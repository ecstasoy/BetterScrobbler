#include "include/Config.h"
#include "include/Logger.h"
#include "include/Helper.h"
#include "include/LastFmScrobbler.h"
#include "include/UrlUtils.h"
#include "../lib/json.hpp"
#import "include/TrackManager.h"
#include <regex>
#include <map>
#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

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

bool getAppleMusicStatus() {
    static NSString *script = @"tell application \"Music\"\n"
                                   "    if player state is playing then\n"
                                   "        return true\n"
                                   "    end if\n"
                                   "    return false\n"
                                   "end tell\n";

    static NSAppleScript *cachedScript = nil;

    @autoreleasepool {
        if (!cachedScript) {
            cachedScript = [[NSAppleScript alloc] initWithSource:script];
        }

        NSDictionary *error = nil;
        NSAppleEventDescriptor *result = [cachedScript executeAndReturnError:&error];

        if (result) {
            BOOL isPlaying = [result booleanValue];
            return isPlaying;
        } else {
            NSLog(@"AppleScript error: %@", error);
        }
    }

    return -1.0;
}

double getAppleMusicPosition() {

    if (!getAppleMusicStatus()) {
        return -1.0;
    }

    static NSString *script = @"tell application \"Music\"\n"
                       "    return player position\n"
                       "end tell\n";

    static NSAppleScript *cachedScript = nil;

    @autoreleasepool {
        if (!cachedScript) {
            cachedScript = [[NSAppleScript alloc] initWithSource:script];
        }

        NSDictionary *error = nil;
        NSAppleEventDescriptor *result = [cachedScript executeAndReturnError:&error];

        if (result) {
            return [result doubleValue];
        }
    }

    return -1.0;
}

void Helper::extractMetadata(CFDictionaryRef info, std::string &artist, std::string &title, std::string &album,
                             double &duration, double &playbackRate) {

    if (!info) {
        LOG_DEBUG("Null info dictionary received");
        return;
    }

    @autoreleasepool {
        LOG_DEBUG("Extracting metadata from info dictionary");
        
        auto artistRef = (CFStringRef) CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoArtist"));
        auto titleRef = (CFStringRef) CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoTitle"));
        auto albumRef = (CFStringRef) CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoAlbum"));
        auto durationRef = (CFNumberRef) CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoDuration"));
        auto playbackRateRef = (CFNumberRef) CFDictionaryGetValue(info,
                                                                  CFSTR("kMRMediaRemoteNowPlayingInfoPlaybackRate"));

        LOG_DEBUG("Retrieved metadata references from dictionary");

        @try {
            if (artistRef) {
                CFIndex length = CFStringGetLength(artistRef);
                CFIndex maxSize = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8);
                std::vector<char> buffer(maxSize + 1);
                if (CFStringGetCString(artistRef, buffer.data(), maxSize + 1, kCFStringEncodingUTF8)) {
                    artist = buffer.data();
                    LOG_DEBUG("Extracted artist: '" + artist + "'");
                }
            }

            if (titleRef) {
                CFIndex length = CFStringGetLength(titleRef);
                CFIndex maxSize = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8);
                std::vector<char> buffer(maxSize + 1);
                if (CFStringGetCString(titleRef, buffer.data(), maxSize + 1, kCFStringEncodingUTF8)) {
                    title = buffer.data();
                    LOG_DEBUG("Extracted title: '" + title + "'");
                }
            }

            if (albumRef) {
                CFIndex length = CFStringGetLength(albumRef);
                CFIndex maxSize = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8);
                std::vector<char> buffer(maxSize + 1);
                if (CFStringGetCString(albumRef, buffer.data(), maxSize + 1, kCFStringEncodingUTF8)) {
                    album = buffer.data();
                    LOG_DEBUG("Extracted album: '" + album + "'");
                }
            }

            if (durationRef) {
                CFNumberGetValue(durationRef, kCFNumberDoubleType, &duration);
                LOG_DEBUG("Extracted duration: " + std::to_string(duration));
            } else {
                duration = getAppleMusicDuration();
                LOG_DEBUG("Got duration from AppleScript: " + std::to_string(duration));
            }

            if (playbackRateRef) {
                CFNumberGetValue(playbackRateRef, kCFNumberDoubleType, &playbackRate);
                LOG_DEBUG("Extracted playback rate: " + std::to_string(playbackRate));
            }
            
            LOG_DEBUG("Metadata extraction completed successfully");
        } @catch (NSException *exception) {
            LOG_ERROR("Exception while extracting metadata: " + std::string([[exception description] UTF8String]));
            artist.clear();
            title.clear();
            album.clear();
            duration = 0.0;
            playbackRate = 0.0;
        }
    }
}

