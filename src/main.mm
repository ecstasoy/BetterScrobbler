#import <CoreFoundation/CoreFoundation.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import <termios.h>
#import <stdio.h>
#import <sys/select.h>
#import <unistd.h>
#import "include/MediaRemote.h"
#import "include/Config.h"
#import "include/Logger.h"
#import "include/CommandLine.h"
#import "include/Credentials.h"

bool kbhit() {
    struct timeval tv{};
    fd_set fds;
    tv.tv_sec = 0;
    tv.tv_usec = 0;
    FD_ZERO(&fds);
    FD_SET(STDIN_FILENO, &fds);
    select(STDIN_FILENO+1, &fds, nullptr, nullptr, &tv);
    return FD_ISSET(STDIN_FILENO, &fds);
}

void handleKeyboardCommands() {
    if (kbhit()) {
        char c = (char) getchar();
        if (c == 's' || c == 'S') {
            bool enabled = Config::getInstance().toggleScrobbling();
            if (enabled) {
                printf("\rScrobbling: Enabled  \n");
            } else {
                printf("\rScrobbling: Disabled \n");
            }
        } else if (c == 'h' || c == 'H' || c == '?') {
            printf("\rAvailable commands:\n");
            printf("  s - Toggle scrobbling on/off\n");
            printf("  q - Quit application\n");
            printf("  h - Show this help\n");
        } else if (c == 'q' || c == 'Q') {
            printf("\rQuitting...\n");
            exit(0);
        }
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        CommandLine::parse(argc, argv);
        auto &logger = Logger::getInstance();
        logger.init(Config::getInstance().isDaemonMode());

        if (Config::getInstance().isDaemonMode()) {
            if (daemon(0, 0) == -1) {
                LOG_ERROR("Failed to daemonize process: " + std::string(strerror(errno)));
                return 1;
            }
            LOG_INFO("Starting scrobbler in daemon mode...");
        } else {
            // Set terminal to non-blocking mode for keyboard input handling
            struct termios old_tio = {}, new_tio = {};
            tcgetattr(STDIN_FILENO, &old_tio);
            new_tio = old_tio;
            new_tio.c_lflag &= ~(ICANON | ECHO);
            tcsetattr(STDIN_FILENO, TCSANOW, &new_tio);
            
            printf("Scrobbler is running...\n");
            printf("Press 'h' for available commands\n");
            printf("Scrobbling: %s\n", Config::getInstance().isScrobblingEnabled() ? "Enabled" : "Disabled");
        }

        if (!Credentials::getInstance().checkAndPrompt()) {
            return 1;
        }

        MediaRemote bridge;
        bridge.registerForNowPlayingNotifications();

        LOG_INFO("Scrobbler is running...");
        
        if (!Config::getInstance().isDaemonMode()) {
            // Create a timer to check for keyboard input every 100ms
            dispatch_source_t keyboardTimer = dispatch_source_create(
                DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue()
            );
            dispatch_source_set_timer(
                keyboardTimer, dispatch_time(DISPATCH_TIME_NOW, 0), 
                100 * NSEC_PER_MSEC, 0
            );
            dispatch_source_set_event_handler(keyboardTimer, ^{
                handleKeyboardCommands();
            });
            dispatch_resume(keyboardTimer);
        }
        
        CFRunLoopRun();
    }
}