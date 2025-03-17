#include "include/Config.h"
#include "include/Logger.h"

void Config::setScrobblingEnabled(bool enabled) {
    scrobblingEnabled = enabled;
    if (enabled) {
        LOG_DEBUG("Scrobbling enabled");
    } else {
        LOG_DEBUG("Scrobbling disabled");
    }
}

bool Config::toggleScrobbling() {
    scrobblingEnabled = !scrobblingEnabled;
    if (scrobblingEnabled) {
        LOG_DEBUG("Scrobbling enabled");
    } else {
        LOG_DEBUG("Scrobbling disabled");
    }
    return scrobblingEnabled;
} 