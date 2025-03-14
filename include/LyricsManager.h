#ifndef SCROBBLER_LYRICSMANAGER_H
#define SCROBBLER_LYRICSMANAGER_H

#include <string>
#include <curl/curl.h>
#include <ncurses.h>

class LyricsManager {
public:
    static LyricsManager &getInstance() {
        static LyricsManager instance;
        return instance;
    }

    void fetchLyrics(const std::string& artist,
                     const std::string& title,
                     const std::string& album,
                     double duration);

    void parseSyncedLyrics(const std::string& lyrics);

    void displayLyrics(double playbackRateValue, double elapsedValue);

    int getTerminalHeight();

    void clearLyricsArea();

private:
    LyricsManager() = default;
    ~LyricsManager() = default;

    static size_t WriteCallback(void* contents, size_t size, size_t nmemb, std::string* userp);

    WINDOW *lyricsWin = nullptr;
    bool ncursesInitialized = false;

    void initNcurses();

    void endNcurses();

};
#endif //SCROBBLER_LYRICSMANAGER_H