double
Helper::updateElapsedTime(CFDictionaryRef info, double &reportedElapsed, double playbackRate, double &elapsedValue,
                          double &lastElapsed, double &lastFetchTime, double &lastReportedElapsed) {
    double now = CFAbsoluteTimeGetCurrent();

    auto elapsedTime = (CFNumberRef) CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoElapsedTime"));
    if (elapsedTime) {
        CFNumberGetValue(elapsedTime, kCFNumberDoubleType, &reportedElapsed);
        if (std::fabs(reportedElapsed - lastReportedElapsed) > 0.1) {
            elapsedValue = reportedElapsed;
            lastElapsed = reportedElapsed;
            lastReportedElapsed = reportedElapsed;
            lastFetchTime = now;
            return elapsedValue;
        }
    } else {
        double scriptPosition = getAppleMusicPosition();
        if (scriptPosition >= 0) {
            if (std::fabs(scriptPosition - lastReportedElapsed) > 0.1) {
                reportedElapsed = scriptPosition;
                elapsedValue = scriptPosition;
                lastElapsed = scriptPosition;
                lastReportedElapsed = scriptPosition;
                lastFetchTime = now;
                return elapsedValue;
            }
        }
    }

    // 如果没有获取到新的时间，则根据播放速率计算
    if (playbackRate > 0.0) {
        double timeDiff = now - lastFetchTime;
        elapsedValue = lastElapsed + (timeDiff * playbackRate);
        lastElapsed = elapsedValue;
        lastFetchTime = now;
    }

    return elapsedValue;
}

