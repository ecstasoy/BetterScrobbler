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

    void parsePlainLyrics(const std::string& lyrics);

    void displaySyncedLyrics(double playbackRateValue, double elapsedValue);

    void displayPlainLyrics(double playbackRateValue, double elapsedValue);

    void clearLyricsArea();

    void forceRefreshLyrics();

private:
    LyricsManager() = default;
    ~LyricsManager() = default;

    enum KeyAction {
        NO_ACTION,
        QUIT,
        SCROLL
    };

    static size_t WriteCallback(void* contents, size_t size, size_t nmemb, std::string* userp);

    WINDOW *lyricsWin = nullptr;
    WINDOW *headerWin = nullptr;
    WINDOW *contentWin = nullptr;
    bool manualScrollMode = false;
    bool ncursesInitialized = false;
    int autoScrollPosition = 0;
    int scrollPosition = 0;
    int maxVisibleLines = 0;
    int totalLines = 0;
    bool forceRedraw = false;

    void initNcurses();
    void endNcurses();
    void drawHeader(const std::string& artist, const std::string& title, double elapsed, double duration);
    void drawSyncedLyrics(const std::vector<std::pair<int, std::string>>& lyrics, int currentIndex);
    void drawPlainLyrics(const std::vector<std::string> &lyrics);
    static std::string formatTime(double seconds);
    static std::string truncateText(const std::string& text, int maxWidth);
    KeyAction checkKeypress();

};
#endif //SCROBBLER_LYRICSMANAGER_H
