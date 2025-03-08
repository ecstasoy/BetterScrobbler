//
// Created by Kunhua Huang on 3/7/25.
//

#ifndef BETTERSCROBBLER_CREDENTIALS_H
#define BETTERSCROBBLER_CREDENTIALS_H

#include <string>
#include "Config.h"
#include "Logger.h"
#include "LastFmScrobbler.h"

class Credentials {
public:
    static Credentials &getInstance() {
        static Credentials instance;
        return instance;
    }

    bool checkAndPrompt() {
        apiKey = getApiKey();
        if (apiKey.empty()) {
            LOG_ERROR("Missing API Key");
            return false;
        }

        apiSecret = getApiSecret();
        if (apiSecret.empty()) {
            LOG_ERROR("Missing API Secret");
            return false;
        }

        sessionKey = loadSessionKey();
        if (sessionKey.empty()) {
            LOG_INFO("No session key found. Starting authentication flow...");
            if (!authenticate()) {
                return false;
            }
        }

        return true;
    }

    const std::string &getStoredApiKey() const { return apiKey; }

    const std::string &getStoredApiSecret() const { return apiSecret; }

    const std::string &getSessionKey() const { return sessionKey; }

    std::string getApiKey();

    std::string getAuthToken();

    void openAuthPage(const std::string &token);

    std::string getSessionKey(const std::string &token);

    void saveSessionKey(const std::string &sessionKey);

    std::string loadSessionKey();

    std::string getApiSecret();

private:
    Credentials() = default;

    Credentials(const Credentials &) = delete;

    Credentials &operator=(const Credentials &) = delete;

    bool authenticate();

    std::string apiKey;
    std::string apiSecret;
    std::string sessionKey;
    std::string lastError;
};

#endif //BETTERSCROBBLER_CREDENTIALS_H
