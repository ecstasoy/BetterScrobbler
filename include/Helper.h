#ifndef BETTERSCROBBLER_HELPER_H
#define BETTERSCROBBLER_HELPER_H

#include <string>
#include <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>


class Helper {
public:
    static Helper &getInstance() {
        static Helper instance;
        return instance;
    }

    Helper() = default;

    ~Helper() = default;

    static void
    extractMetadata(CFDictionaryRef info, std::string &artist, std::string &title, std::string &album, double &duration,
                    double &playbackRate);

    static double updateElapsedTime(CFDictionaryRef info, double &reportedElapsed, double playbackRate, double &elapsedValue,
                                    double &lastElapsed, double &lastFetchTime, double &lastReportedElapsed);

    static bool isValidContent(std::string &artist, std::string &title);

    static bool
    extractMusicInfo(const std::string &artist, const std::string &title, std::string &outArtist,
                     std::string &outTitle);

    static std::string cleanArtistName(const std::string &artist);

    static std::string cleanVideoTitle(std::string title);

    static std::string normalizeString(const std::string &input);

    static std::string toLower(std::string str);

    static int levenshteinDistance(const std::string &s1, const std::string &s2);
};

#endif //BETTERSCROBBLER_HELPER_H
