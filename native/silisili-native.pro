TEMPLATE = app
TARGET = silisili-native

CONFIG += c++11
VERSION = 1.1.0
isEmpty(SILISILI_NATIVE_PACKAGE_RELEASE): SILISILI_NATIVE_PACKAGE_RELEASE = development
DEFINES += SILISILI_NATIVE_APP_VERSION=\\\"$$VERSION\\\"
DEFINES += SILISILI_NATIVE_PACKAGE_RELEASE=\\\"$$SILISILI_NATIVE_PACKAGE_RELEASE\\\"
DEFINES += SILISILI_NATIVE_PACKAGE_NAME=\\\"silisili-native-devel\\\"
DEFINES += SILISILI_NATIVE_HAVE_DROIDMEDIA=1
QT += core dbus gui qml quick network
INCLUDEPATH += /usr/include/sailfishapp /usr/include/mdeclarativecache5
LIBS += -lsailfishapp -lmdeclarativecache5 -lmpv -lEGL -lGLESv2
QMAKE_CXXFLAGS += $$system(pkg-config --cflags droidmedia)
LIBS += $$system(pkg-config --libs droidmedia)
QMAKE_CXXFLAGS += $$system(pkg-config --cflags libavformat libavcodec libavutil)
LIBS += $$system(pkg-config --libs libavformat libavcodec libavutil)
# Privileged mapplauncherd sessions load the application through the Silica
# booster. The resulting executable must be ET_DYN/PIE so dlopen() succeeds.
QMAKE_CFLAGS += -fPIE
QMAKE_CXXFLAGS += -fPIE
QMAKE_LFLAGS += -pie
!isEmpty(SILISILI_MPV_PREFIX) {
    INCLUDEPATH += $$SILISILI_MPV_PREFIX/include
    LIBS += -L$$SILISILI_MPV_PREFIX/lib
}

SOURCES += \
    src/main.cpp \
    src/appsettings.cpp \
    src/bilibiliimagenetwork.cpp \
    src/networkutils.cpp \
    src/homefeedmodel.cpp \
    src/searchmodel.cpp \
    src/videodetailmodel.cpp \
    src/accountservice.cpp \
    src/accountlibrarymodel.cpp \
    src/regionfeedmodel.cpp \
    src/dynamicfeedmodel.cpp \
    src/inboxmodel.cpp \
    src/commentmodel.cpp \
    src/relatedmodel.cpp \
    src/playbackresolver.cpp \
    src/mpvvideoitem.cpp \
    src/droidvideodecoder.cpp \
    src/playbacksession.cpp \
    src/displayframemonitor.cpp \
    src/systempipcontroller.cpp \
    src/danmakumodel.cpp \
    src/livefeedmodel.cpp \
    src/liveresolver.cpp \
    src/pgcfeedmodel.cpp \
    src/pgcdetailmodel.cpp \
    src/authorspacemodel.cpp \
    src/configmigration.cpp

HEADERS += \
    src/appsettings.h \
    src/bilibiliimagenetwork.h \
    src/networkutils.h \
    src/homefeedmodel.h \
    src/searchmodel.h \
    src/videodetailmodel.h \
    src/accountservice.h \
    src/accountlibrarymodel.h \
    src/regionfeedmodel.h \
    src/dynamicfeedmodel.h \
    src/inboxmodel.h \
    src/commentmodel.h \
    src/relatedmodel.h \
    src/playbackresolver.h \
    src/mpvvideoitem.h \
    src/droidvideodecoder.h \
    src/playbacksession.h \
    src/displayframemonitor.h \
    src/systempipcontroller.h \
    src/danmakumodel.h \
    src/livefeedmodel.h \
    src/liveresolver.h \
    src/pgcfeedmodel.h \
    src/pgcdetailmodel.h \
    src/authorspacemodel.h \
    src/configmigration.h

RESOURCES += qml/qml.qrc
