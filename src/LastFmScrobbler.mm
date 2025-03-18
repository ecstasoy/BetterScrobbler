#include "include/LastFmScrobbler.h"
#include "include/Logger.h"
#include "include/Credentials.h"
#include "include/UrlUtils.h"
#include "include/Helper.h"
#include "include/Config.h"
#include "../lib/json.hpp"
#include <map>

using json = nlohmann::json;

LastFmScrobbler::LastFmScrobbler() : curl(nullptr) {
    init();
}

LastFmScrobbler::~LastFmScrobbler() {
    cleanup();
}

bool LastFmScrobbler::init() {
    curl = curl_easy_init();
    if (!curl) {
        lastError = "Failed to initialize CURL";
        LOG_ERROR(lastError);
        return false;
    }
    return true;
}

void LastFmScrobbler::cleanup() {
    if (curl) {
        curl_easy_cleanup(curl);
        curl = nullptr;
    }
}

bool LastFmScrobbler::sendNowPlaying(const std::string &artist, const std::string &track, const std::string &album,
                                     double duration) {
    auto &credentials = Credentials::getInstance();

    std::string sessionKey = Credentials::loadSessionKey();
    if (sessionKey.empty()) {
        lastError = "No session key available";
        LOG_ERROR(lastError);
        return false;
    }

    std::string safeArtist = Helper::cleanArtistName(artist);
    std::string safeTrack = track;
    std::string safeAlbum = album;

    auto cleanString = [](std::string &s) {
        s.erase(std::remove_if(s.begin(), s.end(),
                               [](unsigned char c) {
                                   return std::iswcntrl(c);
                               }),
                s.end());
    };

    cleanString(safeArtist);
    cleanString(safeTrack);
    cleanString(safeAlbum);

    std::map<std::string, std::string> params = {
            {"method", "track.updateNowPlaying"},
            {"artist", safeArtist},
            {"track",  safeTrack},
            {"sk",     sessionKey}
    };

    if (!safeAlbum.empty()) {
        params["album"] = safeAlbum;
    }
    if (duration > 0) {
        params["duration"] = std::to_string((int) duration);
    }

    LOG_DEBUG("Sending now playing - Artist: '" + safeArtist + "', Track: '" + safeTrack + "'");

    std::map<std::string, std::string> allParams = params;
    allParams["api_key"] = Credentials::getApiKey();
    std::string apiSig = UrlUtils::generateSignature(allParams, credentials);
    allParams["api_sig"] = apiSig;
    allParams["format"] = "json";

    std::string url = "https://ws.audioscrobbler.com/2.0/";
    std::string response = UrlUtils::sendPostRequest(url, allParams, curl);

    if (response.empty()) {
        LOG_ERROR("Empty response from Last.fm");
        return false;
    }

    return true;
}

void LastFmScrobbler::sendNowPlayingUpdate(const std::string &artist, const std::string &title, bool isMusic,
                                           const std::string &album, double &lastNowPlayingSent, double playbackRate) {
    // Check if scrobbling is enabled in config
    if (!Config::getInstance().isScrobblingEnabled()) {
        return;
    }

    if (playbackRate == 0.0) {
        return;
    }

    if (!isMusic) {
        return;
    }

    double now = CFAbsoluteTimeGetCurrent();
    if (now - lastNowPlayingSent < 30.0) {
        return;
    }

    std::string cleanedArtist = Helper::cleanArtistName(artist);

    LOG_DEBUG("Sending now playing update");
    lastNowPlayingSent = now;
    LastFmScrobbler::getInstance().sendNowPlaying(cleanedArtist, title, album, 0.0 /* duration placeh. */);
}

bool LastFmScrobbler::scrobble(const std::string &artist, const std::string &track, const std::string &album,
                               double duration, int timeStamp) {
    auto &credentials = Credentials::getInstance();

    if (!Config::getInstance().isScrobblingEnabled()) {
        LOG_DEBUG("Scrobbling is disabled in config");
        return false;
    }

    std::string sessionKey = Credentials::loadSessionKey();
    if (sessionKey.empty()) {
        lastError = "No session key available";
        LOG_ERROR(lastError);
        return false;
    }

    if (timeStamp == 0) {
        timeStamp = (int) std::time(nullptr);
    }

    std::string safeArtist = Helper::cleanArtistName(artist);
    std::string safeTrack = track;
    std::string safeAlbum = album;

    auto cleanString = [](std::string &s) {
        s.erase(std::remove_if(s.begin(), s.end(),
                               [](unsigned char c) {
                                   return std::iswcntrl(c);
                               }),
                s.end());
    };

    cleanString(safeTrack);
    cleanString(safeAlbum);

    std::map<std::string, std::string> params = {
            {"method",    "track.scrobble"},
            {"artist",    safeArtist},
            {"track",     safeTrack},
            {"timestamp", std::to_string(timeStamp)},
            {"sk",        sessionKey}
    };

    if (!safeAlbum.empty()) {
        params["album"] = safeAlbum;
    }
    if (duration > 0) {
        params["duration"] = std::to_string((int) duration);
    }

    std::map<std::string, std::string> allParams = params;
    allParams["api_key"] = Credentials::getApiKey();
    std::string apiSig = UrlUtils::generateSignature(allParams, credentials);
    allParams["api_sig"] = apiSig;
    allParams["format"] = "json";

    std::string url = "https://ws.audioscrobbler.com/2.0/";
    std::string response = UrlUtils::sendPostRequest(url, allParams, curl);

    if (!response.empty()) {
        LOG_INFO("Scrobbled: " + artist + " - " + track +
                 (album.empty() ? "" : " [" + album + "]"));
        return true;
    }

    return false;
}

