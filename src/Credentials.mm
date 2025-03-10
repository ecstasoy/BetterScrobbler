#include "include/Credentials.h"
#include "include/UrlUtils.h"
#include "../lib/json.hpp"
#include <string>
#include <map>
#include <Appkit/Appkit.h>
#import <Security/Security.h>
#import <Security/SecKeychain.h>
#import <Security/SecKeychainItem.h>

using json = nlohmann::json;

bool Credentials::authenticate() {

    std::string token = getAuthToken();
    if (token.empty()) {
        LOG_ERROR("Failed to get Last.fm token");
        return false;
    }

    openAuthPage(token);
    sessionKey = getSessionKey(token);

    if (sessionKey.empty()) {
        LOG_ERROR("Authentication failed");
        return false;
    }

    saveSessionKey(sessionKey);
    LOG_INFO("Authentication successful");
    return true;
}

std::string Credentials::getAuthToken() {

    std::map<std::string, std::string> params = {
            {"method", "auth.getToken"}
    };

    std::string url = UrlUtils::buildApiUrl("auth.getToken", params);
    std::string response = UrlUtils::sendGetRequest(url);

    try {
        json j = json::parse(response);
        return j["token"];
    } catch (...) {
        return "";
    }
}

void Credentials::openAuthPage(const std::string &token) {
    std::string url = "https://www.last.fm/api/auth/?api_key=" + getApiKey() +
                      "&token=" + token;

    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
            [NSString stringWithUTF8String:url.c_str()]]];

    LOG_INFO("Please authorize the application in your browser");
    std::cout << "Press Enter once you've authorized...\n";
    std::cin.ignore();
}

std::string Credentials::getSessionKey(const std::string &token) {
    std::map<std::string, std::string> params = {
            {"method", "auth.getSession"},
            {"token",  token}
    };

    std::string url = UrlUtils::buildApiUrl("auth.getSession", params);
    std::string response = UrlUtils::sendGetRequest(url);

    try {
        json j = json::parse(response);
        if (j.contains("session") && j["session"].contains("key")) {
            std::string sk = j["session"]["key"];
            saveSessionKey(sk);
            return sk;
        }
    } catch (const std::exception &e) {
        lastError = "Failed to parse session key: " + std::string(e.what());
        LOG_ERROR(lastError);
    }
    return "";
}

void Credentials::saveSessionKey(const std::string &sk) {
    saveToKeyChain(Config::getInstance().getKeychainService(),
                   Config::getInstance().getKeychainSessionKeyAccount(),
                   sk);
    LOG_INFO("Session key saved to keychain");
}

std::string Credentials::loadSessionKey() {
    std::string sessionKey = getFromKeyChain(Config::getInstance().getKeychainService(),
                                             Config::getInstance().getKeychainSessionKeyAccount());
    if (sessionKey.empty()) {
        LOG_ERROR("Failed to load session key from keychain");
    }
    return sessionKey;
}

std::string Credentials::getApiKey() {
    std::string apiKey = getFromKeyChain("com.scrobbler.credentials", "API_KEY");
    if (apiKey.empty()) {
        std::cout << "🔑 Enter your Last.fm API Key: ";
        std::getline(std::cin, apiKey);
        saveToKeyChain("com.scrobbler.credentials", "API_KEY", apiKey);
    }
    return apiKey;
}

std::string Credentials::getApiSecret() {
    std::string apiSecret = getFromKeyChain("com.scrobbler.credentials", "SHARED_SECRET");
    if (apiSecret.empty()) {
        std::cout << "🔑 Enter your Last.fm API Secret: ";
        std::getline(std::cin, apiSecret);
        saveToKeyChain("com.scrobbler.credentials", "SHARED_SECRET", apiSecret);
    }
    return apiSecret;
}

std::string Credentials::getFromKeyChain(const std::string &service, const std::string &account) {
    void *data = nullptr;
    UInt32 length = 0;

    OSStatus status = SecKeychainFindGenericPassword(nullptr,
                                                     (UInt32) service.length(), service.c_str(),
                                                     (UInt32) account.length(), account.c_str(),
                                                     &length, &data, nullptr);

    if (status == errSecSuccess) {
        std::string result((char *) data, length);
        SecKeychainItemFreeContent(nullptr, data);
        LOG_DEBUG(account + " retrieved from Keychain");
        return result;
    } else if (status == errSecItemNotFound) {
        LOG_ERROR(account + " not found in Keychain");
        std::string command = "security find-generic-password -s \"" + service + "\" -a \"" + account + "\" -w";
        FILE *pipe = popen(command.c_str(), "r");
        if (!pipe) {
            LOG_ERROR("Failed to execute security command");
            return "";
        }
        char buffer[128];
        std::string result;
        while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
            result += buffer;
        }
        pclose(pipe);

        // Trim newline
        result.erase(result.find_last_not_of('\n') + 1);

        if (result.empty()) {
            LOG_ERROR("Failed to retrieve " + account + " from Keychain");
        } else {
            LOG_DEBUG(account + " retrieved from Keychain");
        }
        return result;
    }

    LOG_ERROR("Keychain error: " + std::to_string(status));

    return "";
}

void Credentials::saveToKeyChain(const std::string &service, const std::string &account, const std::string &value) {
    OSStatus status = SecKeychainAddGenericPassword(nullptr,
                                                    (UInt32) service.length(), service.c_str(),
                                                    (UInt32) account.length(), account.c_str(),
                                                    (UInt32) value.length(), value.c_str(),
                                                    nullptr);

    if (status == errSecSuccess) {
        LOG_INFO(account + " saved to Keychain");
        return;
    } else if (status == errSecDuplicateItem) {
        LOG_INFO(account + " already exists in Keychain");
        return;
    } else {
        LOG_ERROR("Keychain error: " + std::to_string(status));
        std::string command =
                "security add-generic-password -s \"" + service + "\" -a \"" + account + "\" -w \"" + value + "\"";
        int result = system(command.c_str());

        if (result == 0) {
            LOG_INFO(account + " saved to Keychain using CLI fallback");
        } else {
            LOG_INFO("Failed to save " + account + " to Keychain using CLI fallback");
        }
    }

}
