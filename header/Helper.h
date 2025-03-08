//
// Created by Kunhua Huang on 3/7/25.
//

#ifndef BETTERSCROBBLER_HELPER_H
#define BETTERSCROBBLER_HELPER_H

#include <string>
#include <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>

void extractMetadata(CFDictionaryRef info, std::string &artist, std::string &title, std::string &album,
                     double &duration, double &reportedElapsed, double &playbackRate);

void resetScrobbleState(double &lastElapsed, double &lastDuration, double &lastFetchTime,
                        int &beginTimeStamp, bool &hasScrobbled);

double updateElapsedTime(CFDictionaryRef info, double &reportedElapsed, double playbackRate, double &elapsedValue,
                         double &lastElapsed, double &lastFetchTime, double &lastReportedElapsed);

void sendNowPlayingUpdate(const std::string &artist, const std::string &title, bool isMusic,
                          const std::string &album, double &lastNowPlayingSent, double playbackRate);

bool shouldScrobble(double elapsed, double duration, double playbackRate, bool isMusic, bool hasScrobbled);

bool isValidMusicContent(const std::string &artist, const std::string &title, const std::string &album);

bool extractMusicInfo(const std::string &videoTitle, std::string &outArtist, std::string &outTitle);

std::string cleanArtistName(const std::string &artist);

std::string normalizeString(const std::string &input);

#endif //BETTERSCROBBLER_HELPER_H
