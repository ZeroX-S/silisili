cmake_minimum_required(VERSION 3.13)
project(silisili-native VERSION 1.1.0 LANGUAGES CXX)

set(SILISILI_NATIVE_PACKAGE_RELEASE "development" CACHE STRING
    "RPM package release shown by the application")

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt5 5.6 REQUIRED COMPONENTS Core DBus Gui Network Qml Quick)
find_package(PkgConfig REQUIRED)
pkg_check_modules(SAILFISHAPP REQUIRED sailfishapp)
pkg_check_modules(DROIDMEDIA REQUIRED droidmedia)
pkg_check_modules(FFMPEG REQUIRED libavformat libavcodec libavutil)
find_path(MPV_INCLUDE_DIR mpv/client.h)
find_library(MPV_LIBRARY mpv)
find_library(GLESV2_LIBRARY GLESv2)
find_library(EGL_LIBRARY EGL)
if(NOT MPV_INCLUDE_DIR OR NOT MPV_LIBRARY OR NOT GLESV2_LIBRARY OR NOT EGL_LIBRARY)
    message(FATAL_ERROR "libmpv headers plus EGL/GLESv2 are required")
endif()

add_executable(silisili-native
    src/main.cpp
    src/appsettings.cpp
    src/appsettings.h
    src/bilibiliimagenetwork.cpp
    src/bilibiliimagenetwork.h
    src/networkutils.cpp
    src/networkutils.h
    src/homefeedmodel.cpp
    src/homefeedmodel.h
    src/searchmodel.cpp
    src/searchmodel.h
    src/videodetailmodel.cpp
    src/videodetailmodel.h
    src/accountservice.cpp
    src/accountservice.h
    src/accountlibrarymodel.cpp
    src/accountlibrarymodel.h
    src/regionfeedmodel.cpp
    src/regionfeedmodel.h
    src/dynamicfeedmodel.cpp
    src/dynamicfeedmodel.h
    src/inboxmodel.cpp
    src/inboxmodel.h
    src/commentmodel.cpp
    src/commentmodel.h
    src/relatedmodel.cpp
    src/relatedmodel.h
    src/playbackresolver.cpp
    src/playbackresolver.h
    src/mpvvideoitem.cpp
    src/mpvvideoitem.h
    src/droidvideodecoder.cpp
    src/droidvideodecoder.h
    src/playbacksession.cpp
    src/playbacksession.h
    src/displayframemonitor.cpp
    src/displayframemonitor.h
    src/systempipcontroller.cpp
    src/systempipcontroller.h
    src/danmakumodel.cpp
    src/danmakumodel.h
    src/livefeedmodel.cpp
    src/livefeedmodel.h
    src/liveresolver.cpp
    src/liveresolver.h
    src/pgcfeedmodel.cpp
    src/pgcfeedmodel.h
    src/pgcdetailmodel.cpp
    src/pgcdetailmodel.h
    src/authorspacemodel.cpp
    src/authorspacemodel.h
    src/configmigration.cpp
    src/configmigration.h
    qml/qml.qrc
)
set_target_properties(silisili-native PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    LINK_FLAGS "-pie"
)
target_include_directories(silisili-native PRIVATE
    ${SAILFISHAPP_INCLUDE_DIRS}
    ${DROIDMEDIA_INCLUDE_DIRS}
    ${FFMPEG_INCLUDE_DIRS}
    ${MPV_INCLUDE_DIR}
    ${Qt5Gui_PRIVATE_INCLUDE_DIRS}
)
target_compile_options(silisili-native PRIVATE
    ${SAILFISHAPP_CFLAGS_OTHER}
    ${DROIDMEDIA_CFLAGS_OTHER}
    ${FFMPEG_CFLAGS_OTHER}
)
target_compile_definitions(silisili-native PRIVATE
    SILISILI_NATIVE_APP_VERSION="${PROJECT_VERSION}"
    SILISILI_NATIVE_PACKAGE_RELEASE="${SILISILI_NATIVE_PACKAGE_RELEASE}"
    SILISILI_NATIVE_PACKAGE_NAME="silisili-native-devel"
    SILISILI_NATIVE_HAVE_DROIDMEDIA=1
)
target_link_directories(silisili-native PRIVATE
    ${SAILFISHAPP_LIBRARY_DIRS}
    ${DROIDMEDIA_LIBRARY_DIRS}
    ${FFMPEG_LIBRARY_DIRS}
)
target_link_libraries(silisili-native PRIVATE
    Qt5::Core Qt5::DBus Qt5::Gui Qt5::Network Qt5::Qml Qt5::Quick
    ${SAILFISHAPP_LIBRARIES}
    ${DROIDMEDIA_LIBRARIES}
    ${FFMPEG_LIBRARIES}
    ${MPV_LIBRARY}
    ${GLESV2_LIBRARY} ${EGL_LIBRARY}
)
install(TARGETS silisili-native RUNTIME DESTINATION bin)
