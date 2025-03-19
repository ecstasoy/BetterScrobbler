#include "include/LyricsManager.h"
#include "include/TrackManager.h"
#include "include/Logger.h"
#include "include/UrlUtils.h"
#include "include/Helper.h"
#include "../lib/json.hpp"
#include <sstream>
#include <curl/curl.h>
#include <regex>
#include <locale.h>

using json = nlohmann::json;

void LyricsManager::fetchLyrics(const std::string &artist, const std::string &title, const std::string &album,
                                double duration) {
    TrackManager::TrackState *currentTrack = TrackManager::getInstance().getCurrentTrack();
    auto &config = Config::getInstance();
    if (!currentTrack) return;

    currentTrack->plainLyrics = "";
    currentTrack->syncedLyrics = "";
    currentTrack->hasSyncedLyrics = false;
    currentTrack->parsedPlainLyrics.clear();
    currentTrack->parsedSyncedLyrics.clear();
    currentTrack->currentLyricIndex = -1;

    forceRefreshLyrics();

    if (!config.isShowLyrics()) {
        return;
    }

    CURL *curl = curl_easy_init();
    if (!curl) {
        LOG_ERROR("Failed to initialize CURL");
        return;
    }

    std::string url = "https://lrclib.net/api/get?";
    url += "artist_name=" + UrlUtils::urlEncode(artist);
    url += "&track_name=" + UrlUtils::urlEncode(title);
    if (!album.empty()) {
        url += "&album_name=" + UrlUtils::urlEncode(album);
    }
    if (duration > 0) {
        url += "&duration=" + std::to_string(static_cast<int>(duration));
    }

    struct curl_slist *headers = nullptr;
    headers = curl_slist_append(headers,
                                "Lrclib-Client: BetterScrobbler v1.1.1 (https://github.com/ecstasoy/BetterScrobbler)");
    std::string response;

    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);

    CURLcode res = curl_easy_perform(curl);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (res != CURLE_OK) {
        LOG_ERROR("CURL error: " + std::string(curl_easy_strerror(res)));
        return;
    }

    if (response.empty()) {
        LOG_INFO("No lyrics found");
        return;
    }

    LOG_DEBUG("Lyrics response: " + response);

    json j;
    try {
        j = json::parse(response);
    } catch (const std::exception &e) {
        LOG_ERROR("Failed to parse JSON: " + std::string(e.what()));
    }

    if (j.contains("statusCode") || j.contains("message")) {
        LOG_INFO("No lyrics found: " + j.value("message", "Unknown error"));
    }

    if (j.contains("plainLyrics") && !j["plainLyrics"].is_null()) {
        currentTrack->plainLyrics = j["plainLyrics"];
        parsePlainLyrics(currentTrack->plainLyrics);
    } else {
        currentTrack->plainLyrics = "";
    }

    if (j.contains("syncedLyrics") && !j["syncedLyrics"].is_null()) {
        currentTrack->syncedLyrics = j["syncedLyrics"];
        parseSyncedLyrics(currentTrack->syncedLyrics);
    } else {
        currentTrack->syncedLyrics = "";
        currentTrack->hasSyncedLyrics = false;
    }

    currentTrack->hasSyncedLyrics = !currentTrack->parsedSyncedLyrics.empty();
}

void LyricsManager::parseSyncedLyrics(const std::string &lyrics) {
    TrackManager::TrackState *currentTrack = TrackManager::getInstance().getCurrentTrack();
    if (!currentTrack) return;

    currentTrack->parsedSyncedLyrics.clear();

    std::regex timeTagRegex(R"(\[(\d+):(\d+)\.(\d+)\](.*))");
    std::istringstream stream(lyrics);
    std::string line;

    currentTrack->parsedSyncedLyrics.emplace_back(0, " ");

    while (std::getline(stream, line)) {
        std::smatch matches;
        if (std::regex_search(line, matches, timeTagRegex) && matches.size() > 4) {
            int minutes = std::stoi(matches[1].str());
            int seconds = std::stoi(matches[2].str());
            int milliseconds = std::stoi(matches[3].str());
            std::string lyricText = matches[4].str();

            int totalMs = (minutes * 60 + seconds) * 1000 + milliseconds;
            LOG_DEBUG("Parsed synced lyric: " + std::to_string(totalMs) + "ms - " + lyricText);
            currentTrack->parsedSyncedLyrics.emplace_back(totalMs, lyricText);
        }
    }

    std::sort(currentTrack->parsedSyncedLyrics.begin(), currentTrack->parsedSyncedLyrics.end(),
              [](const auto &a, const auto &b) { return a.first < b.first; });
}

