#ifndef BETTERSCROBBLER_CONFIG_H
#define BETTERSCROBBLER_CONFIG_H

#include <string>

class Config {
public:
    static Config &getInstance() {
        static Config instance;
        return instance;
    }

    void setDaemonMode(bool enabled) { isDaemon = enabled; }

    [[nodiscard]] bool isDaemonMode() const { return isDaemon; }

    [[nodiscard]] const std::string &getLogPath() const { return logPath; }

    void setLogPath(const std::string &path) { logPath = path; }

    [[nodiscard]] bool isShowLyrics() const { return showLyrics; }

    void setShowLyrics(bool enabled) { showLyrics = enabled; }

    void setPreferSyncedLyrics(bool enabled) { preferSyncedLyrics = enabled; }

    void setQuietMode(bool enabled) { quietMode = enabled; }

    [[nodiscard]] bool isQuietMode() const { return quietMode; }

    [[nodiscard]] bool isPreferSyncedLyrics() const { return preferSyncedLyrics; }

    [[nodiscard]] const std::string &getAppName() const { return appName; }

    void setAppName(const std::string &name) { appName = name; }

    // Credential storage configuration
    [[nodiscard]] const std::string &getKeychainService() const { return keychainService; }

    [[nodiscard]] const std::string &getKeychainApiKeyAccount() const { return keychainApiKeyAccount; }

    [[nodiscard]] const std::string &getKeychainSecretAccount() const { return keychainSecretAccount; }

    [[nodiscard]] const std::string &getKeychainSessionKeyAccount() const { return keychainSessionKeyAccount; }

private:
    Config() {
        appName = "Scrobbler";
        logPath = "/tmp/scrobbler.log";
        keychainService = "com.scrobbler.credentials";
        keychainApiKeyAccount = "API_KEY";
        keychainSecretAccount = "SHARED_SECRET";
        keychainSessionKeyAccount = "SESSION_KEY";
    }

    // Disable copy and assignment
    Config(const Config &) = delete;

    Config &operator=(const Config &) = delete;

    bool isDaemon = false;
    bool showLyrics = true;
    bool preferSyncedLyrics = true;
    bool quietMode = false;
    std::string logPath;
    std::string appName;
    std::string keychainService;
    std::string keychainApiKeyAccount;
    std::string keychainSecretAccount;
    std::string keychainSessionKeyAccount;
};

#endif //BETTERSCROBBLER_CONFIG_H
