#include "include/Config.h"
#include "include/Logger.h"
#include "include/Helper.h"
#include "include/LastFmScrobbler.h"
#include "include/UrlUtils.h"
#include "../lib/json.hpp"
#include <iostream>
#include <regex>
#include <map>

using json = nlohmann::json;

double getAppleMusicDuration() {
    FILE *pipe = popen("osascript -e 'tell application \"Music\" to get duration of current track'", "r");
    if (!pipe) {
        return 0.0;
    }
    char buffer[128];
    std::string result;
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        result += buffer;
    }
    pclose(pipe);

    try {
        return std::stod(result);
    } catch (...) {
        return 0.0;
    }
}

void extractMetadata(CFDictionaryRef info, std::string &artist, std::string &title, std::string &album,
                     double &duration, double &lastDuration, double &playbackRate) {

    if (!info) {
        LOG_DEBUG("Null info dictionary received");
        return;
    }

    const char *defaultArtist = "Unknown Artist";
    const char *defaultTitle = "Unknown Title";
    const char *defaultAlbum = "Unknown Album";

    char artistStr[256] = {0};
    char titleStr[256] = {0};
    char albumStr[256] = {0};

    strncpy(artistStr, defaultArtist, sizeof(artistStr) - 1);
    strncpy(titleStr, defaultTitle, sizeof(titleStr) - 1);
    strncpy(albumStr, defaultAlbum, sizeof(albumStr) - 1);

    auto artistRef = (CFStringRef) CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoArtist"));
    auto titleRef = (CFStringRef) CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoTitle"));
    auto albumRef = (CFStringRef) CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoAlbum"));
    auto durationRef = (CFNumberRef) CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoDuration"));
    auto playbackRateRef = (CFNumberRef) CFDictionaryGetValue(info,
                                                              CFSTR("kMRMediaRemoteNowPlayingInfoPlaybackRate"));

    if (artistRef) CFStringGetCString(artistRef, artistStr, sizeof(artistStr), kCFStringEncodingUTF8);
    if (titleRef) CFStringGetCString(titleRef, titleStr, sizeof(titleStr), kCFStringEncodingUTF8);
    if (albumRef) CFStringGetCString(albumRef, albumStr, sizeof(albumStr), kCFStringEncodingUTF8);

    if (durationRef) {
        CFNumberGetValue(durationRef, kCFNumberDoubleType, &duration);
        if (duration > 0.0 && duration != lastDuration) {
            lastDuration = duration;
        }
    }

    if (lastDuration == 0.0) {
        double fromAppleScript = getAppleMusicDuration();
        if (fromAppleScript > 0.0) {
            lastDuration = fromAppleScript;
            std::cout << "[INFO] Fetched duration from AppleScript: " << lastDuration << " sec\n";
        }
    }

    if (playbackRateRef) CFNumberGetValue(playbackRateRef, kCFNumberDoubleType, &playbackRate);

    artist = artistStr;
    title = titleStr;
    album = albumStr;
}

double updateElapsedTime(CFDictionaryRef info, double &reportedElapsed, double playbackRate, double &elapsedValue,
                         double &lastElapsed, double &lastFetchTime, double &lastReportedElapsed) {
    constexpr double SEEK_THRESHOLD = 0.5;
    double now = CFAbsoluteTimeGetCurrent();

    // Get the elapsed time from the now playing info
    auto elapsedTime = (CFNumberRef) CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoElapsedTime"));
    if (elapsedTime) {
        CFNumberGetValue(elapsedTime, kCFNumberDoubleType, &reportedElapsed);
    } else {
        // If the elapsed time is not available, use the last known value
        reportedElapsed = lastElapsed;
    }

    bool isReportedTimeUnchanged = (reportedElapsed == lastReportedElapsed);
    bool isSeekDetected = std::fabs(reportedElapsed - lastElapsed) > SEEK_THRESHOLD;

    // If the reported elapsed time is the same as the last reported value, calculate the elapsed time based on the playback rate
    // Seek detection: if the difference between the reported elapsed time and the last known elapsed time is
    // greater than 0.5 seconds, use the reported elapsed time
    if (isReportedTimeUnchanged) {
        elapsedValue = lastElapsed + (now - lastFetchTime) * playbackRate;
    } else if (isSeekDetected) {
        LOG_DEBUG("Seek detected: " + std::to_string(lastElapsed) + " -> " + std::to_string(reportedElapsed));
        elapsedValue = reportedElapsed;
    } else {
        elapsedValue = reportedElapsed;
    }

    lastElapsed = elapsedValue;
    lastReportedElapsed = reportedElapsed;
    lastFetchTime = now;

    return elapsedValue;
}