size_t LyricsManager::WriteCallback(void *contents, size_t size, size_t nmemb, std::string *userp) {
    size_t realsize = size * nmemb;
    userp->append((char *) contents, realsize);
    return realsize;
}

void LyricsManager::initNcurses() {
    if (!ncursesInitialized) {
        setlocale(LC_ALL, "");

        initscr();
        cbreak();
        noecho();
        keypad(stdscr, TRUE);
        curs_set(0);
        start_color();

        init_pair(1, COLOR_RED, COLOR_BLACK);     // Title
        init_pair(2, COLOR_YELLOW, COLOR_BLACK);  // Song info
        init_pair(3, COLOR_WHITE, COLOR_BLACK);   // Lyrics
        init_pair(4, COLOR_CYAN, COLOR_BLACK);    // Current line
        init_pair(5, COLOR_GREEN, COLOR_BLACK);   // Progress bar
        init_pair(6, COLOR_MAGENTA, COLOR_BLACK); // Hint

        int termHeight, termWidth;
        getmaxyx(stdscr, termHeight, termWidth);

        int headerHeight = 5;
        int contentHeight = termHeight - headerHeight - 1;

        lyricsWin = newwin(termHeight, termWidth, 0, 0);

        headerWin = newwin(headerHeight, termWidth, 0, 0);

        contentWin = newwin(contentHeight, termWidth, headerHeight, 0);

        maxVisibleLines = contentHeight - 2;
        scrollPosition = 0;

        nodelay(stdscr, TRUE);

        ncursesInitialized = true;
    }
}

void LyricsManager::endNcurses() {
    if (ncursesInitialized) {
        delwin(contentWin);
        delwin(headerWin);
        delwin(lyricsWin);
        endwin();
        ncursesInitialized = false;
    }
}

std::string LyricsManager::formatTime(double seconds) {
    int mins = static_cast<int>(seconds) / 60;
    int secs = static_cast<int>(seconds) % 60;
    char buffer[10];
    snprintf(buffer, sizeof(buffer), "%d:%02d", mins, secs);
    return {buffer};
}

std::string LyricsManager::truncateText(const std::string &text, int maxWidth) {
    if (text.length() <= maxWidth) {
        return text;
    }
    return text.substr(0, maxWidth - 3) + "...";
}

void LyricsManager::drawHeader(const std::string &artist, const std::string &title, double elapsed, double duration) {
    werase(headerWin);

    int height, width;
    getmaxyx(headerWin, height, width);

    wattron(headerWin, COLOR_PAIR(1));
    box(headerWin, 0, 0);
    wattroff(headerWin, COLOR_PAIR(1));

    std::string headerText = "Now Playing";
    wattron(headerWin, COLOR_PAIR(1) | A_BOLD);
    mvwprintw(headerWin, 0, (width - headerText.length()) / 2, "%s", headerText.c_str());
    wattroff(headerWin, COLOR_PAIR(1) | A_BOLD);

    std::string songInfo = artist + " - " + title;
    songInfo = truncateText(songInfo, width - 4);
    wattron(headerWin, COLOR_PAIR(2) | A_BOLD);
    mvwprintw(headerWin, 1, (width - songInfo.length()) / 2, "%s", songInfo.c_str());
    wattroff(headerWin, COLOR_PAIR(2) | A_BOLD);

    std::string timeInfo = formatTime(elapsed) + " / " + formatTime(duration);
    wattron(headerWin, COLOR_PAIR(5));
    mvwprintw(headerWin, 2, (width - timeInfo.length()) / 2, "%s", timeInfo.c_str());
    wattroff(headerWin, COLOR_PAIR(5));

    int progressWidth = width - 8;
    double progress = (duration > 0) ? elapsed / duration : 0;
    int progressPos = static_cast<int>(progress * progressWidth);

    wattron(headerWin, COLOR_PAIR(5));
    mvwprintw(headerWin, 3, 4, "[");
    for (int i = 0; i < progressWidth; i++) {
        if (i < progressPos) {
            waddch(headerWin, '=');
        } else if (i == progressPos) {
            waddch(headerWin, '>');
        } else {
            waddch(headerWin, ' ');
        }
    }
    mvwprintw(headerWin, 3, 4 + progressWidth + 1, "]");
    wattroff(headerWin, COLOR_PAIR(5));

    wrefresh(headerWin);
}

