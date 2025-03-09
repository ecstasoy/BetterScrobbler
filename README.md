# BetterScrobbler
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/8aa48c219e2543439039cb1f116c47cc)](https://app.codacy.com/gh/ecstasoy/BetterScrobbler/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)

A better Last.fm scrobbler for macOS, and it works globally!

## Introduction
Are you sick of the lack of reliable scrobblers on macOS?

Foobar2000's scrobble plugin was deprecated, Apple Music does not support built-in scrobbling, and there is absolutely no way to scrobble on Netease Music's desktop application.

All the workarounds may not be worth the hassle now. BetterScrobbler is a CLI scrobbler that scrobbles ANY music playing on you Mac. And yes, it even works for your browser! (not always)

## Preparation (easy)
It is **important** to do this before everything!
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
