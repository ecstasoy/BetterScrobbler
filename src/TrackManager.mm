#include <include/TrackManager.h>
#include <include/Logger.h>
#include <include/Helper.h>
#include <include/LyricsManager.h>
#include <sstream>
#include <sys/ioctl.h>
#include <unistd.h>

auto &config = Config::getInstance();
auto &lyricsManager = LyricsManager::getInstance();

void TrackManager::processTitleChange(const std::string &artist, const std::string &title, const std::string &album,
                                      double playbackRateValue) {
    LOG_DEBUG("Title changed: '" + lastTitle + "' -> '" + title + "'");

    if (currentTrack && currentTrack->hasScrobbled && !currentTrack->hasSubmitted&& currentTrack -> isMusic) {
        scrobbler.scrobble(currentTrack->artist, currentTrack->title, currentTrack->album,
                           currentTrack->lastDuration,
                           currentTrack->beginTimeStamp);
        currentTrack->hasSubmitted = true;
        LOG_DEBUG("Previous track scrobbled on change");
    }

    lyricsManager.clearLyricsArea();

    bool isMusic = false;
    extractedArtist = artist;
    extractedTitle = title;

    if (isFromMusicPlatform) {
        isMusic = true;
        LOG_DEBUG("Using platform metadata: " + extractedArtist + " - " + extractedTitle);
    } else if (extractMusicInfo(artist, title, extractedArtist, extractedTitle)) {
        isMusic = true;
        LOG_DEBUG("Extracted metadata: " + extractedArtist + " - " + extractedTitle);
    } else if (isValidContent(extractedArtist, extractedTitle)) {
        isMusic = true;
        LOG_DEBUG("Caution! This content might not be valid music: " + extractedArtist + " - " + extractedTitle);
    }

    if (isMusic) {
        updateTrackInfo(extractedArtist, extractedTitle, album, isMusic, 0.0, 0.0);
        lastTitle = title;
        LOG_INFO("⏭️ Switched to: " + extractedArtist + " - " + extractedTitle + " [" + album + "]  (" +
                 std::to_string(currentTrack->lastDuration) + " sec)");
        LOG_DEBUG("Resetting scrobble state for new track");

        if (config.isShowLyrics()) {

            LOG_DEBUG("hasSyncedLyrics: " + std::to_string(currentTrack->hasSyncedLyrics));
            LOG_DEBUG("preferSyncedLyrics: " + std::to_string(config.isPreferSyncedLyrics()));
            LOG_DEBUG("plainLyrics length: " + std::to_string(currentTrack->plainLyrics.length()));
            LOG_DEBUG("syncedLyrics length: " + std::to_string(currentTrack->syncedLyrics.length()));
            LOG_DEBUG("parsedSyncedLyrics size: " + std::to_string(currentTrack->parsedSyncedLyrics.size()));

            if (currentTrack->hasSyncedLyrics && config.isPreferSyncedLyrics()) {
                LOG_INFO("Synced lyrics found for: " + currentTrack->artist + " - " + currentTrack->title);
            } else if (!currentTrack->plainLyrics.empty()) {
                LOG_INFO("Plain lyrics found for: " + currentTrack->artist + " - " + currentTrack->title);
                std::cout << "\033[1;31m" << "\n--- Lyrics start ---" << "\033[0m" << std::endl;
                std::cout << "\033[1;35m" << currentTrack->plainLyrics << "\033[0m" << std::endl;
                std::cout << "\033[1;31m" << "--- Lyrics end ---\n" << "\033[0m" << std::endl;
            } else {
                LOG_INFO("No lyrics found for: " + currentTrack->artist + " - " + currentTrack->title);
            }
        }
    } else {
        updateTrackInfo(artist, title, album, isMusic, 0.0, 0.0);
        LOG_INFO("⏭️ Switched to: " + title);
        LOG_INFO("Detected non-music content: " + artist + " - " + title + ", skipping...");
    }
}

void TrackManager::handlePlaybackStateChange(double playbackRateValue, double elapsedValue) {
    if (!currentTrack) return;

    double progressPercentage = (currentTrack->lastDuration > 0.0)
                                ? (elapsedValue / currentTrack->lastDuration) * 100.0
                                : 0.0;

    if (!currentTrack->hasScrobbled &&
        LastFmScrobbler::shouldScrobble(elapsedValue, currentTrack->lastDuration,
                                 playbackRateValue, currentTrack->isMusic)) {
        currentTrack->hasScrobbled = true;
        LOG_DEBUG("Track reached scrobble threshold");
    }

    std::string playbackState = (playbackRateValue == 0.0) ? "⏸️ Paused" :
                                (playbackRateValue > 0.0) ? "▶️ Playing" : "⏹️ Stopped";

    if (playbackState != lastPlaybackState) {
        lastPlaybackState = playbackState;
        if (currentTrack->isMusic) {
            LOG_INFO(
                    playbackState + ": " + currentTrack->artist + " - " + currentTrack->title + " [" + currentTrack->album +
                    "]  (" +
                    std::to_string(currentTrack->lastDuration) + " sec)");
        } else {
            LOG_INFO(playbackState + ": " + currentTrack->title);
        }
    }

    if (currentTrack->title == lastTitle && progressPercentage < 10.0 && currentTrack->hasScrobbled &&
        playbackRateValue > 0.0) {
        if (currentTrack->hasScrobbled && !currentTrack->hasSubmitted && currentTrack -> isMusic) {
            scrobbler.scrobble(currentTrack->artist, currentTrack->title, currentTrack->album,
                               currentTrack->lastDuration,
                               currentTrack->beginTimeStamp);
            currentTrack->hasSubmitted = true;
        }
        LOG_INFO("Song restarted (based on elapsed time drop)! Resetting scrobble state");
        updateTrackInfo(currentTrack->artist, currentTrack->title, currentTrack->album,
                        currentTrack->isMusic, currentTrack->lastDuration, elapsedValue);
    }

    lyricsManager.displayLyrics(playbackRateValue, elapsedValue);
}

void TrackManager::updateTrackInfo(const std::string &artist, const std::string &title, const std::string &album,
                                   bool isMusic, double duration, double elapsedValue) {
    std::string trackId = generateTrackId(artist, title, album);
    auto &state = trackCache[trackId];

    if (trackCache.size() >= MAX_TRACK_CACHE) {
        trackCache.erase(trackCache.begin());
    }

    state.artist = artist;
    state.title = title;
    state.album = album;
    state.isMusic = isMusic;
    state.beginTimeStamp = static_cast<int>(std::time(nullptr));
    state.lastFetchTime = CFAbsoluteTimeGetCurrent();
    state.hasScrobbled = false;
    state.hasSubmitted = false;
    state.lastElapsed = elapsedValue;
    state.lastDuration = duration;
    state.lastNowPlayingSent = CFAbsoluteTimeGetCurrent();
    state.plainLyrics = "";
    state.syncedLyrics = "";
    state.hasSyncedLyrics = false;
    state.parsedSyncedLyrics.clear();
    state.currentLyricIndex = -1;

    currentTrack = &state;
    lastArtist = artist;
    lastTitle = title;
    lastAlbum = album;

    LyricsManager::getInstance().fetchLyrics(
            artist,
            title,
            album,
            state.lastDuration
    );
}