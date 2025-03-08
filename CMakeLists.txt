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
)

set(HEADERS
        src/MediaRemote.h
        src/LastFmScrobbler.h
        src/Helper.h
        src/Config.h
        src/Logger.h
        src/CommandLine.h
        src/Credentials.h
        src/UrlUtils.h
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
