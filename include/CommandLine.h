#ifndef BETTERSCROBBLER_COMMANDLINE_H
#define BETTERSCROBBLER_COMMANDLINE_H

#include <string>
#include <vector>
#include <iostream>
#include "Config.h"
#include "Logger.h"

class CommandLine {
public:
    static void parse(int argc, char *argv[]) {
        auto &config = Config::getInstance();
        auto &logger = Logger::getInstance();

        for (int i = 1; i < argc; i++) {
            std::string arg = argv[i];

            if (arg == "--daemon") {
                config.setDaemonMode(true);
            } else if (arg == "--debug") {
                logger.setDebugEnabled(true);
            } else if (arg.substr(0, 6) == "--log=") {
                config.setLogPath(arg.substr(6));
            } else if (arg == "--help") {
                showHelp();
                exit(0);
            } else {
                LOG_ERROR("Unknown argument: " + arg);
                showHelp();
                exit(1);
            }
        }
    }

private:
    static void showHelp() {
        std::cout << "Usage: Scrobbler [options]\n"
                  << "Options:\n"
                  << "  --daemon    Run as a daemon process\n"
                  << "  --debug     Show debug message in the console\n"
                  << "  --log=PATH  Specify custom log file path\n"
                  << "  --help      Show this help message\n";
    }
};

#endif //BETTERSCROBBLER_COMMANDLINE_H
