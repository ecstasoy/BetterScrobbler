#include "include/LyricsManager.h"
#include "include/TrackManager.h"
#include "include/Logger.h"
#include "include/UrlUtils.h"
#include "../lib/json.hpp"
#include <sstream>
#include <curl/curl.h>
#include <regex>
#include <locale.h>

#define LYRICS_OFFSET 500

using json = nlohmann::json;

void LyricsManager::fetchLyrics(const std::string &artist, const std::string &title, const std::string &album,
                                double duration) {
    TrackManager::TrackState *currentTrack = TrackManager::getInstance().getCurrentTrack();
    auto &config = Config::getInstance();
    if (!currentTrack) return;

    if (!config.isShowLyrics()) {
        currentTrack->plainLyrics = "";
        currentTrack->syncedLyrics = "";
        currentTrack->hasSyncedLyrics = false;
        return;
    }

    CURL* curl = curl_easy_init();
    if (!curl) {
        LOG_ERROR("Failed to initialize CURL");
        currentTrack->plainLyrics = "";
        currentTrack->syncedLyrics = "";
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

    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Lrclib-Client: BetterScrobbler v1.1.0 (https://github.com/ecstasoy/BetterScrobbler)");
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
        currentTrack->plainLyrics = "";
        currentTrack->syncedLyrics = "";
        return;
    }

    if (response.empty()) {
        LOG_INFO("No lyrics found");
        currentTrack->plainLyrics = "";
        currentTrack->syncedLyrics = "";
        return;
    }

    LOG_DEBUG("Lyrics response: " + response);

    json j;
    try {
        j = json::parse(response);
    } catch (const std::exception &e) {
        LOG_ERROR("Failed to parse JSON: " + std::string(e.what()));
        currentTrack->plainLyrics = "";
        currentTrack->syncedLyrics = "";
    }

    if (j.contains("statusCode") || j.contains("message")) {
        LOG_INFO("No lyrics found: " + j.value("message", "Unknown error"));
        currentTrack->plainLyrics = "";
        currentTrack->syncedLyrics = "";
    }

    if (j.contains("plainLyrics") && !j["plainLyrics"].is_null()) {
        currentTrack->plainLyrics = j["plainLyrics"];
        LOG_DEBUG("Parsed plain lyrics: " + currentTrack->plainLyrics);
    } else {
        currentTrack->plainLyrics = "";
    }

    if (j.contains("syncedLyrics") && !j["syncedLyrics"].is_null()) {
        currentTrack->syncedLyrics = j["syncedLyrics"];
        parseSyncedLyrics(currentTrack->syncedLyrics);
        LOG_DEBUG("Parsed synced lyrics: " + currentTrack->syncedLyrics);
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
              [](const auto& a, const auto& b) { return a.first < b.first; });
}

size_t LyricsManager::WriteCallback(void* contents, size_t size, size_t nmemb, std::string* userp) {
    size_t realsize = size * nmemb;
    userp->append((char*)contents, realsize);
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

        init_pair(1, COLOR_RED, COLOR_BLACK);
        init_pair(2, COLOR_YELLOW, COLOR_BLACK);
        init_pair(3, COLOR_MAGENTA, COLOR_BLACK);
        init_pair(4, COLOR_CYAN, COLOR_BLACK);

        int height = 9;
        int width = COLS * 3 / 4;
        int startY = (LINES - height) / 2;
        int startX = (COLS - width) / 2;

        lyricsWin = newwin(height, width, startY, startX);

        ncursesInitialized = true;
    }
}

void LyricsManager::endNcurses() {
    if (ncursesInitialized) {
        delwin(lyricsWin);
        endwin();
        ncursesInitialized = false;
    }
}

void LyricsManager::displayLyrics(double playbackRateValue, double elapsedValue) {
    auto &config = Config::getInstance();
    TrackManager::TrackState *currentTrack = TrackManager::getInstance().getCurrentTrack();

    if (config.isShowLyrics() && config.isPreferSyncedLyrics() && currentTrack &&
        currentTrack->hasSyncedLyrics && playbackRateValue > 0.0) {

        initNcurses();

        int currentTimeMs = static_cast<int>(elapsedValue * 1000);
        int newLyricIndex = -1;
        for (size_t i = 0; i < currentTrack->parsedSyncedLyrics.size(); i++) {
            if (currentTrack->parsedSyncedLyrics[i].first <= currentTimeMs - LYRICS_OFFSET) {
                newLyricIndex = i;
            } else {
                break;
            }
        }

        if (newLyricIndex != currentTrack->currentLyricIndex && newLyricIndex >= 0) {
            currentTrack->currentLyricIndex = newLyricIndex;
            std::string currentLyric = currentTrack->parsedSyncedLyrics[newLyricIndex].second;
            std::string previousLyric = newLyricIndex > 0 ? currentTrack->parsedSyncedLyrics[newLyricIndex - 1].second : "";
            std::string nextLyric = newLyricIndex < currentTrack->parsedSyncedLyrics.size() - 1
                                    ? currentTrack->parsedSyncedLyrics[newLyricIndex + 1].second : "";

            werase(lyricsWin);

            wattron(lyricsWin, COLOR_PAIR(1));
            box(lyricsWin, 0, 0);
            wattroff(lyricsWin, COLOR_PAIR(1));

            int height, width;
            getmaxyx(lyricsWin, height, width);

            std::string title = "Now Playing";
            wattron(lyricsWin, COLOR_PAIR(1));
            mvwprintw(lyricsWin, 0, (width - title.length()) / 2, "%s", title.c_str());
            wattroff(lyricsWin, COLOR_PAIR(1));

            std::string songInfo = currentTrack->artist + " - " + currentTrack->title;
            if (songInfo.length() > width - 6) {
                songInfo = songInfo.substr(0, width - 9) + "...";
            }
            wattron(lyricsWin, COLOR_PAIR(2));
            mvwprintw(lyricsWin, 1, (width - songInfo.length()) / 2, "%s", songInfo.c_str());
            wattroff(lyricsWin, COLOR_PAIR(2));

            wattron(lyricsWin, COLOR_PAIR(3));
            mvwprintw(lyricsWin, 3, 2, "♪ %s", previousLyric.c_str());
            wattroff(lyricsWin, COLOR_PAIR(3));

            wattron(lyricsWin, COLOR_PAIR(4));
            mvwprintw(lyricsWin, 4, 2, "♬ %s", currentLyric.c_str());
            wattroff(lyricsWin, COLOR_PAIR(4));

            wattron(lyricsWin, COLOR_PAIR(3));
            mvwprintw(lyricsWin, 5, 2, "♪ %s", nextLyric.c_str());
            wattroff(lyricsWin, COLOR_PAIR(3));

            wrefresh(lyricsWin);
        }
    } else if (ncursesInitialized) {
        endNcurses();
    }
}

void LyricsManager::clearLyricsArea() {
    if (ncursesInitialized) {
        endNcurses();
    }
}