#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <include/MediaRemote.h>
#include <include/LastFmScrobbler.h>
#include <include/Logger.h>
#include <include/Helper.h>
#include<include/TrackManager.h>
#import "include/LyricsManager.h"

typedef void (*MRMediaRemoteGetNowPlayingInfo_t)(dispatch_queue_t, void(^)(CFDictionaryRef));

class MediaRemote::Impl {
public:
    void *handle = nullptr;
    MRMediaRemoteGetNowPlayingInfo_t MRMediaRemoteGetNowPlayingInfo = nullptr;
    dispatch_source_t playbackTimer = nullptr;
    dispatch_source_t lyricsTimer = nullptr;
    LastFmScrobbler &scrobbler = LastFmScrobbler::getInstance();
    TrackManager &trackManager = TrackManager::getInstance();
    std::mutex mediaRemoteMutex;
    bool isInitialized = false;

    Impl() {
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (!handle) {
            LOG_ERROR("Failed to load MediaRemote.framework");
            return;
        }

        MRMediaRemoteGetNowPlayingInfo =
                (MRMediaRemoteGetNowPlayingInfo_t) dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
        if (!MRMediaRemoteGetNowPlayingInfo) {
            LOG_ERROR("Failed to find MRMediaRemoteGetNowPlayingInfo");
            return;
        }

        isInitialized = true;
    }

    ~Impl() {
        if (playbackTimer) {
            dispatch_source_cancel(playbackTimer);
            dispatch_release(playbackTimer);
            playbackTimer = nullptr;
        }
        if (lyricsTimer) {
            dispatch_source_cancel(lyricsTimer);
            dispatch_release(lyricsTimer);
            lyricsTimer = nullptr;
        }
        if (handle) {
            dlclose(handle);
            handle = nullptr;
        }
    }

    void registerTimer() {
        if (!isInitialized) {
            LOG_ERROR("MediaRemote not properly initialized");
            return;
        }

        LOG_INFO("Listening for Now Playing changes");
        
        // 创建播放状态检查定时器
        playbackTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        if (!playbackTimer) {
            LOG_ERROR("Failed to create dispatch timer");
            return;
        }
        
        dispatch_source_set_timer(playbackTimer, 
                                dispatch_time(DISPATCH_TIME_NOW, 0), 
                                NSEC_PER_SEC, 
                                NSEC_PER_SEC / 10);
        
        dispatch_source_set_event_handler(playbackTimer, ^{
            @autoreleasepool {
                fetchNowPlayingInfo();
            }
        });
        
        dispatch_resume(playbackTimer);

        // 创建歌词显示定时器
        lyricsTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        if (!lyricsTimer) {
            LOG_ERROR("Failed to create lyrics timer");
            return;
        }
        
        dispatch_source_set_timer(lyricsTimer,
                                dispatch_time(DISPATCH_TIME_NOW, 0),
                                0.05 * NSEC_PER_SEC,
                                0.05 * NSEC_PER_SEC / 10);
        
        dispatch_source_set_event_handler(lyricsTimer, ^{
            @autoreleasepool {
                auto &lyricsManager = LyricsManager::getInstance();
                auto &config = Config::getInstance();
                auto *currentTrack = trackManager.getCurrentTrack();
                if (!currentTrack) return;

                double now = CFAbsoluteTimeGetCurrent();
                double interpolatedTime = currentTrack->lastElapsed;

                if (currentTrack->lastPlaybackRate > 0.0) {
                    interpolatedTime += (now - currentTrack->lastFetchTime) * currentTrack->lastPlaybackRate;
                }

                if (config.isShowLyrics()) {
                    if (config.isPreferSyncedLyrics() && currentTrack->hasSyncedLyrics) {
                        lyricsManager.displaySyncedLyrics(
                                currentTrack->lastPlaybackRate,
                                interpolatedTime
                        );
                    } else if (!currentTrack->plainLyrics.empty()) {
                        lyricsManager.displayPlainLyrics(
                                currentTrack->lastPlaybackRate,
                                interpolatedTime
                        );
                    }
                }
            }
        });
        
        dispatch_resume(lyricsTimer);
    }

