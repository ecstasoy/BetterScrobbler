#ifndef SCROBBLER_LYRICSMANAGER_H
#define SCROBBLER_LYRICSMANAGER_H

#include <string>
#include <curl/curl.h>

class LyricsManager {
public:
    static LyricsManager &getInstance() {
        static LyricsManager instance;
        return instance;
    }

    std::string fetchLyrics(const std::string& artist,
                     const std::string& title,
                     const std::string& album,
                     double duration);

private:
    LyricsManager() = default;
    ~LyricsManager() = default;

    static size_t WriteCallback(void* contents, size_t size, size_t nmemb, std::string* userp);
};
#endif //SCROBBLER_LYRICSMANAGER_H
