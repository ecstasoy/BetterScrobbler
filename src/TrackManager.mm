#include <include/TrackManager.h>
#include <include/Logger.h>
#include <include/Helper.h>
#include <include/LyricsManager.h>
#include <sys/ioctl.h>
#include <mutex>
#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>

auto &config = Config::getInstance();
auto &lyricsManager = LyricsManager::getInstance();

namespace {
    std::string safeStringCopy(const std::string &input) {
        @autoreleasepool {
            if (input.empty()) {
                return "";
            }
            NSString *nsStr = [[NSString alloc] initWithUTF8String:input.c_str()];
            if (!nsStr) {
                return "";
            }
            std::string result(nsStr.UTF8String);
            [nsStr release];
            return result;
        }
    }

    std::string trim(const std::string &str) {
        size_t first = str.find_first_not_of(" \t\n\r");
        if (first == std::string::npos) {
            return "";
        }
        size_t last = str.find_last_not_of(" \t\n\r");
        return str.substr(first, (last - first + 1));
    }
}

std::string TrackManager::generateTrackId(const std::string &artist, const std::string &title, const std::string &album) {
    @autoreleasepool {
        LOG_DEBUG("Generating track ID for - Artist: '" + artist + "', Title: '" + title + "', Album: '" + album + "'");
        
        @try {
            // 使用安全的字符串复制
            std::string safeArtist = safeStringCopy(artist);
            std::string safeTitle = safeStringCopy(title);
            std::string safeAlbum = safeStringCopy(album);
            
            LOG_DEBUG("Safe strings copied - Artist: '" + safeArtist + "', Title: '" + safeTitle + "', Album: '" + safeAlbum + "'");
            
            // 去除空白字符
            safeArtist = trim(safeArtist);
            safeTitle = trim(safeTitle);
            safeAlbum = trim(safeAlbum);
            
            LOG_DEBUG("Strings trimmed - Artist: '" + safeArtist + "', Title: '" + safeTitle + "', Album: '" + safeAlbum + "'");
            
            // 生成唯一的track ID
            std::string trackId = safeArtist + "|" + safeTitle + "|" + safeAlbum;
            
            LOG_DEBUG("Generated track ID: '" + trackId + "'");
            return trackId;
        } @catch (NSException *exception) {
            LOG_ERROR("Exception in generateTrackId: " + std::string([[exception description] UTF8String]));
            return "";
        }
    }
}

void TrackManager::processTitleChange(const std::string &artist, const std::string &title, const std::string &album,
                                      double playbackRateValue) {
    @autoreleasepool {
        LOG_DEBUG("Title changed: '" + lastTitle + "' -> '" + title + "'");
        LOG_DEBUG("Artist: '" + artist + "', Album: '" + album + "'");

        if (currentTrack && currentTrack->hasScrobbled && !currentTrack->hasSubmitted && currentTrack->isMusic) {
            LOG_DEBUG("Attempting to scrobble previous track");
            currentTrack->hasSubmitted = scrobbler.scrobble(currentTrack->artist,
                                                            currentTrack->title,
                                                            currentTrack->album,
                                                            currentTrack->duration,
                                                            currentTrack->beginTimeStamp);
            LOG_DEBUG("Previous track scrobbled on change");
        }

        lyricsManager.clearLyricsArea();

        bool isMusic = false;
        extractedArtist = safeStringCopy(artist);
        extractedTitle = safeStringCopy(title);
        LOG_DEBUG("Extracted artist: '" + extractedArtist + "', title: '" + extractedTitle + "'");

        if (isFromMusicPlatform) {
            isMusic = true;
            LOG_DEBUG("Using platform metadata: " + extractedArtist + " - " + extractedTitle);
        } else if (Helper::extractMusicInfo(artist, title, album, extractedArtist, extractedTitle)) {
            isMusic = true;
            LOG_DEBUG("Extracted metadata: " + extractedArtist + " - " + extractedTitle);
        }

        if (isMusic) {
            LOG_DEBUG("Updating track info for music content");
            updateTrackInfo(extractedArtist, extractedTitle, album, isMusic, 0.0, 0.0);
            lastTitle = safeStringCopy(title);
            lastArtist = safeStringCopy(artist);
            lastAlbum = safeStringCopy(album);

            LOG_INFO("⏭️ Switched to: " + extractedArtist + " - " + extractedTitle + " [" + album + "]  (" +
                     std::to_string(currentTrack->duration) + " sec)");
            LOG_DEBUG("Resetting scrobble state for new track");

            if (config.isShowLyrics()) {
                if (currentTrack->hasSyncedLyrics && config.isPreferSyncedLyrics()) {
                    LOG_INFO("Synced lyrics found for: " + currentTrack->artist + " - " + currentTrack->title);
                } else if (!currentTrack->plainLyrics.empty()) {
                    LOG_INFO("Plain lyrics found for: " + currentTrack->artist + " - " + currentTrack->title);
                } else {
                    LOG_INFO("No lyrics found for: " + currentTrack->artist + " - " + currentTrack->title);
                }
            }
        } else {
            LOG_DEBUG("Updating track info for non-music content");
            updateTrackInfo(artist, title, album, isMusic, 0.0, 0.0);
            lastTitle = safeStringCopy(title);
            lastArtist = safeStringCopy(artist);
            lastAlbum = safeStringCopy(album);

            LOG_INFO("⏭️ Switched to: " + title);
            LOG_INFO("Detected non-music content: " + artist + " - " + title + ", skipping...");
        }
    }
}