    void fetchNowPlayingInfo() {
        if (!MRMediaRemoteGetNowPlayingInfo) {
            LOG_ERROR("MediaRemote function not available");
            return;
        }

        @autoreleasepool {
            void (^callback)(CFDictionaryRef) = ^(CFDictionaryRef info) {
                if (!info) {
                    LOG_DEBUG("No Now Playing info available");
                    return;
                }

                @autoreleasepool {
                    @try {
                        LOG_DEBUG("Received Now Playing info, creating copy");
                        CFDictionaryRef infoCopy = CFDictionaryCreateCopy(kCFAllocatorDefault, info);
                        if (!infoCopy) {
                            LOG_ERROR("Failed to create info dictionary copy");
                            return;
                        }

                        LOG_DEBUG("Processing Now Playing info");
                        processNowPlayingInfo(infoCopy);
                        LOG_DEBUG("Finished processing Now Playing info");
                        
                        CFRelease(infoCopy);
                        LOG_DEBUG("Released info dictionary copy");
                    } @catch (NSException *exception) {
                        LOG_ERROR("Exception in processNowPlayingInfo: " + std::string([[exception description] UTF8String]));
                    }
                }
            };

            LOG_DEBUG("Creating callback block copy");
            void (^callbackCopy)(CFDictionaryRef) = Block_copy(callback);
            if (!callbackCopy) {
                LOG_ERROR("Failed to copy callback block");
                return;
            }

            LOG_DEBUG("Requesting Now Playing info");
            MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), callbackCopy);
            LOG_DEBUG("Released callback block copy");
            Block_release(callbackCopy);
        }
    }

    void processNowPlayingInfo(CFDictionaryRef info) {
        if (!info) {
            LOG_ERROR("Invalid info dictionary");
            return;
        }

        std::lock_guard<std::mutex> lock(mediaRemoteMutex);
        
        @autoreleasepool {
            auto *currentTrack = trackManager.getCurrentTrack();
            if (!currentTrack) {
                LOG_DEBUG("No current track available");
                return;
            }

            const std::string &lastTitle = trackManager.getLastTitle();
            const std::string &lastArtist = trackManager.getLastArtist();
            const std::string &extractedArtist = trackManager.getExtractedArtist();
            const std::string &extractedTitle = trackManager.getExtractedTitle();

            LOG_DEBUG("Processing Now Playing info - Last title: '" + lastTitle + 
                     "', Last artist: '" + lastArtist + "'");

            std::string artist, title, album;
            double durationValue = currentTrack->duration;
            double elapsedValue = currentTrack->lastElapsed;
            double reportedElapsed = 0.0;
            double playbackRateValue = 0.0;

            @try {
                Helper::extractMetadata(info, artist, title, album, currentTrack->duration, playbackRateValue);
                if (artist.empty() && title.empty() && album.empty()) {
                    LOG_DEBUG("No metadata available in info dictionary");
                    handleFlushedMetadata(artist, title, album);
                }

                LOG_DEBUG("Extracted metadata - Artist: '" + artist + 
                         "', Title: '" + title + 
                         "', Album: '" + album + 
                         "', Duration: " + std::to_string(currentTrack->duration) +
                         ", Playback rate: " + std::to_string(playbackRateValue));

                bool isFromMusicPlatform = !artist.empty() && !title.empty() && !album.empty();
                trackManager.setFromMusicPlatform(isFromMusicPlatform);
                LOG_DEBUG("Is from music platform: " + std::to_string(isFromMusicPlatform));

                if (!title.empty() && title != lastTitle) {
                    LOG_DEBUG("Title changed, processing title change");
                    trackManager.processTitleChange(artist, title, album, playbackRateValue);
                    currentTrack = trackManager.getCurrentTrack();
                    if (!currentTrack) {
                        LOG_ERROR("Failed to get current track after title change");
                        return;
                    }
                }

                currentTrack->lastPlaybackRate = playbackRateValue;
                LOG_DEBUG("Updated playback rate: " + std::to_string(playbackRateValue));

                elapsedValue = Helper::updateElapsedTime(info, reportedElapsed, playbackRateValue, elapsedValue,
                                          currentTrack->lastElapsed, currentTrack->lastFetchTime,
                                          currentTrack->lastReportedElapsed);
                
                LOG_DEBUG("Updated elapsed time - Reported: " + std::to_string(reportedElapsed) +
                         ", Current: " + std::to_string(currentTrack->lastElapsed));

                if (currentTrack->isMusic && playbackRateValue > 0.0) {
                    LOG_DEBUG("Sending Now Playing update");
                    scrobbler.sendNowPlayingUpdate(currentTrack->extractArtist,
                                                  currentTrack->extractTitle,
                                                  currentTrack->isMusic, album,
                                                  currentTrack->lastNowPlayingSent,
                                                  playbackRateValue);
                }

                LOG_DEBUG("Handling playback state change");
                trackManager.handlePlaybackStateChange(playbackRateValue, elapsedValue);
            } @catch (NSException *exception) {
                LOG_ERROR("Exception while processing now playing info: " + std::string([[exception description] UTF8String]));
                if (currentTrack) {
                    currentTrack->lastPlaybackRate = 0.0;
                }
            }
        }
    }

    void handleFlushedMetadata(std::string &artist, std::string &title, std::string &album) const {
        auto *currentTrack = trackManager.getCurrentTrack();
        if (!currentTrack) {
            return;
        }

        const std::string &lastArtist = trackManager.getLastArtist();
        const std::string &lastTitle = trackManager.getLastTitle();
        const std::string &lastAlbum = trackManager.getLastAlbum();

        if (artist.empty() && title.empty() && !lastTitle.empty()) {
            // Metadata was flushed, using cached values
            artist = lastArtist;
            title = lastTitle;
            album = lastAlbum;
        }
    }
};

#pragma mark - MediaRemoteBridge

MediaRemote::MediaRemote()
        : impl(new Impl) {
}

MediaRemote::~MediaRemote() {
    delete impl;
}

void MediaRemote::registerForNowPlayingNotifications() {
    if (impl) impl->registerTimer();
}