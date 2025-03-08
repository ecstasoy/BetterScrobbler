//
// Created by Kunhua Huang on 3/7/25.
//

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

    bool scrobble(const std::string &artist,
                  const std::string &track,
                  const std::string &album = "",
                  double duration = 0.0,
                  int timeStamp = 0);

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
