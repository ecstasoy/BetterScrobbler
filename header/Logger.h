//
// Created by Kunhua Huang on 3/7/25.
//

#ifndef BETTERSCROBBLER_LOGGER_H
#define BETTERSCROBBLER_LOGGER_H

#include <string>
#include <fstream>
#include <iostream>
#include <ctime>
#include "Config.h"

class Logger {
public:
    enum class Level {
        DEBUG,
        INFO,
        ERROR
    };

    static Logger &getInstance() {
        static Logger instance;
        return instance;
    }

    void setDebugEnabled(bool enabled) { showDebug = enabled; }
    bool isDebugEnabled() const { return showDebug; }

    void init(bool isDaemon) {
        if (isDaemon) {
            setupDaemonLogging();
        }
    }

    void log(const std::string &message, Level level = Level::INFO) {
        std::string levelStr;
        switch (level) {
            case Level::DEBUG:
                levelStr = "DEBUG";
                break;
            case Level::INFO:
                levelStr = "INFO";
                break;
            case Level::ERROR:
                levelStr = "ERROR";
                break;
        }

        std::time_t now = std::time(nullptr);
        char timeStr[20];
        std::strftime(timeStr, sizeof(timeStr), "%Y-%m-%d %H:%M:%S", std::localtime(&now));

        std::string logMessage = std::string(timeStr) + " [" + levelStr + "] " + message + "\n";

        if (Config::getInstance().isDaemonMode() && logFile.is_open()) {
            logFile << logMessage;
            logFile.flush();
        }

        if (!Config::getInstance().isDaemonMode()) {
            if (level == Level::ERROR) {
                std::cerr << logMessage;
            } else if (level != Level::DEBUG || showDebug) {
                std::cout << logMessage;
            }
        }
    }

    void debug(const std::string &message) {
        if (showDebug) {
            log(message, Level::DEBUG);
        }
    }

    void info(const std::string &message) { log(message, Level::INFO); }

    void error(const std::string &message) { log(message, Level::ERROR); }

private:
    Logger() = default;

    Logger(const Logger &) = delete;

    Logger &operator=(const Logger &) = delete;

    void setupDaemonLogging() {
        const std::string &logPath = Config::getInstance().getLogPath();
        logFile.open(logPath, std::ios::app);
        if (!logFile.is_open()) {
            std::cerr << "❌ Failed to open log file: " << logPath << "\n";
        }
    }

    std::ofstream logFile;
    bool showDebug = false;
};

#define LOG_DEBUG(msg) Logger::getInstance().debug(msg)
#define LOG_INFO(msg) Logger::getInstance().info(msg)
#define LOG_ERROR(msg) Logger::getInstance().error(msg)

#endif //BETTERSCROBBLER_LOGGER_H