std::string Helper::cleanArtistName(const std::string &artist) {
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

std::string Helper::cleanVideoTitle(std::string title) {

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
                    R"(\s*[\(\[](?:MV|M/V|Music Video|Official Video|Lyrics Video|Lyric Video|Audio|Visualizer|Karaoke)[^\)\]]*[\)\]].*$)",
                    std::regex_constants::icase),
            std::regex(R"(\s*[\(\[](?:Official|HD|4K|demo|Remaster(?:ed)?|[12]\d{3})[^\)\]]*[\)\]].*$)",
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

// Helper function to determine if a character is a control character in UTF-8
bool Helper::isUtf8Control(const std::string& str) {
    for (size_t i = 0; i < str.size(); ++i) {
        unsigned char c = str[i];
        if (c < 128) {  // ASCII range
            if (std::iswcntrl(c)) {
                return true;
            }
        } else if (c >= 192) {  // Start of a new UTF-8 character sequence
            int num_bytes = 0;
            if ((c & 0xE0) == 0xC0) num_bytes = 2;
            else if ((c & 0xF0) == 0xE0) num_bytes = 3;
            else if ((c & 0xF8) == 0xF0) num_bytes = 4;
            i += num_bytes - 1; // Skip continuation bytes
        }
    }
    return false;
}

std::string Helper::normalizeString(const std::string &input) {
    if (input.empty()) {
        return input;
    }

    @autoreleasepool {
        if (input.find_first_of('\0') != std::string::npos) {
            LOG_ERROR("Input string contains null characters");
            return input;
        }

        // 首先尝试直接创建NSString
        NSString *str = @(input.c_str());
        if (!str) {
            // 如果直接创建失败，尝试通过NSData和不同编码创建
            NSData *data = [[NSData alloc] initWithBytes:input.c_str() length:input.length()];
            if (!data) {
                LOG_ERROR("Failed to create NSData");
                return input;
            }

            NSStringEncoding encodings[] = {
                NSUTF8StringEncoding,
                CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000),
                CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5),
                CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingShiftJIS),
                CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_JP),
                CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_KR),
            };

            for (NSStringEncoding encoding : encodings) {
                str = [[NSString alloc] initWithData:data encoding:encoding];
                if (str) break;
            }

            [data release];

            if (!str) {
                LOG_ERROR("Failed to create NSString with any encoding");
                return input;
            }
        } else {
            str = [str retain];
        }

        std::string result = input;
        @try {
            // 规范化处理
            NSString *decomposedStr = [str decomposedStringWithCanonicalMapping];
            [str release];
            
            if (!decomposedStr) {
                LOG_ERROR("Failed during decomposed mapping");
                return input;
            }

            // 创建可变字符串副本
            CFMutableStringRef mutableStr = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, (__bridge CFStringRef)decomposedStr);
            if (!mutableStr) {
                LOG_ERROR("Failed to create mutable copy of string");
                return input;
            }

            // 执行全角到半角的转换
            if (!CFStringTransform(mutableStr, nullptr, kCFStringTransformFullwidthHalfwidth, false)) {
                CFRelease(mutableStr);
                LOG_ERROR("Failed to transform string");
                return input;
            }

            // 转换回标准形式
            NSString *transformedStr = (__bridge NSString *)mutableStr;
            NSString *precomposedStr = [transformedStr precomposedStringWithCanonicalMapping];
            CFRelease(mutableStr);

            if (!precomposedStr) {
                LOG_ERROR("Failed during precomposed mapping");
                return input;
            }

            // 转换回UTF-8
            NSData *resultData = [precomposedStr dataUsingEncoding:NSUTF8StringEncoding 
                                          allowLossyConversion:YES];
            if (!resultData) {
                LOG_ERROR("Failed to convert normalized string back to UTF-8");
                return input;
            }

            const char *bytes = static_cast<const char*>(resultData.bytes);
            NSUInteger length = resultData.length;

            if (bytes && length > 0) {
                result = std::string(bytes, length);
                result.erase(std::remove_if(result.begin(), result.end(),
                                            [](unsigned char c) { return isUtf8Control(std::string(1, c)); }),
                             result.end());
            }
        }
        @catch (NSException *exception) {
            LOG_ERROR("Exception during string normalization: " + std::string([[exception description] UTF8String]));
            [str release];
        }

        return result;
    }
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
    if (!title.empty()) {
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
Helper::extractMusicInfo(const std::string &artist, const std::string &title, const std::string &album,
                         std::string &outArtist,
                         std::string &outTitle) {
    auto &trackManager = TrackManager::getInstance();
    auto currentTrack = trackManager.getCurrentTrack();
    std::string trackId = TrackManager::generateTrackId(artist, title, album);

    if (trackManager.isCachedTrak(trackId)) {
        currentTrack = trackManager.getCachedTrack(trackId);
        outArtist = currentTrack->artist;
        outTitle = currentTrack->title;
        return true;
    }

    if (nonMusicDetect(title)) {
        return false;
    }

    std::string normalizedArtist = Helper::normalizeString(artist);
    std::string cleanedArtist = Helper::cleanArtistName(normalizedArtist);

    if (!cleanedArtist.empty() && isRealArtist(cleanedArtist)) {
        LOG_DEBUG("Found valid artist on Last.fm: " + cleanedArtist);
        if (tryLastFmSearch(cleanedArtist, title, outArtist, outTitle)) {
            return true;
        }
    }

    std::string normalizedTitle = Helper::normalizeString(title);
    std::string cleanedTitle = Helper::cleanVideoTitle(normalizedTitle);

    trim(cleanedArtist);
    trim(cleanedTitle);

    if (hasMusicSeparators(cleanedTitle)) {
        if (parseStandardFormat(cleanedTitle, outArtist, outTitle)) {
            outArtist = Helper::normalizeString(outArtist);
            outTitle = Helper::normalizeString(outTitle);

            outTitle = Helper::cleanVideoTitle(outTitle);
            outArtist = Helper::cleanArtistName(outArtist);

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
                    } else {
                        return false;
                    }
                } else {
                    LOG_DEBUG("Invalid artist name: " + outArtist);
                    return false;
                }
            }
        }
    } else {
        outArtist = cleanedArtist;
        outTitle = cleanedTitle;
        LOG_DEBUG("No common title separator found in: " + cleanedTitle + ", trying Last.fm search");
    }

    LOG_DEBUG("Trying Last.fm search with cleaned artist and title: " + cleanedArtist + " - " + cleanedTitle);

    return tryLastFmSearch(cleanedArtist, cleanedTitle, outArtist, outTitle);
};

std::string Helper::toLower(std::string str) {
    std::transform(str.begin(), str.end(), str.begin(), ::tolower);
    return str;
}

int Helper::levenshteinDistance(const std::string &s1, const std::string &s2) {
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