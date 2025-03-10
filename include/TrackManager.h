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
        int beginTimeStamp;
        double lastElapsed;
        double lastDuration;
        double lastFetchTime;
        double lastReportedElapsed;
        double lastNowPlayingSent;
        bool isMusic;
        std::string artist;
        std::string title;
        std::string album;

        TrackState() :
                hasScrobbled(false),
                beginTimeStamp(0),
                lastElapsed(0.0),
                lastDuration(0.0),
                lastFetchTime(0.0),
                lastReportedElapsed(0.0),
                lastNowPlayingSent(0.0),
                isMusic(false) {}
    };

    void processTitleChange(const std::string &artist,
                            const std::string &title,
                            const std::string &album,
                            double playbackRateValue);

    void handlePlaybackStateChange(double playbackRate,
                                   double elapsedValue);

    TrackState *getCurrentTrack() { return currentTrack; }

    const std::string &getLastTitle() const { return lastTitle; }

    const std::string &getLastArtist() const { return lastArtist; }

    const std::string &getLastAlbum() const { return lastAlbum; }

    const std::string getExtractedTitle() const { return extractedTitle; }

    const std::string getExtractedArtist() const { return extractedArtist; }

    void setFromMusicPlatform(bool isFromMusicPlatform) {
        this->isFromMusicPlatform = isFromMusicPlatform;
    }

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
    bool isFromMusicPlatform = false;

    std::string generateTrackId(const std::string &artist,
                                const std::string &title,
                                const std::string &album) {
        return artist + "|" + title + "|" + album;
    }
};

#endif //SCROBBLER_TRACKMANAGER_H
