#ifndef SCROBBLER_TRACKMANAGER_H
#define SCROBBLER_TRACKMANAGER_H

#include <string>
#include <map>
#include "LastFmScrobbler.h"

class TrackManager {
public:
    static TrackManager &getInstance() {
        static TrackManager instance;
        return instance;
    }
    TrackManager() {
        std::string emptyTrackId = generateTrackId("", "", "");
        auto &state = trackCache[emptyTrackId];
        state.isMusic = false;
        currentTrack = &state;
    }

    struct TrackState {
        bool hasScrobbled;
        bool hasSubmitted;
        bool hasSyncedLyrics;
        int beginTimeStamp;
        double lastElapsed;
        double duration;
        double lastFetchTime;
        double lastReportedElapsed;
        double lastNowPlayingSent;
        double lastPlaybackRate;
        bool isMusic;
        std::string artist;
        std::string extractArtist;
        std::string title;
        std::string extractTitle;
        std::string album;
        std::string plainLyrics;
        std::string syncedLyrics;
        std::vector<std::string> parsedPlainLyrics;
        std::vector<std::pair<int, std::string>> parsedSyncedLyrics;
        int currentLyricIndex;

        TrackState() :
                hasScrobbled(false),
                hasSubmitted(false),
                beginTimeStamp(0),
                lastElapsed(0.0),
                duration(0.0),
                lastFetchTime(0.0),
                lastReportedElapsed(0.0),
                lastNowPlayingSent(0.0),
                lastPlaybackRate(0.0),
                isMusic(false) {}
    };

    void processTitleChange(const std::string &artist,
                            const std::string &title,
                            const std::string &album,
                            double playbackRateValue);

    void handlePlaybackStateChange(double playbackRate,
                                   double elapsedValue);

    void updateTrackInfo(const std::string &artist,
                         const std::string &title,
                         const std::string &album,
                         bool isMusic,
                         double duration,
                         double elapsedValue);

    TrackState *getCurrentTrack() { return currentTrack; }

    [[nodiscard]] const std::string &getLastTitle() const { return lastTitle; }

    [[nodiscard]] const std::string &getLastArtist() const { return lastArtist; }

    [[nodiscard]] const std::string &getLastAlbum() const { return lastAlbum; }

    [[nodiscard]] std::string getExtractedTitle() const {
        return currentTrack->extractTitle;
    }

    [[nodiscard]] std::string getExtractedArtist() const {
        return currentTrack->extractArtist;
    }

    void setFromMusicPlatform(bool fromMusicPlatform) {
        this->isFromMusicPlatform = fromMusicPlatform;
    }

    bool isCachedTrak(std::string trackId) {
        return trackCache.find(trackId) != trackCache.end();
    }

    TrackState *getCachedTrack(std::string trackId) {
        return &trackCache[trackId];
    }

    static std::string generateTrackId(const std::string &artist,
                                       const std::string &title,
                                       const std::string &album);

    bool isFromMusicPlatform = false;
private:
    static const size_t MAX_TRACK_CACHE = 50;
    std::map<std::string, TrackState> trackCache;
    TrackState *currentTrack = nullptr;
    LastFmScrobbler &scrobbler = LastFmScrobbler::getInstance();

    std::string lastTitle;
    std::string lastArtist;
    std::string lastAlbum;
    std::string lastPlaybackState;
    std::string extractedTitle;
    std::string extractedArtist;

    std::mutex trackMutex;
};

#endif //SCROBBLER_TRACKMANAGER_H
