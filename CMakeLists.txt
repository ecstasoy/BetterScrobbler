cmake_minimum_required(VERSION 3.16)
project(Scrobbler
        VERSION 1.0
        LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)

set(SOURCES
        src/main.mm
        src/MediaRemote.mm
        src/LastFmScrobbler.mm
        src/Helper.mm
        src/UrlUtils.mm
        src/Credentials.mm
)

set(HEADERS
        header/MediaRemote.h
        header/LastFmScrobbler.h
        header/Helper.h
        header/Config.h
        header/Logger.h
        header/CommandLine.h
        header/Credentials.h
        header/UrlUtils.h
)

find_package(CURL REQUIRED)

add_executable(Scrobbler ${SOURCES} ${HEADERS})

target_link_libraries(Scrobbler
        CURL::libcurl
        "-framework Foundation"
        "-framework CoreFoundation"
        "-F/System/Library/PrivateFrameworks"
        "-framework Security"
        "-framework MediaRemote"
        "-framework AppKit"
)

target_include_directories(Scrobbler
        PRIVATE
        "${CMAKE_SOURCE_DIR}"
)
