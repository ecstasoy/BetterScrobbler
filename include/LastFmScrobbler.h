#ifndef BETTERSCROBBLER_LASTFMSCROBBLER_H
#define BETTERSCROBBLER_LASTFMSCROBBLER_H

#include <string>
#include <map>
#include <list>
#include <curl/curl.h>

class LastFmScrobbler {
public:
    static LastFmScrobbler &getInstance() {
        static LastFmScrobbler instance;
        return instance;
    }

    bool init();

    void cleanup();

    // Scrobble related
    bool sendNowPlaying(const std::string &artist,
                        const std::string &track,
                        const std::string &album = "",
                        double duration = 0.0);

    void sendNowPlayingUpdate(const std::string &artist,
                              const std::string &title,
                              bool isMusic,
                              const std::string &album,
                              double &lastNowPlayingSent,
                              double playbackRate);

    bool scrobble(const std::string &artist,
                  const std::string &track,
                  const std::string &album = "",
                  double duration = 0.0,
                  int timeStamp = 0);

    void resetScrobbleState(double &lastElapsed,
                            double &lastDuration,
                            double &lastFetchTime,
                            int &beginTimeStamp,
                            bool &hasScrobbled);

    bool shouldScrobble(double elapsed,
                        double duration,
                        double playbackRate,
                        bool isMusic,
                        bool hasScrobbled);

    // Search
    std::string search(const std::string &artist, const std::string &track);

    std::list<std::string> bestMatch(std::string &artist, std::string &track);

private:
    LastFmScrobbler();

    ~LastFmScrobbler();

    LastFmScrobbler(const LastFmScrobbler &) = delete;

    LastFmScrobbler &operator=(const LastFmScrobbler &) = delete;

    CURL *curl;
    std::string lastError;

};

#endif //BETTERSCROBBLER_LASTFMSCROBBLER_H
