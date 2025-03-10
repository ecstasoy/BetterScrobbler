#include <include/TrackManager.h>
#include <include/Logger.h>
#include <include/Helper.h>


void TrackManager::processTitleChange(const std::string &artist, const std::string &title, const std::string &album,
                                      double playbackRateValue) {
    LOG_DEBUG("Title changed: '" + lastTitle + "' -> '" + title + "'");

    if (currentTrack && currentTrack->hasScrobbled && !currentTrack->hasSubmitted) {
        scrobbler.scrobble(currentTrack->artist, currentTrack->title, currentTrack->album,
                           currentTrack->lastDuration,
                           currentTrack->beginTimeStamp);
        currentTrack->hasSubmitted = true;
        LOG_DEBUG("Previous track scrobbled on change");
    }

    bool isMusic = false;

    if (isFromMusicPlatform) {
        extractedArtist = artist;
        extractedTitle = title;
        isMusic = true;
        LOG_DEBUG("Using platform metadata: " + extractedArtist + " - " + extractedTitle);
    } else if (extractMusicInfo(artist, title, extractedArtist, extractedTitle)) {
        isMusic = true;
        LOG_DEBUG("Extracted metadata: " + extractedArtist + " - " + extractedTitle);
    } else if (isValidContent(extractedArtist, extractedTitle)) {
        isMusic = true;
        LOG_DEBUG("Caution! This content might not be valid music: " + extractedArtist + " - " + extractedTitle);
    } else {
        extractedArtist = "";
        extractedTitle = "";
    }

    if (isMusic) {
        LOG_DEBUG("Resetting scrobble state for new track");

        if (trackCache.size() >= MAX_TRACK_CACHE) {
            trackCache.erase(trackCache.begin());
        }

        std::string trackId = generateTrackId(extractedArtist, extractedTitle, album);
        auto &state = trackCache[trackId];

        state.artist = extractedArtist;
        state.title = extractedTitle;
        state.album = album;
        state.isMusic = true;
        state.beginTimeStamp = static_cast<int>(std::time(nullptr));
        state.lastFetchTime = CFAbsoluteTimeGetCurrent();
        state.hasScrobbled = false;
        state.lastElapsed = 0.0;
        state.lastDuration = 0.0;
        state.lastNowPlayingSent = CFAbsoluteTimeGetCurrent();

        currentTrack = &state;
        lastArtist = extractedArtist;
        lastTitle = title;
        lastAlbum = album;

        if (extractedTitle.empty()) {
            LOG_ERROR("Empty scrobble title detected!");
            return;
        }

        std::string playbackState = (playbackRateValue == 0.0) ? "⏸ Paused" :
                                    (playbackRateValue > 0.0) ? "▶️ Playing" : "⏹ Stopped";
        LOG_INFO(playbackState + ": " + extractedArtist + " - " + extractedTitle + " [" + album + "]  (" +
                 std::to_string(currentTrack->lastDuration) + " sec)");
    } else {
        currentTrack = nullptr;
        lastTitle = title;
        LOG_INFO("Skipping non-music content");
    }
}

void TrackManager::handlePlaybackStateChange(double playbackRateValue, double elapsedValue) {
    if (!currentTrack) return;

    double progressPercentage = (currentTrack->lastDuration > 0.0)
                                ? (elapsedValue / currentTrack->lastDuration) * 100.0
                                : 0.0;

    if (!currentTrack->hasScrobbled &&
        scrobbler.shouldScrobble(elapsedValue, currentTrack->lastDuration,
                                 playbackRateValue, currentTrack->isMusic, false)) {
        currentTrack->hasScrobbled = true;
        LOG_DEBUG("Track reached scrobble threshold");
    }

    std::string playbackState = (playbackRateValue == 0.0) ? "⏸ Paused" :
                                (playbackRateValue > 0.0) ? "▶️ Playing" : "⏹ Stopped";

    static double lastPlaybackRate = 0.0;
    if (currentTrack->hasScrobbled && !currentTrack->hasSubmitted && playbackRateValue <= 0.0 && lastPlaybackRate > 0.0) {
        scrobbler.scrobble(currentTrack->artist, currentTrack->title, currentTrack->album,
                           currentTrack->lastDuration,
                           currentTrack->beginTimeStamp);
        currentTrack->hasSubmitted = true;
        LOG_DEBUG("Track finished/changed - sending scrobble request");
    }
    lastPlaybackRate = playbackRateValue;

    if (playbackState != lastPlaybackState) {
        lastPlaybackState = playbackState;
        LOG_INFO(
                playbackState + ": " + currentTrack->artist + " - " + currentTrack->title + " [" + currentTrack->album +
                "]  (" +
                std::to_string(currentTrack->lastDuration) + " sec)");
    }

    if (currentTrack->title == lastTitle && progressPercentage < 10.0 && currentTrack->hasScrobbled &&
        playbackRateValue > 0.0) {
        LOG_INFO("Song restarted (based on elapsed time drop)! Resetting scrobble state");
        currentTrack->hasScrobbled = false;
        currentTrack->hasSubmitted = false;
        currentTrack->lastElapsed = 0.0;
        currentTrack->lastFetchTime = CFAbsoluteTimeGetCurrent();
        currentTrack->beginTimeStamp = static_cast<int>(std::time(nullptr));
    }
}