void LyricsManager::drawSyncedLyrics(const std::vector<std::pair<int, std::string>> &lyrics, int currentIndex) {
    werase(contentWin);

    int height, width;
    getmaxyx(contentWin, height, width);

    wattron(contentWin, COLOR_PAIR(3));
    box(contentWin, 0, 0);
    wattroff(contentWin, COLOR_PAIR(3));

    totalLines = lyrics.size();

    if (!manualScrollMode) {
        int middleLine = (height - 2) / 2;
        scrollPosition = std::max(0, currentIndex - middleLine);
        autoScrollPosition = scrollPosition;
    }

    int displayedLines = 0;
    for (int i = scrollPosition; i < totalLines && displayedLines < height - 2; i++) {
        std::string line = lyrics[i].second;
        line = truncateText(line, width - 6);

        if (i == currentIndex) {
            wattron(contentWin, COLOR_PAIR(4) | A_BOLD);
            mvwprintw(contentWin, displayedLines + 1, 2, ">%s", line.c_str());
            wattroff(contentWin, COLOR_PAIR(4) | A_BOLD);
        } else if (i < currentIndex) {
            wattron(contentWin, COLOR_PAIR(3) | A_BOLD);
            mvwprintw(contentWin, displayedLines + 1, 2, " %s", line.c_str());
            wattroff(contentWin, COLOR_PAIR(3) | A_BOLD);
        } else {
            wattron(contentWin, COLOR_PAIR(3));
            mvwprintw(contentWin, displayedLines + 1, 2, " %s", line.c_str());
            wattroff(contentWin, COLOR_PAIR(3));
        }

        displayedLines++;
    }

    if (totalLines > height - 2) {
        wattron(contentWin, COLOR_PAIR(6));
        if (scrollPosition > 0) {
            mvwaddch(contentWin, 0, width / 2, ACS_UARROW);
        }
        if (scrollPosition + height - 2 < totalLines) {
            mvwaddch(contentWin, height - 1, width / 2, ACS_DARROW);
        }
        wattroff(contentWin, COLOR_PAIR(6));
    }

    std::string scrollModeHint = manualScrollMode ? "[Manual] 'a':auto" : "[Auto] 'a':manual";
    std::string scrobblingHint = Config::getInstance().isScrobblingEnabled() ?
                                 "[Scrobbling On] 's':toggle" :
                                 "[Scrobbling Off] 's':toggle";

    std::string combinedHint = scrollModeHint + " | " + scrobblingHint;
    if (combinedHint.length() > width - 4) {
        scrollModeHint = manualScrollMode ? "[M]" : "[A]";
        scrobblingHint = Config::getInstance().isScrobblingEnabled() ? "[S:On]" : "[S:Off]";
        combinedHint = scrollModeHint + " 'a':toggle | " + scrobblingHint + " 's':toggle";

        if (combinedHint.length() > width - 4) {
            combinedHint = manualScrollMode ? "[M]" : "[A]";
            combinedHint += Config::getInstance().isScrobblingEnabled() ? " [S+]" : " [S-]";
        }
    }

    wattron(contentWin, COLOR_PAIR(6));
    mvwprintw(contentWin, height - 1, (width - combinedHint.length()) / 2, "%s", combinedHint.c_str());
    wattroff(contentWin, COLOR_PAIR(6));

    wrefresh(contentWin);
}

