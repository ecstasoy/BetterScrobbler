//
// Created by Kunhua Huang on 3/7/25.
//

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <header/MediaRemote.h>
#include <header/Logger.h>
#include <header/Helper.h>

typedef void (*MRMediaRemoteGetNowPlayingInfo_t)(dispatch_queue_t, void(^)(CFDictionaryRef));

class MediaRemote::Impl {
public:
    void *handle = nullptr;
    MRMediaRemoteGetNowPlayingInfo_t MRMediaRemoteGetNowPlayingInfo = nullptr;
    dispatch_source_t timer = nullptr;
    LastFmScrobbler &scrobbler = LastFmScrobbler::getInstance();

    std::string lastTitle;
    std::string lastArtist;
    std::string lastAlbum;
    std::string lastPlaybackState;
    std::string extractedTitle;
    std::string extractedArtist;
    double lastFetchTime = 0.0;
    double lastDuration = 0.0;
    double lastElapsed = 0.0;
    double lastReportedElapsed = 0.0;
    double lastNowPlayingSent = 0.0;
    int beginTimeStamp = 0;
    bool hasScrobbled = false;
    bool isMusic = true;
    bool isFromMusicPlatform = false;

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
        LOG_INFO("Listening for Now Playing changes every 2 seconds...");
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        if (!timer) {
            LOG_ERROR("Failed to create dispatch timer");
            return;
        }
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 2 * NSEC_PER_SEC, 0);
        dispatch_source_set_event_handler(timer, ^{
            fetchNowPlayingInfo();
        });
        dispatch_resume(timer);
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
        std::string artist, title, album;
        double durationValue = lastDuration;
        double elapsedValue = lastElapsed;
        double reportedElapsed;
        double playbackRateValue = 0.0;

        extractMetadata(info, artist, title, album, durationValue, lastDuration, playbackRateValue);
        isFromMusicPlatform = !artist.empty() && !title.empty() && !album.empty();

        handleFlushedMetadata(artist, title, album);

        // Ensure we are working with non-empty values
        std::string currentTitle = !title.empty() ? title : lastTitle;
        std::string scrobbleArtist = !extractedArtist.empty() ? extractedArtist : !artist.empty() ? artist
                                                                                                  : lastArtist;
        std::string scrobbleTitle = !extractedTitle.empty() ? extractedTitle : !title.empty() ? title : lastTitle;

        if (!currentTitle.empty() && currentTitle != lastTitle) {
            processTitleChange(currentTitle, artist, title, album, scrobbleArtist, scrobbleTitle, playbackRateValue);
        }

        // Skip processing if it's not music
        if (!isMusic) {
            return;
        }

        updateElapsedTime(info, reportedElapsed, playbackRateValue, elapsedValue, lastElapsed, lastFetchTime,
                          lastReportedElapsed);
        sendNowPlayingUpdate(scrobbleArtist, scrobbleTitle, isMusic, album, lastNowPlayingSent, playbackRateValue);
        handlePlaybackStateChange(currentTitle, scrobbleArtist, scrobbleTitle, album, playbackRateValue, elapsedValue);
    }

    void processTitleChange(const std::string &currentTitle, const std::string &artist, const std::string &title,
                            const std::string &album, std::string &scrobbleArtist, std::string &scrobbleTitle,
                            double playbackRateValue) {
        LOG_DEBUG("Title changed: '" + lastTitle + "' -> '" + currentTitle + "'");

        std::string newArtist, newTitle;
        if (isFromMusicPlatform) {
            scrobbleArtist = artist;
            scrobbleTitle = title;
            extractedArtist = artist;
            extractedTitle = title;
            isMusic = true;
            LOG_DEBUG("Using platform metadata: " + scrobbleArtist + " - " + scrobbleTitle);
        } else if (extractMusicInfo(currentTitle, newArtist, newTitle)) {
            extractedArtist = newArtist;
            extractedTitle = newTitle;
            scrobbleArtist = extractedArtist;
            scrobbleTitle = extractedTitle;
            isMusic = true;
            LOG_INFO("Using extracted music info: " + scrobbleArtist + " - " + scrobbleTitle);
        } else {
            extractedArtist = "";
            extractedTitle = "";
            isMusic = isValidMusicContent(artist, title, album);
            if (isMusic) {
                scrobbleArtist = artist;
                scrobbleTitle = currentTitle;
                LOG_DEBUG("Using original title: " + scrobbleTitle);
            }
        }

        if (isMusic) {
            LOG_DEBUG("Resetting scrobble state for new track");
            resetScrobbleState(lastElapsed, lastDuration, lastFetchTime, beginTimeStamp, hasScrobbled);
            if (scrobbleTitle.empty()) {
                LOG_ERROR("Empty scrobble title detected!");
                return;
            }

            std::string playbackState = (playbackRateValue == 0.0) ? "⏸ Paused" :
                                        (playbackRateValue > 0.0) ? "▶️ Playing" : "⏹ Stopped";
            LOG_INFO(playbackState + ": " + scrobbleArtist + " - " + scrobbleTitle + " [" + album + "]  (" +
                     std::to_string(lastDuration) + " sec)");
        } else {
            LOG_INFO("Skipping non-music content");
        }

        // Update last known values after processing
        lastArtist = scrobbleArtist;
        lastTitle = currentTitle;
        lastAlbum = album;
    }

    void handleFlushedMetadata(std::string &artist, std::string &title, std::string &album) const {
        if (isMusic && artist.empty() && title.empty() && !lastTitle.empty()) {
            LOG_DEBUG("Metadata will be flushed, using cached values");
            artist = lastArtist;
            title = lastTitle;
            album = lastAlbum;
        }
    }

    void handlePlaybackStateChange(const std::string &currentTitle, const std::string &scrobbleArtist,
                                   const std::string &scrobbleTitle, const std::string &album, double playbackRateValue,
                                   double elapsedValue) {
        double progressPercentage = (lastDuration > 0.0)
                                    ? (elapsedValue / lastDuration) * 100.0
                                    : 0.0;

        std::string playbackState = (playbackRateValue == 0.0) ? "⏸ Paused" :
                                    (playbackRateValue > 0.0) ? "▶️ Playing" : "⏹ Stopped";

        if (playbackState != lastPlaybackState) {
            lastPlaybackState = playbackState;
            LOG_INFO(playbackState + ": " + scrobbleArtist + " - " + scrobbleTitle + " [" + album + "]  (" +
                     std::to_string(lastDuration) + " sec)");
        }

        if (currentTitle == lastTitle && progressPercentage < 10.0 && hasScrobbled && playbackRateValue > 0.0) {
            LOG_INFO("Song restarted (based on elapsed time drop)! Resetting scrobble state");
            hasScrobbled = false;
            lastElapsed = 0.0;
            lastFetchTime = CFAbsoluteTimeGetCurrent();
            beginTimeStamp = static_cast<int>(std::time(nullptr));
        }

        if (shouldScrobble(elapsedValue, lastDuration, playbackRateValue, isMusic, hasScrobbled)) {
            scrobbler.scrobble(scrobbleArtist, scrobbleTitle, album, lastDuration, beginTimeStamp);
            hasScrobbled = true;
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