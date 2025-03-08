//
// Created by Kunhua Huang on 3/8/25.
//

#include "header/credentials.h"
#include "header/UrlUtils.h"
#include "header/LastFmScrobbler.h"
#include "lib/json.hpp"
#include <string>
#include <map>
#include <Appkit/Appkit.h>

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
            std::string sessionKey = j["session"]["key"];
            saveSessionKey(sessionKey);
            return sessionKey;
        }
    } catch (const std::exception &e) {
        lastError = "Failed to parse session key: " + std::string(e.what());
        LOG_ERROR(lastError);
    }
    return "";
}