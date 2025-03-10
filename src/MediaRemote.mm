#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <include/MediaRemote.h>
#include <include/LastFmScrobbler.h>
#include <include/Logger.h>
#include <include/Helper.h>
#include<include/TrackManager.h>

typedef void (*MRMediaRemoteGetNowPlayingInfo_t)(dispatch_queue_t, void(^)(CFDictionaryRef));

class MediaRemote::Impl {
public:
    void *handle = nullptr;
    MRMediaRemoteGetNowPlayingInfo_t MRMediaRemoteGetNowPlayingInfo = nullptr;
    dispatch_source_t timer = nullptr;
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
        auto *currentTrack = trackManager.getCurrentTrack();
        const std::string &lastTitle = trackManager.getLastTitle();
        const std::string &lastArtist = trackManager.getLastArtist();
        const std::string &extractedArtist = trackManager.getExtractedArtist();
        const std::string &extractedTitle = trackManager.getExtractedTitle();

        std::string artist, title, album;
        double durationValue = currentTrack ? currentTrack->lastDuration : 0.0;
        double elapsedValue = currentTrack ? currentTrack->lastElapsed : 0.0;
        double reportedElapsed;
        double playbackRateValue = 0.0;

        extractMetadata(info, artist, title, album, durationValue,
                        currentTrack ? currentTrack->lastDuration : durationValue, playbackRateValue);
        trackManager.setFromMusicPlatform(!artist.empty() && !title.empty() && !album.empty());

        handleFlushedMetadata(artist, title, album);

        // Ensure we are working with non-empty values
        std::string currentTitle = !title.empty() ? title : lastTitle;
        std::string scrobbleArtist = !extractedArtist.empty() ? extractedArtist : !artist.empty() ? artist
                                                                                                  : lastArtist;
        std::string scrobbleTitle = !extractedTitle.empty() ? extractedTitle : !title.empty() ? title : lastTitle;

        if (!title.empty() && title != trackManager.getLastTitle()) {
            trackManager.processTitleChange(artist, title, album, playbackRateValue);
            currentTrack = trackManager.getCurrentTrack();
        }

        if (!currentTrack || !currentTrack->isMusic) {
            return;
        }

        updateElapsedTime(info, reportedElapsed, playbackRateValue, elapsedValue,
                          currentTrack->lastElapsed, currentTrack->lastFetchTime,
                          currentTrack->lastReportedElapsed);

        scrobbler.sendNowPlayingUpdate(scrobbleArtist, scrobbleTitle,
                                       currentTrack->isMusic, album,
                                       currentTrack->lastNowPlayingSent,
                                       playbackRateValue);

        trackManager.handlePlaybackStateChange(playbackRateValue, elapsedValue);
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