std::string cleanArtistName(const std::string &artist) {
    static const std::vector<std::regex> patterns = {
            std::regex(R"(\s*-\s*Topic\s*$)", std::regex_constants::icase),    // "The Wake - Topic"
            std::regex(R"(\s*-\s*Official\s*$)", std::regex_constants::icase), // "Artist Name - Official"
            std::regex(R"(\s*-\s*Official\s+Channel\s*$)", std::regex_constants::icase), // "Artist - Official Channel"
            std::regex(R"(\s*VEVO\s*$)", std::regex_constants::icase),         // "ArtistVEVO"
            std::regex(R"(\s*-\s*VEVO\s*$)", std::regex_constants::icase),     // "Artist - VEVO"
            std::regex(R"(\s*Official\s*$)", std::regex_constants::icase),      // "Artist Official"
            std::regex(R"(\s*Music\s*$)", std::regex_constants::icase)         // "Artist Music"
    };

    std::string cleaned = artist;
    for (const auto &pattern: patterns) {
        cleaned = std::regex_replace(cleaned, pattern, "");
    }

    auto trim = [](std::string &s) {
        s.erase(0, s.find_first_not_of(" \t\n\r\f\v"));
        s.erase(s.find_last_not_of(" \t\n\r\f\v") + 1);
    };
    trim(cleaned);

    return cleaned;
}

std::string cleanVideoTitle(std::string title) {

    static const std::vector<std::regex> platformSuffixes = {
            std::regex(R"((.+?)_哔哩哔哩_bilibili$)"),
            std::regex(R"((.+?)_哔哩哔哩bilibili$)"),
            std::regex(R"((.+?)\s*-\s*YouTube$)"),
            std::regex(R"((.+?)\s*-\s*优酷$)"),
            std::regex(R"((.+?)\s*-\s*腾讯视频$)"),
            std::regex(R"((.+?)\s*-\s*爱奇艺$)"),
            std::regex(R"((.+?)\s*-\s*抖音$)"),
            std::regex(R"((.+?)\s*-\s*快手$)"),
            std::regex(R"((.+?)\s*-\s*西瓜视频$)"),
            std::regex(R"((.+?)\s*-\s*Bilibili$)"),
            std::regex(R"((.+?)\s*-\s*B站$)"),
            std::regex(R"((.+?)\s*-\s*哔哩哔哩$)")
    };

    static const std::vector<std::regex> suffixes = {
            std::regex(R"(^\s*\[[^\]]*\]\s*)"),
            std::regex(R"(\s*\[[^\]]*\].*$)"),

            std::regex(
                    R"(\s*[\(\[](?:MV|M/V|Music Video|Official Video|Lyric Video|Audio|Visualizer|Karaoke)[^\)\]]*[\)\]].*$)",
                    std::regex_constants::icase),
            std::regex(R"(\s*[\(\[](?:Official|HD|4K|Remaster(?:ed)?|[12]\d{3})[^\)\]]*[\)\]].*$)",
                       std::regex_constants::icase),
            std::regex(R"(\s*[\(\[](?:Live|Concert|Tour|Session|Performance)[^\)\]]*[\)\]].*$)",
                       std::regex_constants::icase),
            std::regex(R"(\s*[\(\[](?:TV|Show|Episode|Late Night|Television)[^\)\]]*[\)\]].*$)",
                       std::regex_constants::icase),
            std::regex(R"(\s*【[^】]*】.*$)"),
            std::regex(R"(\s*\|\s*.*$)"),
            std::regex(R"(\s*｜\s*.*$)"),
            // Date formats
            std::regex(R"(\s*\d{1,2}[-/]\d{1,2}[-/]\d{2,4}.*$)"),
            std::regex(R"(\s*[\(\[]\d{1,2}[-/]\d{1,2}[-/]\d{2,4}[\)\]].*$)")
    };

    for (const auto &pattern: platformSuffixes) {
        std::smatch matches;
        if (std::regex_search(title, matches, pattern) && matches.size() > 1) {
            title = matches[1].str();
            break;
        }
    }

    std::string cleaned = title;
    for (const auto &suffix: suffixes) {
        cleaned = std::regex_replace(cleaned, suffix, "");
    }

    return cleaned;
}

