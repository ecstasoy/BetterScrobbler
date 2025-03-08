#include <header/UrlUtils.h>
#include <string>
#include <map>
#include <sstream>
#include <iomanip>
#include <CommonCrypto/CommonDigest.h>

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