LyricsManager::KeyAction LyricsManager::checkKeypress() {
    int ch = getch();
    if (ch == ERR) {
        return NO_ACTION;
    }

    KeyAction action = NO_ACTION;

    switch (ch) {
        case KEY_UP:
            if (scrollPosition > 0) {
                scrollPosition--;
                action = SCROLL;
            }
            break;
        case KEY_DOWN:
            if (totalLines > maxVisibleLines && scrollPosition < totalLines - maxVisibleLines) {
                scrollPosition++;
                action = SCROLL;
            }
            break;
        case KEY_PPAGE: // Page Up
            scrollPosition -= maxVisibleLines;
            if (scrollPosition < 0) {
                scrollPosition = 0;
            }
            action = SCROLL;
            break;
        case KEY_NPAGE: // Page Down
            scrollPosition += maxVisibleLines;
            if (totalLines > maxVisibleLines && scrollPosition > totalLines - maxVisibleLines) {
                scrollPosition = totalLines - maxVisibleLines;
            }
            action = SCROLL;
            break;
        case 'a':
            manualScrollMode = !manualScrollMode;
            if (!manualScrollMode) {
                scrollPosition = autoScrollPosition;
            }
            action = SCROLL;
            break;
        case 's':
            Config::getInstance().toggleScrobbling();
            action = SCROLL;
            break;
        case 'q':
            action = QUIT;
            exit(0);
            break;
    }

    return action;
}

void LyricsManager::displaySyncedLyrics(double playbackRateValue, double elapsedValue) {
    auto &config = Config::getInstance();
    TrackManager::TrackState *currentTrack = TrackManager::getInstance().getCurrentTrack();

    if (!config.isShowLyrics() || !currentTrack) {
        if (ncursesInitialized) {
            endNcurses();
        }
        return;
    }

    if (playbackRateValue > 0.0) {
        if (!ncursesInitialized) {
            initNcurses();
        }

        int currentTimeMs = static_cast<int>(elapsedValue * 1000);
        int newLyricIndex = -1;

        size_t left = 0;
        size_t right = currentTrack->parsedSyncedLyrics.size() - 1;

        while (left <= right) {
            size_t mid = (left + right) / 2;
            int timeStamp = currentTrack->parsedSyncedLyrics[mid].first;

            if (timeStamp <= currentTimeMs) {
                newLyricIndex = mid;
                left = mid + 1;
            } else {
                if (mid == 0) break;
                right = mid - 1;
            }
        }

        bool needRedraw = forceRedraw;

        if (newLyricIndex != currentTrack->currentLyricIndex || newLyricIndex == -1) {
            currentTrack->currentLyricIndex = newLyricIndex;
            needRedraw = true;
        }

        KeyAction action = checkKeypress();
        if (action == QUIT) {
            endNcurses();
            return;
        } else if (action == SCROLL) {
            needRedraw = true;
        }

        drawHeader(currentTrack->artist, currentTrack->title, elapsedValue, currentTrack->duration);

        if (needRedraw) {
            if (newLyricIndex >= 0 && !currentTrack->parsedSyncedLyrics.empty()) {
                drawSyncedLyrics(currentTrack->parsedSyncedLyrics, newLyricIndex);
            }
            forceRedraw = false;
        }
    } else if (ncursesInitialized) {
        endNcurses();
        LOG_INFO("⏸️ Paused: " + currentTrack->artist + " - " + currentTrack->title + " [" + currentTrack->album +
                 "]  (" + std::to_string(currentTrack->duration) + " sec)");
    }
}

void LyricsManager::clearLyricsArea() {
    if (ncursesInitialized) {
        endNcurses();
    }
    forceRedraw = false;
}

void LyricsManager::forceRefreshLyrics() {
    forceRedraw = true;

    if (ncursesInitialized) {
        scrollPosition = 0;
    }
}

