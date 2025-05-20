# BetterScrobbler
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/8aa48c219e2543439039cb1f116c47cc)](https://app.codacy.com/gh/ecstasoy/BetterScrobbler/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)

**UPDATE: Apple seems to deprive user program's permission to use MediaRemote since macOS 15.4.**

**RIP, you had a short but beautiful life**

A better Last.fm scrobbler for macOS, and it works globally!

## Introduction
Are you sick of the lack of reliable scrobblers on macOS?

Foobar2000's scrobble plugin was deprecated, Apple Music does not support built-in scrobbling, and there is absolutely no way to scrobble on Netease Music's desktop application.

All the workarounds may not be worth the hassle now. BetterScrobbler is a CLI scrobbler that scrobbles ANY music playing on you Mac. And yes, it even works for your browser! (not always)

## Preparation (easy)
It is **important** to do this before everything.
1. Open [this page](https://www.last.fm/api/account/create) to create an API account
2. You only need to fill in the first two column. For "Application name", fill in whatever you want!
   
  ![Image](https://github.com/user-attachments/assets/cf103447-9df0-4802-9243-428a9aa27378)

3. Success! Now you have an **API key** and **shared secret**. You can take a screenshot of the page open, or visit [this page](https://www.last.fm/api/accounts) anytime.
4. Remeber do not expose these credentials anywhere. BetterScrobbler will also make sure they are secured by storing it in macOS's Keychain.

## Installatiion
### HomeBrew (Recommended)
1. Make sure you have HomeBrew installed. If you haven't, open terminal and copy-paste to run:
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
2. Again, copy-paste and run:
```
brew tap ecstasoy/scrobbler
brew install scrobbler
```
3. Wait for the compilation and done!

## Basic Usage
### First time running setup:
1. Run the scrobbler in terminal:
```
scrobbler
```
2. Prepare your API key and shared secret. Copy-paste your credentials when prompted:
3. These credentials will be stored in macOS' Keychain and secured by system-level protection.
4. If credentials are correct, your default browser will open and bring you to this page:
   ![Image](https://github.com/user-attachments/assets/97b3ecba-e9ed-4390-b5c0-5b50d4a1415f)
5. The application name displayed here will be anything you filled when creating API account.
6. Click 'Yes, allow access'.
7. Press ENTER.

### Running as foreground CLI program:
1. Run the scrobbler in terminal:
```
scrobbler
```
2. If the setup is correct, the program should be running perfectly:
```
[INFO] Scrobbler is running...
```
4. Information displayed on the console includes:
   - Information of the song currently playing/paused **at the foreground**.
   - The playback state of the song
     ```
     [INFO] ▶️ Playing: the Mountain Goats - Against Pollution (Jordan Lake Sessions) []  (369.941000 sec)
     ```
     ```
     [INFO] ⏸ Paused: the Mountain Goats - Against Pollution (Jordan Lake Sessions) []  (369.941000 sec)
     ```
   - Notification when the song is scrobbled to Last.fm
     ```
     [INFO] Scrobbled: the Mountain Goats - Against Pollution (Jordan Lake Sessions)
     ```
   - **Lyrics Display (New Feature!)**:
     - If lyrics are found for the current song, they will be displayed in the terminal.
     - Supports both plain text lyrics and synchronized lyrics (LRC format).
     - Lyrics are fetched from [lrclib.net](https://lrclib.net/).
     - You can use command-line options to control lyric display (see "Command Line Options" section).
     ```
     [INFO] Synced lyrics found for: Artist - Title
     [INFO] Plain lyrics found for: Artist - Title
     [INFO] No lyrics found for: Artist - Title
     ```
     When lyrics are displayed, you can:
       - Use `UP`/`DOWN` arrow keys to scroll manually.
       - Press `a` to toggle between auto-scroll and manual scroll mode.
       - Press `s` to toggle scrobbling for the current session.
       - Press `q` to quit.
   - If you are playing video:
     - The music info extracted from the video, if possible
        ```
        [INFO] Using extracted music info: the Mountain Goats - Against Pollution (Jordan Lake Sessions)
        ```
     - Best effort to detect and skip non-music video contect
       ```
       [INFO] Searching for best match for: 养暹罗就跟养了条狗一样 - 养暹罗就跟养了条狗一样
       [INFO] Skipping non-music content
       ```
     - Mistakes are still happening all the time, please be aware when playing videos especially non-music ones.
     - Please refer to the section below.

### Running it in the background (Recommended)
1. Use HomeBrew services to start the scrobbler automatically on login:
```
brew services start scrobbler
```
2. In this way, scrobbler will be started automatically as a HomeBrew service after each reboot. There are no worries onwards.
3. Other commands:
```
# Stop the service
brew services stop scrobbler

# Restart the service
brew services restart scrobbler

# Check status
brew services info scrobbler
```
### Running it in the background (Daemon)
1. Run the program as a daemon process directly:
```
scrobbler --daemon
```
2. To stop:
```
pkill scrobbler
```

## Command Line Options
### Reference:
```
        std::cout << "Usage: Scrobbler [options]\n"
                  << "Options:\n"
                  << "  --daemon        Run as a daemon process\n"
                  << "  --no-lyrics     Disable lyrics display\n"
                  << "  --plain-lyrics  Prefer plain lyrics over synced lyrics\n"
                  << "  --quiet         Quiet mode, minimal console output\n"
                  << "  --debug         Show debug message in the console\n"
                  << "  --log=PATH      Specify custom log file path\n"
                  << "  --no-scrobble   Disable scrobbling entirely\n"
                  << "  --help          Show this help message\n";
```
### Examples:
```
# Run in background
scrobbler --daemon

# Disable lyrics display
scrobbler --no-lyrics

# Prefer plain lyrics
scrobbler --plain-lyrics

# Enable quiet mode
scrobbler --quiet

# Enable debug logging
scrobbler --debug

# Custom log file location
scrobbler --log=/Users/you/scrobbler.log

# Disable scrobbling
scrobbler --no-scrobble

# Show help
scrobbler --help
```

## Logs
- Default path: /var/log/scrobbler.log
- You can watch the log in real-time:
```
tail -f /var/log/scrobbler.log
```

## Wrong track info?
For audio, metadata are usually formatted properly and easy to retrieve. So it is unlikely to happen when audio is playing. 

For video, although BetterScrobbler tries parse and verify track information from various sources, the current parsing methods are still too naive to handle the clusterfucked naming traditions of music videos on YouTube, Bilibili, etc..

If you notice something is wrong, please make sure the video title is formatted as one of the followings:
1. Basic Formats:
```
Artist - Title
Artist: Title
```
2. Quoted Formats:
```
Artist - "Title"
Artist - 'Title'
```
3. Brackets Formats:
```
Artist「Title」
Artist『Title』
Artist [Title]
Artist (Title)
Artist <Title>
```
4. Formats above with Additional Info:
```
Artist - Title (2024)          # Year
Artist - Title [Official MV]   # Additional tags
Artist - Title @ Live          # Location/event
Artist - Title (Live at...)    # Live performance
```
**Notes:**
- The separator between artist and title can be various dashes: -, –, −, ﹣, －
- Spaces around the separator are optional
- The program will automatically clean up:
   - Platform suffixes (e.g., "- YouTube", "- bilibili")
   - Common tags (MV, Official Video, HD, etc.)
   - Date information
   - Extra metadata
