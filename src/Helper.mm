//
// Created by Kunhua Huang on 3/7/25.
//

#include "header/Config.h"
#include "header/Logger.h"
#include "header/Helper.h"
#include <iostream>

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
    char artistStr[256] = "Unknown Artist";
    char titleStr[256] = "Unknown Title";
    char albumStr[256] = "Unknown Album";

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
    double now = CFAbsoluteTimeGetCurrent();

    // Get the elapsed time from the now playing info
    auto elapsedTime = (CFNumberRef) CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoElapsedTime"));
    if (elapsedTime) {
        CFNumberGetValue(elapsedTime, kCFNumberDoubleType, &reportedElapsed);
    } else {
        // If the elapsed time is not available, use the last known value
        reportedElapsed = lastElapsed;
    }

    // If the reported elapsed time is the same as the last reported value, calculate the elapsed time based on the playback rate
    // Seek detection: if the difference between the reported elapsed time and the last known elapsed time is
    // greater than 0.5 seconds, use the reported elapsed time
    if (reportedElapsed == lastReportedElapsed) {
        elapsedValue = lastElapsed + (now - lastFetchTime) * playbackRate;
    } else {
        LOG_DEBUG("Seek detected: " + std::to_string(lastElapsed) + " -> " + std::to_string(reportedElapsed));
        elapsedValue = reportedElapsed;
    }

    lastElapsed = elapsedValue;
    lastReportedElapsed = reportedElapsed;
    lastFetchTime = now;

    return elapsedValue;
}
