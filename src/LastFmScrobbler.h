//
// Created by Kunhua Huang on 3/7/25.
//

#ifndef BETTERSCROBBLER_LASTFMSCROBBLER_H
#define BETTERSCROBBLER_LASTFMSCROBBLER_H
#include <string>

class LastFmScrobbler {
public:
    static LastFmScrobbler &getInstance() {
        static LastFmScrobbler instance;
        return instance;
    }

    bool init();

    void cleanup();

    // Authentication related
    std::string getAuthToken();

    void openAuthPage(const std::string &token);

    std::string getSessionKey(const std::string &token);

    void saveSessionKey(const std::string &sessionKey);

    std::string loadSessionKey();

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

    // Credentials
    std::string getApiKey();

    std::string getApiSecret();
};
#endif //BETTERSCROBBLER_LASTFMSCROBBLER_H