std::string normalizeString(const std::string &input) {
    std::string result = input;

    std::map<std::string, std::string> replacements = {
            {"\xE2\x80\x98", "'"},
            {"\xE2\x80\x99", "'"},
            {"\xE2\x80\x9A", "'"},
            {"\xE2\x80\x9C", "\""},
            {"\xE2\x80\x9D", "\""},
            {"\xE2\x80\x9E", "\""},
            {"\xE2\x80\x93", "-"},
            {"\xE2\x80\x94", "-"},
            {"\xE2\x88\x92", "-"},
            {"\xE2\x80\xA6", "..."},
            {"\xC2\xBD",     "1/2"},
            {"\xC2\xBC",     "1/4"},
            {"\xC2\xBE",     "3/4"},
            {"\xE3\x80\x82", "."},
            {"\xEF\xBC\x8C", ","},
            {"\xEF\xBC\x9B", ";"},
            {"\xEF\xBC\x9A", ":"},
            {"\xEF\xBC\x81", "!"},
            {"\xEF\xBC\x9F", "?"},
            {"\xE3\x80\x8A", "<"},
            {"\xE3\x80\x8B", ">"},
            {"\xEF\xBC\x82", "\""},
            {"\xEF\xBC\x87", "'"},
            {"\xE3\x80\x90", "["},
            {"\xE3\x80\x91", "]"}
    };

    for (const auto &pair: replacements) {
        size_t pos = 0;
        while ((pos = result.find(pair.first, pos)) != std::string::npos) {
            result.replace(pos, pair.first.length(), pair.second);
            pos += pair.second.length();
        }
    }

    result.erase(std::remove_if(result.begin(), result.end(),
                                [](unsigned char c) {
                                    return std::iswcntrl(c);
                                }),
                 result.end());

    return result;
}

inline void trim(std::string &s) {
    s.erase(0, s.find_first_not_of(" \t\n\r\f\v"));
    s.erase(s.find_last_not_of(" \t\n\r\f\v") + 1);
}

bool nonMusicDetect(const std::string &videoTitle) {
    std::vector<std::string> nonMusicKeywords = {
            "讲座", "演讲", "教程", "课程", "直播", "访谈", "采访", "纪录片",
            "vlog", "游戏", "实况", "攻略", "解说", "新闻", "资讯", "评测",
            "开箱", "测评", "教学", "指南", "指导", "教育", "学习", "知识",
            "lecture", "tutorial", "course", "interview", "documentary", "news",
            "vlog", "game", "news", "review", "unboxing", "teaching",
            "guide", "education", "study", "knowledge"
    };

    std::string lowerTitle = videoTitle;
    std::transform(lowerTitle.begin(), lowerTitle.end(), lowerTitle.begin(), ::tolower);

    for (const auto &keyword: nonMusicKeywords) {
        if (lowerTitle.find(keyword) != std::string::npos) {
            LOG_DEBUG("Detected non-music keyword in title: " + keyword);
            return true;
        }
    }

    return false;
}

bool hasMusicSeparators(const std::string &title) {
    static const std::vector<std::string> separators = {
            "-", "「", "『", "[", "(", "<", "《"
    };

    for (const auto &sep: separators) {
        if (title.find(sep) != std::string::npos) {
            return true;
        }
    }
    return false;
}

