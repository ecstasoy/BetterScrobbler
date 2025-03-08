//
// Created by Kunhua Huang on 3/7/25.
//

#ifndef BETTERSCROBBLER_URLUTILS_H
#define BETTERSCROBBLER_URLUTILS_H

#include <string>
#include <map>
#import <curl/curl.h>
#import "Credentials.h"

class UrlUtils {
public:
    static std::string buildApiUrl(const std::string &method,
                            const std::map<std::string, std::string> &params);

    static std::string sendGetRequest(const std::string &url, CURL *curl = nullptr, int maxRetries = 3);

    static std::string sendPostRequest(const std::string &url,
                                const std::map<std::string, std::string> &params,
                                CURL *curl = nullptr, int maxRetries = 3);

    static std::string generateSignature(const std::map<std::string, std::string> &params,
                                         Credentials &credentials);

private:
    static std::string urlEncode(const std::string &input);

    static std::string buildUrl(const std::string &baseUrl,
                                const std::map<std::string, std::string> &params);

    static std::string md5(const std::string &input);

    static std::string generateApiSignature(const std::map<std::string, std::string> &params,
                                            const std::string &apiSecret);

    static size_t writeCallback(void *ptr, size_t size, size_t nmemb, std::string *data);

    static bool processResponse(const std::string &response);

    static bool shouldRetry(const std::string &response, int attempt);

    static void waitBeforeRetry(int attempt);

    static std::string lastError;
    static std::chrono::system_clock::time_point lastRequestTime;
    static constexpr int MIN_REQUEST_INTERVAL_MS = 250;
};

#endif //BETTERSCROBBLER_URLUTILS_H
