//
// Created by Kunhua Huang on 3/7/25.
//

#ifndef BETTERSCROBBLER_MEDIAREMOTE_H
#define BETTERSCROBBLER_MEDIAREMOTE_H

#include <string>
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
};

#endif //BETTERSCROBBLER_MEDIAREMOTE_H
