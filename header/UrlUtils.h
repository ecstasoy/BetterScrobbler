//
// Created by Kunhua Huang on 3/7/25.
//

#ifndef BETTERSCROBBLER_URLUTILS_H
#define BETTERSCROBBLER_URLUTILS_H

#include <string>
#include <map>

class UrlUtils {
public:
    static std::string urlEncode(const std::string &input);

    static std::string buildUrl(const std::string &baseUrl,
                                const std::map<std::string, std::string> &params);

    static std::string md5(const std::string &input);

    static std::string generateApiSignature(const std::map<std::string, std::string> &params,
                                            const std::string &apiSecret);
};

#endif //BETTERSCROBBLER_URLUTILS_H
