//
// Created by Kunhua Huang on 3/7/25.
//

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
        for (int i = 1; i < argc; i++) {
            std::string arg = argv[i];
            processArg(arg);
        }
    }

    static void printUsage(const char *programName) {
        std::cout << "Usage: " << programName << " [options]\n"
                  << "Options:\n"
                  << "  --daemon    Run as a daemon process\n"
                  << "  --debug     Show debug message in the console\n"
                  << "  --log=PATH  Specify custom log file path\n"
                  << "  --help      Show this help message\n";
    }

private:
    static void processArg(const std::string &arg) {
        if (arg == "--debug") {
            Logger::getInstance().setDebugEnabled(true);
        }
        if (arg == "--daemon") {
            Config::getInstance().setDaemonMode(true);
        } else if (arg.substr(0, 6) == "--log=") {
            Config::getInstance().setLogPath(arg.substr(6));
        } else if (arg == "--help") {
            printUsage(Config::getInstance().getAppName().c_str());
            exit(0);
        } else {
            LOG_ERROR("Unknown argument: " + arg);
            printUsage(Config::getInstance().getAppName().c_str());
            exit(1);
        }
    }
};

#endif //BETTERSCROBBLER_COMMANDLINE_H
