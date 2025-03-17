#include "include/UrlUtils.h"
#include "include/Credentials.h"
#include "../lib/json.hpp"
#include <curl/curl.h>
#include <string>
#include <map>
#include <sstream>
#include <iomanip>
#include <thread>
#include <CommonCrypto/CommonDigest.h>

using json = nlohmann::json;

std::string UrlUtils::urlEncode(const std::string &input) {
    std::ostringstream encoded;
    for (unsigned char c: input) {
        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            encoded << c;
        } else if (c == ' ') {
            encoded << '+';
        } else {
            encoded << '%' << std::uppercase << std::hex << std::setw(2)
                    << std::setfill('0') << static_cast<int>(c);
        }
    }
    return encoded.str();
}

std::string UrlUtils::buildUrl(const std::string &baseUrl,
                               const std::map<std::string, std::string> &params) {
    std::string url = baseUrl;
    bool first = true;

    for (const auto &param: params) {
        url += (first ? "?" : "&");
        url += urlEncode(param.first) + "=" + urlEncode(param.second);
        first = false;
    }

    return url;
}

std::string UrlUtils::md5(const std::string &input) {
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(input.c_str(), (CC_LONG) input.length(), digest);

    std::ostringstream ss;
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; ++i) {
        ss << std::hex << std::setw(2) << std::setfill('0') << (int) digest[i];
    }
    return ss.str();
}

std::string UrlUtils::generateApiSignature(const std::map<std::string, std::string> &params,
                                           const std::string &apiSecret) {

    std::vector<std::pair<std::string, std::string>> sortedParams(params.begin(), params.end());
    std::sort(sortedParams.begin(), sortedParams.end());

    std::string baseString;
    for (const auto &pair: sortedParams) {
        if (pair.first != "format" && pair.first != "callback") {
            baseString += pair.first + pair.second;
        }
    }

    baseString += apiSecret;
    return md5(baseString);
}

std::string UrlUtils::generateSignature(const std::map<std::string, std::string> &params,
                                        Credentials &credentials) {
    std::string shared_secret = credentials.getApiSecret();

    std::vector<std::pair<std::string, std::string>> sortedParams(params.begin(), params.end());
    std::sort(sortedParams.begin(), sortedParams.end());

    std::string baseString;
    for (const auto &pair: sortedParams) {
        if (pair.first != "format" && pair.first != "callback" && pair.first != "api_sig") {
            baseString += pair.first + pair.second;
        }
    }

    baseString += shared_secret;
    return md5(baseString);
}

size_t UrlUtils::writeCallback(void *ptr, size_t size, size_t nmemb, std::string *data) {
    if (!data) return 0;
    data->append((char *) ptr, size * nmemb);
    return size * nmemb;
}

std::string UrlUtils::buildApiUrl(const std::string &method,
                                  const std::map<std::string, std::string> &params) {
    auto &credentials = Credentials::getInstance();
    std::map<std::string, std::string> allParams = params;
    allParams["method"] = method;
    allParams["api_key"] = credentials.getApiKey();

    std::string apiSig = generateSignature(allParams, credentials);

    allParams["api_sig"] = apiSig;
    allParams["format"] = "json";

    std::string url = UrlUtils::buildUrl("https://ws.audioscrobbler.com/2.0/", allParams);
    LOG_DEBUG("Generated URL: " + url);
    return url;
}

std::string UrlUtils::sendGetRequest(const std::string &url, CURL *curl, int maxRetries) {
    bool needsCleanup = false;
    if (!curl) {
        curl = curl_easy_init();
        if (!curl) {
            lastError = "Failed to initialize CURL";
            LOG_ERROR(lastError);
            return "";
        }
        needsCleanup = true;
    }

    auto now = std::chrono::system_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
            now - lastRequestTime).count();
    if (elapsed < MIN_REQUEST_INTERVAL_MS) {
        std::this_thread::sleep_for(
                std::chrono::milliseconds(MIN_REQUEST_INTERVAL_MS - elapsed));
    }

    try {
        for (int attempt = 1; attempt <= maxRetries; ++attempt) {
            std::string response;
            curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
            curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
            curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
            curl_easy_setopt(curl, CURLOPT_USERAGENT, "Scrobbler/1.0");

            CURLcode res = curl_easy_perform(curl);
            lastRequestTime = std::chrono::system_clock::now();

            if (res != CURLE_OK) {
                lastError = "CURL error: " + std::string(curl_easy_strerror(res));
                LOG_ERROR(lastError);

                if (shouldRetry(response, attempt)) {
                    waitBeforeRetry(attempt);
                    continue;
                }
                return "";
            }

            if (!processResponse(response)) {
                if (shouldRetry(response, attempt)) {
                    waitBeforeRetry(attempt);
                    continue;
                }
                return "";
            }

            if (needsCleanup && curl) {
                curl_easy_cleanup(curl);
            }

            return response;
        }
    } catch (const std::exception &e) {
        lastError = "Exception: " + std::string(e.what());
        LOG_ERROR(lastError);
    }

    lastError = "Max retries exceeded";
    LOG_ERROR(lastError);

    if (needsCleanup && curl) {
        curl_easy_cleanup(curl);
    }
    return "";
}

