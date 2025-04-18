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

    [[nodiscard]] const std::string &getStoredApiKey() const { return apiKey; }

    [[nodiscard]] const std::string &getStoredApiSecret() const { return apiSecret; }

    [[nodiscard]] const std::string &getSessionKey() const { return sessionKey; }

    static std::string getApiKey();

    static std::string getAuthToken();

    void openAuthPage(const std::string &token);

    std::string getSessionKey(const std::string &token);

    static void saveSessionKey(const std::string &sk);

    static std::string loadSessionKey();

    static std::string getApiSecret();

private:
    Credentials() = default;

    Credentials(const Credentials &) = delete;

    Credentials &operator=(const Credentials &) = delete;

    static std::string getFromKeyChain(const std::string &service, const std::string &account);

    static void saveToKeyChain(const std::string &service, const std::string &account, const std::string &value);

    bool authenticate();

    std::string apiKey;
    std::string apiSecret;
    std::string sessionKey;
    std::string lastError;
};

#endif //BETTERSCROBBLER_CREDENTIALS_H
