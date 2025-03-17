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
        src/TrackManager.mm
        src/LyricsManager.mm
        src/Config.mm
)

set(HEADERS
        include/MediaRemote.h
        include/LastFmScrobbler.h
        include/Helper.h
        include/Config.h
        include/Logger.h
        include/CommandLine.h
        include/Credentials.h
        include/UrlUtils.h
        include/TrackManager.h
        include/LyricsManager.h
)

find_package(CURL REQUIRED)

find_package(Curses REQUIRED)

if(CURSES_HAVE_NCURSESW_H)
    include_directories(${CURSES_INCLUDE_DIR})
    add_definitions(-DHAVE_NCURSESW_H)
else()
    message(WARNING "ncursesw not found, Unicode support may be limited")
endif()

add_executable(Scrobbler ${SOURCES} ${HEADERS})

target_link_libraries(Scrobbler
        ${CURSES_LIBRARIES}
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
