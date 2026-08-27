cmake_minimum_required(VERSION 3.15)
project(RMHook)

enable_language(OBJC OBJCXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# Build mode options
# - rmfakecloud: Redirect reMarkable cloud to rmfakecloud server (default)
# - qmlrebuild: Qt resource data registration hooking
# - dev: Development/reverse engineering mode with all hooks
option(BUILD_MODE_RMFAKECLOUD "Build with rmfakecloud support" ON)
option(BUILD_MODE_QMLREBUILD "Build with QML resource rebuilding" OFF)
option(BUILD_MODE_DEV "Build with dev/reverse engineering hooks" OFF)

# Compiler settings for macOS
set(CMAKE_MACOSX_RPATH 1)
set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15" CACHE STRING "Minimum OS X deployment version")

# Architecture: x86_64 only for reMarkable
set(CMAKE_OSX_ARCHITECTURES "x86_64" "arm64")

# Project root directory
set(PROJECT_ROOT_DIR ${CMAKE_CURRENT_SOURCE_DIR})

# Include directories
include_directories(
    ${PROJECT_ROOT_DIR}/src/core
    ${PROJECT_ROOT_DIR}/src/utils
    ${PROJECT_ROOT_DIR}/src/RMHook
    ${PROJECT_ROOT_DIR}/libs/include
)

# Find required libraries
find_library(FOUNDATION_LIBRARY Foundation REQUIRED)
find_library(COCOA_LIBRARY Cocoa REQUIRED)
find_library(SECURITY_LIBRARY Security REQUIRED)

# Common libraries
set(LIBS
    ${FOUNDATION_LIBRARY}
    ${COCOA_LIBRARY}
    ${SECURITY_LIBRARY}
    ${PROJECT_ROOT_DIR}/libs/tinyhook.a # tinyhook for function hooking
    ${PROJECT_ROOT_DIR}/libs/libzstd.a  # libzstd for compression/decompression
    z  # zlib for compression/decompression
)

# Locate Qt libraries
set(QT_LIB_TARGETS "")
set(_qt_candidate_roots "$ENV{HOME}/Qt/6.10.3/macos")

foreach(_qt_root ${_qt_candidate_roots})
    if(_qt_root AND EXISTS "${_qt_root}")
        list(APPEND CMAKE_PREFIX_PATH "${_qt_root}")
    endif()
endforeach()

find_package(Qt6 COMPONENTS Core Network WebSockets Qml QUIET)
if(Qt6_FOUND)
    set(QT_LIB_TARGETS Qt6::Core Qt6::Network Qt6::WebSockets Qt6::Qml)
else()
    find_package(Qt5 COMPONENTS Core Network WebSockets Qml QUIET)
    if(Qt5_FOUND)
        set(QT_LIB_TARGETS Qt5::Core Qt5::Network Qt5::WebSockets Qt5::Qml)
    endif()
endif()

if(NOT QT_LIB_TARGETS)
    message(FATAL_ERROR "Qt Core, Network and WebSockets not found. Set CMAKE_PREFIX_PATH to your Qt installation.")
endif()

# Common sources
set(COMMON_SOURCES
    ${PROJECT_ROOT_DIR}/src/utils/MemoryUtils.m
    ${PROJECT_ROOT_DIR}/src/utils/Constant.m
    ${PROJECT_ROOT_DIR}/src/utils/ResourceUtils.m
)

# RMHook dylib
set(RMHOOK_SOURCES
    ${PROJECT_ROOT_DIR}/src/RMHook/RMHook.m
    ${PROJECT_ROOT_DIR}/src/RMHook/Config.m
    ${PROJECT_ROOT_DIR}/src/RMHook/SSLConfig.m
    ${PROJECT_ROOT_DIR}/src/RMHook/DevHooks.m
)

add_library(RMHook SHARED 
    ${COMMON_SOURCES}
    ${RMHOOK_SOURCES}
)

# Set source files as Objective-C++
set_source_files_properties(
    ${RMHOOK_SOURCES}
    PROPERTIES LANGUAGE OBJCXX
)

set_target_properties(RMHook PROPERTIES
    PREFIX ""
    SUFFIX ".dylib"
    OUTPUT_NAME "RMHook"
    LIBRARY_OUTPUT_DIRECTORY "${PROJECT_ROOT_DIR}/build/dylibs"
    MACOSX_RPATH ON
)

add_definitions(-DQT_NO_VERSION_TAGGING)

# Add build mode compile definitions and conditionally add sources
if(BUILD_MODE_RMFAKECLOUD)
    target_compile_definitions(RMHook PRIVATE BUILD_MODE_RMFAKECLOUD=1)
    message(STATUS "Build mode: rmfakecloud (cloud redirection)")
endif()

if(BUILD_MODE_QMLREBUILD)
    target_compile_definitions(RMHook PRIVATE BUILD_MODE_QMLREBUILD=1)
    
    # Enable Qt MOC for MessageBroker
    set_target_properties(RMHook PROPERTIES AUTOMOC ON)
    
    # Add MessageBroker source (needs MOC processing)
    target_sources(RMHook PRIVATE 
        ${PROJECT_ROOT_DIR}/src/utils/MessageBroker.mm
    )
    message(STATUS "Build mode: qmlrebuild (resource hooking)")
endif()

if(BUILD_MODE_DEV)
    target_compile_definitions(RMHook PRIVATE BUILD_MODE_DEV=1)
    message(STATUS "Build mode: dev (reverse engineering)")
endif()

target_link_libraries(RMHook PRIVATE 
    ${LIBS}
    ${QT_LIB_TARGETS}
)