std::string UrlUtils::sendPostRequest(const std::string &url,
                                      const std::map<std::string, std::string> &params,
                                      CURL *curl, int maxRetries) {
    bool needsCleanup = false;
    if (!curl) {
        curl = curl_easy_init();
        if (!curl) {
            lastError = "Failed to initialize CURL";
            LOG_ERROR(lastError);
            return "";
        }
        needsCleanup = true;
    }

    auto now = std::chrono::system_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
            now - lastRequestTime).count();
    if (elapsed < MIN_REQUEST_INTERVAL_MS) {
        std::this_thread::sleep_for(
                std::chrono::milliseconds(MIN_REQUEST_INTERVAL_MS - elapsed));
    }

    std::string postFields;
    for (const auto &param: params) {
        if (!postFields.empty()) postFields += "&";
        postFields += UrlUtils::urlEncode(param.first) + "=" +
                      UrlUtils::urlEncode(param.second);
    }

    LOG_DEBUG("POST fields: " + postFields);

    try {
        for (int attempt = 1; attempt <= maxRetries; ++attempt) {
            std::string response;
            curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
            curl_easy_setopt(curl, CURLOPT_POSTFIELDS, postFields.c_str());
            curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
            curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
            curl_easy_setopt(curl, CURLOPT_USERAGENT, "Scrobbler/1.0");

            CURLcode res = curl_easy_perform(curl);
            lastRequestTime = std::chrono::system_clock::now();

            if (res != CURLE_OK) {
                lastError = "CURL error: " + std::string(curl_easy_strerror(res));
                LOG_ERROR(lastError);

                if (shouldRetry(response, attempt)) {
                    waitBeforeRetry(attempt);
                    continue;
                }
                return "";
            }

            if (!processResponse(response)) {
                if (shouldRetry(response, attempt)) {
                    waitBeforeRetry(attempt);
                    continue;
                }
                return "";
            }

            if (needsCleanup && curl) {
                curl_easy_cleanup(curl);
            }

            return response;
        }
    } catch (const std::exception &e) {
        lastError = "Exception: " + std::string(e.what());
        LOG_ERROR(lastError);
    }

    if (needsCleanup && curl) {
        curl_easy_cleanup(curl);
    }

    lastError = "Max retries exceeded";
    LOG_ERROR(lastError);
    return "";
}

bool UrlUtils::processResponse(const std::string &response) {
    try {
        json j = json::parse(response);
        if (j.contains("error")) {
            int errorCode = j["error"];
            std::string errorMessage = j["message"];
            lastError = "Last.fm API error " + std::to_string(errorCode) +
                        ": " + errorMessage;
            LOG_ERROR(lastError);
            return false;
        }
        return true;
    } catch (const std::exception &e) {
        lastError = "Failed to parse response: " + std::string(e.what());
        LOG_ERROR(lastError);
        return false;
    }
}

bool UrlUtils::shouldRetry(const std::string &response, int attempt) {
    try {
        json j = json::parse(response);
        if (j.contains("error")) {
            int errorCode = j["error"];

            switch (errorCode) {
                case 11: // Service Offline
                case 16: // Service Temporarily Unavailable
                case 29: // Rate Limit Exceeded
                    return true;
                default:
                    return false;
            }
        }
    } catch (...) {
        return true;
    }
    return false;
}

void UrlUtils::waitBeforeRetry(int attempt) {
    int delay = std::min(1000 * (1 << (attempt - 1)), 30000);
    std::this_thread::sleep_for(std::chrono::milliseconds(delay));
}

std::string UrlUtils::lastError;
std::chrono::system_clock::time_point UrlUtils::lastRequestTime;