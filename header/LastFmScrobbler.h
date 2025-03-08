//
// Created by Kunhua Huang on 3/7/25.
//

#ifndef BETTERSCROBBLER_LASTFMSCROBBLER_H
#define BETTERSCROBBLER_LASTFMSCROBBLER_H

#include <string>
#include <curl/curl.h>

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

private:
    LastFmScrobbler();

    ~LastFmScrobbler();

    LastFmScrobbler(const LastFmScrobbler &) = delete;

    LastFmScrobbler &operator=(const LastFmScrobbler &) = delete;

    std::string sendGetRequest(const std::string &url, int maxRetries = 3);

    std::string sendPostRequest(const std::string &url,
                                const std::map<std::string, std::string> &params,
                                int maxRetries = 3);

    bool processResponse(const std::string &response);

    bool shouldRetry(const std::string &response, int attempt);

    void waitBeforeRetry(int attempt);

    std::string buildApiUrl(const std::string &method,
                            const std::map<std::string, std::string> &params);

    CURL *curl;
    std::string lastError;
    std::chrono::system_clock::time_point lastRequestTime;
    static constexpr int MIN_REQUEST_INTERVAL_MS = 250;

};
#endif //BETTERSCROBBLER_LASTFMSCROBBLER_H
