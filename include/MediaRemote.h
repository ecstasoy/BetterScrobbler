#ifndef SCROBBLER_MEDIAREMOTE_H
#define SCROBBLER_MEDIAREMOTE_H

#include <string>
#include <mutex>
#include "LastFmScrobbler.h"

class MediaRemote {
public:
    MediaRemote();

    ~MediaRemote();

    /**
     * @brief Register for notifications from the media remote.
     * This will allow us to receive notifications when the now playing item changes.
     */
    void registerForNowPlayingNotifications();

private:
    class Impl;

    Impl *impl;
    std::mutex mediaRemoteMutex;
};

#endif //SCROBBLER_MEDIAREMOTE_H