void TrackManager::handlePlaybackStateChange(double playbackRateValue, double elapsedValue) {

    if (!currentTrack) return;

    double progressPercentage = (currentTrack->duration > 0.0)
                                ? (elapsedValue / currentTrack->duration) * 100.0
                                : 0.0;

    if (!currentTrack->hasScrobbled &&
        LastFmScrobbler::shouldScrobble(elapsedValue, currentTrack->duration,
                                        playbackRateValue, currentTrack->isMusic)) {
        currentTrack->hasScrobbled = true;
        LOG_DEBUG("Track reached scrobble threshold");
    }

    std::string playbackState = (playbackRateValue == 0.0) ? "⏸️ Paused" :
                                (playbackRateValue > 0.0) ? "▶️ Playing" : "⏹️ Stopped";

    if (playbackState != lastPlaybackState) {
        lastPlaybackState = playbackState;
        if (currentTrack->isMusic) {
            LOG_INFO(
                    playbackState + ": " + currentTrack->artist + " - " + currentTrack->title + " [" +
                    currentTrack->album +
                    "]  (" +
                    std::to_string(currentTrack->duration) + " sec)");
        } else {
            LOG_INFO(playbackState + ": " + currentTrack->title);
        }
    }

    if (currentTrack->title == lastTitle && progressPercentage < 10.0 && playbackRateValue > 0.0 &&
        currentTrack->hasScrobbled && currentTrack->isMusic) {
        if (!currentTrack->hasSubmitted) {
            scrobbler.scrobble(currentTrack->artist,
                               currentTrack->title,
                               currentTrack->album,
                               currentTrack->duration,
                               currentTrack->beginTimeStamp);
            LOG_DEBUG("Looped track scrobbled on restart");
        }
        LOG_INFO("Scrobbled song restarted： " + currentTrack->artist + " - " + currentTrack->title + " [" +
                 currentTrack->album + "]  (" +
                 std::to_string(currentTrack->duration) + " sec)");
        updateTrackInfo(currentTrack->artist,
                        currentTrack->title,
                        currentTrack->album,
                        currentTrack->isMusic,
                        currentTrack->duration,
                        elapsedValue);
        currentTrack->hasScrobbled = false;
        currentTrack->hasSubmitted = false;
    }
}

