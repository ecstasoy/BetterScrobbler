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
        }
    }

    ~Impl() {
        if (handle) {
            dlclose(handle);
        }
    }

    void registerTimer() {
        LOG_INFO("Listening for Now Playing changes");
        playbackTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        if (!playbackTimer) {
            LOG_ERROR("Failed to create dispatch timer");
            return;
        }
        dispatch_source_set_timer(playbackTimer, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC, 0);
        dispatch_source_set_event_handler(playbackTimer, ^{
            fetchNowPlayingInfo();
        });
        dispatch_resume(playbackTimer);

        lyricsTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        if (!lyricsTimer) {
            LOG_ERROR("Failed to create lyrics timer");
            return;
        }
        dispatch_source_set_timer(lyricsTimer,
                                  dispatch_time(DISPATCH_TIME_NOW, 0),
                                  0.05 * NSEC_PER_SEC,
                                  0
        );
        dispatch_source_set_event_handler(lyricsTimer, ^{
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
        });
        dispatch_resume(lyricsTimer);
    }

    void fetchNowPlayingInfo() {
        if (!MRMediaRemoteGetNowPlayingInfo) {
            LOG_ERROR("MediaRemote function not available");
            return;
        }

        MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
            if (!info) {
                LOG_DEBUG("No Now Playing info available");
                return;
            }

            processNowPlayingInfo(info);
        });
    }

    void processNowPlayingInfo(CFDictionaryRef info) {
        auto *currentTrack = trackManager.getCurrentTrack();
        const std::string &lastTitle = trackManager.getLastTitle();
        const std::string &lastArtist = trackManager.getLastArtist();
        const std::string &extractedArtist = trackManager.getExtractedArtist();
        const std::string &extractedTitle = trackManager.getExtractedTitle();

        std::string artist, title, album;
        if (currentTrack) {
            double durationValue = currentTrack->duration;
            double elapsedValue = currentTrack->lastElapsed;
            double reportedElapsed;
            double playbackRateValue = 0.0;

            Helper::extractMetadata(info, artist, title, album, currentTrack->duration, playbackRateValue);
            trackManager.setFromMusicPlatform(!artist.empty() && !title.empty() && !album.empty());

            handleFlushedMetadata(artist, title, album);

            if (!title.empty() && title != lastTitle) {
                trackManager.processTitleChange(artist, title, album, playbackRateValue);
                currentTrack = trackManager.getCurrentTrack();
            }

            if (currentTrack) {
                currentTrack->lastPlaybackRate = playbackRateValue;
            } else {
                LOG_DEBUG("No current track, skipping update");
                return;
            }

            Helper::updateElapsedTime(info, reportedElapsed, playbackRateValue, elapsedValue,
                                      currentTrack->lastElapsed, currentTrack->lastFetchTime,
                                      currentTrack->lastReportedElapsed);

            if (currentTrack->isMusic) {
                scrobbler.sendNowPlayingUpdate(trackManager.getExtractedArtist(), trackManager.getExtractedTitle(),
                                               currentTrack->isMusic, album,
                                               currentTrack->lastNowPlayingSent,
                                               playbackRateValue);
            }

            trackManager.handlePlaybackStateChange(playbackRateValue, elapsedValue);
        }
    }

    void handleFlushedMetadata(std::string &artist, std::string &title, std::string &album) const {
        auto *currentTrack = trackManager.getCurrentTrack();
        const std::string &lastArtist = trackManager.getLastArtist();
        const std::string &lastTitle = trackManager.getLastTitle();
        const std::string &lastAlbum = trackManager.getLastAlbum();

        if (currentTrack && artist.empty() && title.empty() && !lastTitle.empty()) {
            LOG_DEBUG("Metadata was flushed, using cached values");
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