bool parseStandardFormat(const std::string &title, std::string &outArtist, std::string &outTitle) {
    static const std::vector<std::regex> patterns = {
            std::regex(R"((.+?)[-–−﹣－]\s*['"]((.+?))['"])"),           // Artist - 'Title' 或 Artist - "Title"

            std::regex(R"((.+?)(?:\s*[-–−﹣－]\s*)(.+))"),              // Artist - Title
            std::regex(R"((.+?)\s+['"](.+?)['"])"),              // Artist "Title" 或 Artist 'Title'
            std::regex(R"((.+?)[「『](.+?)[」』])"),                    // Artist「Title」或 Artist『Title』
            std::regex(R"((.+?)[\[|\(](.+?)[\]|\)])"),                // Artist [Title] 或 Artist (Title)
            std::regex(R"((.+?)[-–−﹣－](.+?)\s*\(\d{4}\))"),          // Artist-Title (Year)
            std::regex(R"((.+?)[-–−﹣－](.+?)\s*\[.*?\])"),            // Artist-Title [...]
            std::regex(R"((.+?)『(.+?)』\s*\(\d{4}\))"),              // Artist『Title』(Year)
            std::regex(R"((.+?)[-–−﹣－](.+?)\s*@.*)"),               // Artist-Title @ ...
            std::regex(R"((.+?)[-–−﹣－](.+?)\s*\((?:live|LIVE)[^)]*\))"), // Artist-Title (Live ...)
            std::regex(R"((.+?)[<](.+?)[>])")                         // Artist<Title>
    };

    for (const auto &pattern: patterns) {
        std::smatch matches;
        if (std::regex_search(title, matches, pattern) && matches.size() > 2) {
            outArtist = matches[1].str();
            outTitle = matches[2].str();
            return true;
        }
    }
    return false;
}

bool
tryLastFmSearch(const std::string &artist, const std::string &title, std::string &outArtist, std::string &outTitle) {
    if (!title.empty() && !artist.empty()) {
        LastFmScrobbler &scrobbler = LastFmScrobbler::getInstance();
        auto matches = scrobbler.bestMatch(artist, title);
        if (!matches.empty() && matches.size() >= 2) {
            outArtist = matches.front();
            matches.pop_front();
            outTitle = matches.front();
            LOG_DEBUG("Found match via Last.fm search: " + outArtist + " - " + outTitle);
            return true;
        }
    }

    LOG_DEBUG("Failed to extract music info from: " + title);
    return false;
}

bool isRealArtist(const std::string &artist) {
    std::map<std::string, std::string> params = {
            {"method",      "artist.getInfo"},
            {"artist",      artist},
            {"autocorrect", "0"}
    };

    std::string url = UrlUtils::buildApiUrl("artist.getInfo", params);
    std::string response = UrlUtils::sendGetRequest(url);

    try {
        json j = json::parse(response);
        return !j.contains("error");
    } catch (...) {
        return false;
    }
}

bool
extractMusicInfo(const std::string &artist, const std::string &title, std::string &outArtist, std::string &outTitle) {

    if (nonMusicDetect(title)) {
        return false;
    }

    std::string normalizedArtist = normalizeString(artist);
    std::string cleanedArtist = cleanArtistName(normalizedArtist);

    if (!cleanedArtist.empty() && isRealArtist(cleanedArtist)) {
        LOG_DEBUG("Found valid artist on Last.fm: " + cleanedArtist);
        if (tryLastFmSearch(cleanedArtist, title, outArtist, outTitle)) {
            return true;
        }
    }

    std::string normalizedTitle = normalizeString(title);
    std::string cleanedTitle = cleanVideoTitle(normalizedTitle);
    trim(cleanedTitle);

    std::cout << "[INFO] Cleaned title: " << cleanedTitle << std::endl;

    if (hasMusicSeparators(cleanedTitle)) {
        if (parseStandardFormat(cleanedTitle, outArtist, outTitle)) {
            outArtist = normalizeString(outArtist);
            outTitle = normalizeString(outTitle);

            outTitle = cleanVideoTitle(outTitle);
            outArtist = cleanArtistName(outArtist);

            trim(outArtist);
            trim(outTitle);

            if (!outArtist.empty() && !outTitle.empty() &&
                outArtist.length() > 1 && outTitle.length() > 1) {
                if (isRealArtist(outArtist)) {
                    LOG_DEBUG("Found valid artist on Last.fm: " + outArtist);
                    std::string verifiedArtist, verifiedTitle;
                    if (tryLastFmSearch(outArtist, outTitle, verifiedArtist, verifiedTitle)) {
                        outArtist = verifiedArtist;
                        outTitle = verifiedTitle;
                        return true;
                    }
                } else {
                    LOG_DEBUG("Invalid artist name: " + outArtist);
                }
            }
        }
    } else {
        LOG_DEBUG("No common title separator found in: " + cleanedTitle + ", trying Last.fm search");
    }

    return tryLastFmSearch(cleanedArtist, cleanedTitle, outArtist, outTitle);
};

bool isValidContent(std::string &artist, std::string &title) {
    std::string cleanedArtist = cleanArtistName(artist);

    if (!cleanedArtist.empty() && !title.empty()) {
        LastFmScrobbler &scrobbler = LastFmScrobbler::getInstance();
        auto matches = scrobbler.bestMatch(cleanedArtist, const_cast<std::string &>(title));
        if (!matches.empty() && matches.size() >= 2) {
            artist = matches.front();
            matches.pop_front();
            title = matches.front();
            LOG_INFO("Content verified as valid via Last.fm search");
            return true;
        }
    }

    LOG_INFO("Failed to verify valid content");
    return false;
}

std::string toLower(std::string str) {
    std::transform(str.begin(), str.end(), str.begin(), ::tolower);
    return str;
}

int levenshteinDistance(const std::string &s1, const std::string &s2) {
    const size_t len1 = s1.size(), len2 = s2.size();
    std::vector<std::vector<int>> dp(len1 + 1, std::vector<int>(len2 + 1));

    for (size_t i = 0; i <= len1; ++i) dp[i][0] = i;
    for (size_t i = 0; i <= len2; ++i) dp[0][i] = i;

    for (size_t i = 1; i <= len1; ++i) {
        for (size_t j = 1; j <= len2; ++j) {
            dp[i][j] = std::min({dp[i - 1][j] + 1, dp[i][j - 1] + 1,
                                 dp[i - 1][j - 1] + (s1[i - 1] == s2[j - 1] ? 0 : 1)});
        }
    }

    return dp[len1][len2];
}