void TrackManager::updateTrackInfo(const std::string &artist, const std::string &title, const std::string &album,
                                   bool isMusic, double duration, double elapsedValue) {

    LOG_DEBUG("Updating track info - Artist: '" + artist + "', Title: '" + title + "', Album: '" + album + "'");
    
    @autoreleasepool {
        std::string trackId;
        @try {
            LOG_DEBUG("Generating track ID");
            trackId = TrackManager::generateTrackId(artist, title, album);
            if (trackId.empty()) {
                LOG_ERROR("Failed to generate track ID");
                return;
            }
            LOG_DEBUG("Generated track ID: " + trackId);
            
            double currentTime = CFAbsoluteTimeGetCurrent();
            LOG_DEBUG("Current time: " + std::to_string(currentTime));

            // Check if track is already in cache, only update necessary fields
            auto it = trackCache.find(trackId);
            if (it != trackCache.end()) {
                LOG_DEBUG("Found existing track in cache");
                auto &state = it->second;
                double timeDiff = currentTime - state.lastFetchTime;
                LOG_DEBUG("Time difference: " + std::to_string(timeDiff));
                if (timeDiff > 0) {
                    state.lastPlaybackRate = (elapsedValue - state.lastElapsed) / timeDiff;
                    LOG_DEBUG("Updated playback rate: " + std::to_string(state.lastPlaybackRate));
                }
                state.lastFetchTime = currentTime;
                state.lastElapsed = elapsedValue;
                if (duration > 0) {
                    state.duration = duration;
                }
                currentTrack = &state;
                LOG_DEBUG("Updated existing track in cache");
                return;
            }

            LOG_DEBUG("Creating new track in cache");
            // 如果缓存已满，删除最旧的条目
            if (trackCache.size() >= MAX_TRACK_CACHE) {
                LOG_DEBUG("Cache is full, removing oldest entry");
                auto oldestIt = std::min_element(trackCache.begin(), trackCache.end(),
                    [](const auto &a, const auto &b) {
                        return a.second.lastFetchTime < b.second.lastFetchTime;
                    });
                if (oldestIt != trackCache.end()) {
                    trackCache.erase(oldestIt);
                    LOG_DEBUG("Removed oldest track from cache");
                }
            }

            // 创建新的track状态
            LOG_DEBUG("Creating new track state");
            auto &state = trackCache[trackId];
            LOG_DEBUG("Created new track state entry");
            
            // 使用安全的字符串复制
            @try {
                LOG_DEBUG("Copying track strings");
                state.artist = safeStringCopy(artist);
                state.extractArtist = state.artist;
                state.title = safeStringCopy(title);
                state.extractTitle = state.title;
                state.album = safeStringCopy(album);
                LOG_DEBUG("Copied track strings safely");
            } @catch (NSException *exception) {
                LOG_ERROR("Exception while copying strings: " + std::string([[exception description] UTF8String]));
                trackCache.erase(trackId);
                return;
            }
            
            LOG_DEBUG("Initializing track state values");
            state.isMusic = isMusic;
            state.beginTimeStamp = static_cast<int>(std::time(nullptr));
            state.lastFetchTime = currentTime;
            state.hasScrobbled = false;
            state.hasSubmitted = false;
            state.lastElapsed = elapsedValue;
            state.duration = duration;
            state.lastNowPlayingSent = currentTime;
            state.lastPlaybackRate = 1.0; // 默认播放速率为1.0
            state.lastReportedElapsed = elapsedValue;
            LOG_DEBUG("Initialized track state values");

            // 清理旧的歌词数据
            LOG_DEBUG("Clearing lyrics data");
            state.plainLyrics.clear();
            state.syncedLyrics.clear();
            state.hasSyncedLyrics = false;
            state.parsedSyncedLyrics.clear();
            state.currentLyricIndex = -1;
            LOG_DEBUG("Cleared lyrics data");

            currentTrack = &state;
            lastArtist = state.artist;
            lastTitle = state.title;
            lastAlbum = state.album;

            LOG_DEBUG("Created new track state - Artist: '" + state.artist + "', Title: '" + state.title + 
                     "', Album: '" + state.album + "', Duration: " + std::to_string(state.duration));

            // 获取新的歌词
            if (config.isShowLyrics()) {
                LOG_DEBUG("Fetching lyrics for new track");
                @try {
                    LyricsManager::getInstance().clearLyricsArea();
                    LyricsManager::getInstance().fetchLyrics(
                            state.artist,
                            state.title,
                            state.album,
                            state.duration
                    );
                    LyricsManager::getInstance().forceRefreshLyrics();
                    LOG_DEBUG("Successfully fetched and processed lyrics");
                } @catch (NSException *exception) {
                    LOG_ERROR("Exception while fetching lyrics: " + std::string([[exception description] UTF8String]));
                }
            }
            
            LOG_DEBUG("Track info update completed successfully");
        } @catch (NSException *exception) {
            LOG_ERROR("Exception in updateTrackInfo: " + std::string([[exception description] UTF8String]));
            if (!trackId.empty() && trackCache.find(trackId) != trackCache.end()) {
                trackCache.erase(trackId);
            }
        }
    }
}