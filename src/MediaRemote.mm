//
// Created by Kunhua Huang on 3/7/25.
//

#include <CoreFoundation/CoreFoundation.h>
#inclide <dispatch/dispatch.h>
#include <header/MediaRemote.h>

typedef void (*MRMediaRemoteGetNowPlayingInfo_t)(dispatch_queue_t, void(^)(CFDictionaryRef));

class MediaRemote::Impl {

};

#pragma mark - MediaRemoteBridge

MediaRemote::MediaRemote()
        : impl(new Impl) {
}

MediaRemote::~MediaRemote() {
    delete impl;
}

void MediaRemote::registerForNowPlayingNotifications() {

}