#include "include/LyricsManager.h"
#include "include/Logger.h"
#include "include/UrlUtils.h"
#include "../lib/json.hpp"
#include <sstream>
#include <curl/curl.h>

using json = nlohmann::json;

std::string LyricsManager::fetchLyrics(const std::string &artist, const std::string &title, const std::string &album,
                                double duration) {
    CURL* curl = curl_easy_init();
    if (!curl) {
        LOG_ERROR("Failed to initialize CURL");
        return "";
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
        return "";
    }

    if (response.empty()) {
        return "";
    }

    LOG_DEBUG("Lyrics response: " + response);

    json j;
    try {
        j = json::parse(response);
    } catch (const std::exception &e) {
        LOG_ERROR("Failed to parse JSON: " + std::string(e.what()));
        return "";
    }

    if (j.contains("statusCode") || j.contains("message")) {
        LOG_INFO("No lyrics found: " + j.value("message", "Unknown error"));
        return "";
    }

    return j["plainLyrics"];
}

size_t LyricsManager::WriteCallback(void* contents, size_t size, size_t nmemb, std::string* userp) {
    size_t realsize = size * nmemb;
    userp->append((char*)contents, realsize);
    return realsize;
}
