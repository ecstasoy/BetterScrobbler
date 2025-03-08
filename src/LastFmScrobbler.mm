//
// Created by Kunhua Huang on 3/7/25.
//

#include "header/LastFmScrobbler.h"
#include "lib/json.hpp"

using json = nlohmann::json;

// Internal namespace for private functions
namespace {

}

LastFmScrobbler::LastFmScrobbler() : curl(nullptr) {
    init();
}

LastFmScrobbler::~LastFmScrobbler() {
    cleanup();
}

bool LastFmScrobbler::init() {
    curl = curl_easy_init();
    if (!curl) {
        lastError = "Failed to initialize CURL";
        LOG_ERROR(lastError);
        return false;
    }
    return true;
}

void LastFmScrobbler::cleanup() {
    if (curl) {
        curl_easy_cleanup(curl);
        curl = nullptr;
    }
}

