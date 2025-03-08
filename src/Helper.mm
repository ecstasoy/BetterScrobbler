//
// Created by Kunhua Huang on 3/7/25.
//

#include "header/Config.h"
#include "header/Logger.h"
#include "header/Helper.h"

double getAppleMusicDuration() {
    FILE *pipe = popen("osascript -e 'tell application \"Music\" to get duration of current track'", "r");
    if (!pipe) {
        return 0.0;
    }
    char buffer[128];
    std::string result;
    while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
        result += buffer;
    }
    pclose(pipe);

    try {
        return std::stod(result);
    } catch (...) {
        return 0.0;
    }
}