bool
LastFmScrobbler::shouldScrobble(double elapsed, double duration, double playbackRate, bool isMusic) {
    // Check if scrobbling is enabled in config
    if (!Config::getInstance().isScrobblingEnabled()) {
        return false;
    }

    if (!isMusic) return false;

    double progressPercentage = (duration > 0.0) ? (elapsed / duration) * 100.0 : 0.0;

    return (progressPercentage > 50.0 || elapsed > 240.0);
}

std::string LastFmScrobbler::search(const std::string &artist, const std::string &track) {
    auto &credentials = Credentials::getInstance();

    std::string safeArtist = artist;
    std::string safeTrack = track;

    auto cleanString = [](std::string &s) {
        s.erase(std::remove_if(s.begin(), s.end(),
                               [](unsigned char c) {
                                   return std::iswcntrl(c);
                               }),
                s.end());
    };

    cleanString(safeArtist);
    cleanString(safeTrack);

    std::map<std::string, std::string> params;
    params["method"] = "track.search";

    if (!safeArtist.empty()) {
        params["artist"] = safeArtist;
    }
    if (!safeTrack.empty()) {
        params["track"] = safeTrack;
    }

    std::map<std::string, std::string> allParams = params;
    allParams["api_key"] = Credentials::getApiKey();
    std::string apiSig = UrlUtils::generateSignature(allParams, credentials);
    allParams["api_sig"] = apiSig;
    allParams["format"] = "json";

    std::string url = "https://ws.audioscrobbler.com/2.0/";
    std::string response = UrlUtils::sendPostRequest(url, allParams, curl);

    if (response.empty()) {
        LOG_ERROR("Empty response from Last.fm search");
        return "{}";
    }

    return response;
}

std::list<std::string> LastFmScrobbler::bestMatch(const std::string &artist, const std::string &track) {
    std::list<std::string> result;
    LOG_DEBUG("Searching for best match for: " + artist + " - " + track);

    auto searchAndMatch = [&](const std::string &searchArtist, const std::string &searchTrack) -> bool {
        json j;
        try {
            std::string response = LastFmScrobbler::search(searchArtist, searchTrack);
            if (response == "{}") {
                LOG_DEBUG("Empty search response");
                return false;
            }
            j = json::parse(response);
        } catch (const std::exception &e) {
            LOG_ERROR("JSON Parsing failed: " + std::string(e.what()));
            return false;
        }

        if (!j.contains("results") ||
            !j["results"].contains("trackmatches") ||
            !j["results"]["trackmatches"].contains("track") ||
            j["results"]["trackmatches"]["track"].empty()) {
            LOG_DEBUG("No track matches found in JSON response");
            return false;
        }

        std::string bestArtist, bestTrack;
        int bestArtistDistance = 100, bestTrackDistance = 100;

        std::string artistLower = Helper::toLower(searchArtist);
        std::string trackLower = Helper::toLower(searchTrack);

        for (const auto &candidate: j["results"]["trackmatches"]["track"]) {
            if (!candidate.contains("artist") || !candidate.contains("name") ||
                !candidate.contains("listeners"))
                continue;

            std::string foundArtist = candidate["artist"].get<std::string>();
            std::string foundTrack = candidate["name"].get<std::string>();
            int listeners = std::stoi(candidate["listeners"].get<std::string>());

            std::string foundArtistLower = Helper::toLower(foundArtist);
            std::string foundTrackLower = Helper::toLower(foundTrack);

            // Sorry if no one wants to listen to your true music
            if (listeners < 200) {
                LOG_DEBUG("Skipping low-listener track: " + foundArtist + " - " +
                          foundTrack + " (listeners: " + std::to_string(listeners) + ")");
                continue;
            }

            int artistDistance = Helper::levenshteinDistance(artistLower, foundArtistLower);
            int trackDistance = Helper::levenshteinDistance(trackLower, foundTrackLower);

            LOG_DEBUG("Comparing with: " + foundArtist + " - " + foundTrack +
                      " | Artist Distance: " + std::to_string(artistDistance) +
                      " | Track Distance: " + std::to_string(trackDistance));

            if (artistDistance < bestArtistDistance || trackDistance < bestTrackDistance) {
                bestArtist = foundArtist;
                bestTrack = foundTrack;
                bestArtistDistance = artistDistance;
                bestTrackDistance = trackDistance;
            }
        }

        if (bestArtistDistance <= 3 && bestTrackDistance <= 3) {
            LOG_DEBUG("Best fuzzy match found: " + bestArtist + " - " + bestTrack);
            result.push_back(bestArtist);
            result.push_back(bestTrack);
            return true;
        }

        LOG_DEBUG("No good fuzzy match found (distances too large)");
        return false;
    };

    // Try search with extracted values first
    if (searchAndMatch(artist, track)) {
        return result;
    }

    return result;
}