void LyricsManager::drawPlainLyrics(const std::vector<std::string> &lyrics) {
    werase(contentWin);

    int height, width;
    getmaxyx(contentWin, height, width);

    wattron(contentWin, COLOR_PAIR(3));
    box(contentWin, 0, 0);
    wattroff(contentWin, COLOR_PAIR(3));

    totalLines = lyrics.size();

    if (scrollPosition < 0) {
        scrollPosition = 0;
    } else if (totalLines > maxVisibleLines && scrollPosition > totalLines - maxVisibleLines) {
        scrollPosition = totalLines - maxVisibleLines;
    }

    int displayedLines = 0;
    for (int i = scrollPosition; i < totalLines && displayedLines < maxVisibleLines; i++) {
        std::string line = lyrics[i];
        line = truncateText(line, width - 6);

        wattron(contentWin, COLOR_PAIR(3) | A_BOLD);
        mvwprintw(contentWin, displayedLines + 1, 3, "%s", line.c_str());
        wattroff(contentWin, COLOR_PAIR(3) | A_BOLD);

        displayedLines++;
    }

    if (totalLines > maxVisibleLines) {
        wattron(contentWin, COLOR_PAIR(6));
        if (scrollPosition > 0) {
            mvwaddch(contentWin, 0, width / 2, ACS_UARROW);
        }
        if (scrollPosition + maxVisibleLines < totalLines) {
            mvwaddch(contentWin, height - 1, width / 2, ACS_DARROW);
        }
        wattroff(contentWin, COLOR_PAIR(6));
    }

    std::string scrollHint = "Use arrow keys to scroll";
    std::string scrobblingHint = Config::getInstance().isScrobblingEnabled() ? 
                              "[Scrobbling On] 's':toggle" : 
                              "[Scrobbling Off] 's':toggle";
    
    std::string combinedHint = scrollHint + " | " + scrobblingHint;
    
    if (combinedHint.length() > width - 4) {
        scrobblingHint = Config::getInstance().isScrobblingEnabled() ? "[S:On]" : "[S:Off]";
        combinedHint = scrollHint + " | " + scrobblingHint + " 's':toggle";
        
        if (combinedHint.length() > width - 4) {
            combinedHint = "↑↓:scroll | " + std::string(Config::getInstance().isScrobblingEnabled() ? "[S+]" : "[S-]");
        }
    }

    wattron(contentWin, COLOR_PAIR(6));
    mvwprintw(contentWin, height - 1, (width - combinedHint.length()) / 2, "%s", combinedHint.c_str());
    wattroff(contentWin, COLOR_PAIR(6));

    wrefresh(contentWin);
}

void LyricsManager::displayPlainLyrics(double playbackRateValue, double elapsedValue) {
    auto &config = Config::getInstance();
    TrackManager::TrackState *currentTrack = TrackManager::getInstance().getCurrentTrack();

    if (!config.isShowLyrics() || !currentTrack) {
        if (ncursesInitialized) {
            endNcurses();
        }
        return;
    }

    if (playbackRateValue > 0.0) {
        if (!ncursesInitialized) {
            initNcurses();
        }

        bool needRedraw = forceRedraw;

        KeyAction action = checkKeypress();
        if (action == QUIT) {
            endNcurses();
            return;
        } else if (action == SCROLL) {
            needRedraw = true;
        }

        drawHeader(currentTrack->artist, currentTrack->title, elapsedValue, currentTrack->duration);

        if (needRedraw) {
            if (!currentTrack->parsedPlainLyrics.empty()) {
                drawPlainLyrics(currentTrack->parsedPlainLyrics);
            }
            forceRedraw = false;
        }
    } else if (ncursesInitialized) {
        endNcurses();
        LOG_INFO("⏸️ Paused: " + currentTrack->artist + " - " + currentTrack->title + " [" + currentTrack->album +
                 "]  (" + std::to_string(currentTrack->duration) + " sec)");
    }
}

void LyricsManager::parsePlainLyrics(const std::string &lyrics) {
    TrackManager::TrackState *currentTrack = TrackManager::getInstance().getCurrentTrack();
    std::istringstream stream(lyrics);
    std::string line;

    while (std::getline(stream, line)) {
        currentTrack->parsedPlainLyrics.push_back(line);
    }
}