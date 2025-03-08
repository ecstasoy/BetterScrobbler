//
// Created by Kunhua Huang on 3/7/25.
//

#import <CoreFoundation/CoreFoundation.h>
#import "header/MediaRemote.h"
#import "header/Config.h"
#import "header/Logger.h"
#import "header/CommandLine.h"
#import "header/Credentials.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        CommandLine::parse(argc, argv);
        Logger::getInstance().init(Config::getInstance().isDaemonMode());

        if (Config::getInstance().isDaemonMode()) {
            if (daemon(0, 0) == -1) {
                LOG_ERROR("Failed to daemonize process: " + std::string(strerror(errno)));
                return 1;
            }
            LOG_INFO("Starting scrobbler in daemon mode...");
        }

        if (!Credentials::getInstance().checkAndPrompt()) {
            return 1;
        }

        MediaRemote bridge;
        bridge.registerForNowPlayingNotifications();

        LOG_INFO("Scrobbler is running...");
        CFRunLoopRun();
    }
}