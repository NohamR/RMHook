cmake_minimum_required(VERSION 3.15)
project(RMHook)

enable_language(OBJC OBJCXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# Build mode options
# - rmfakecloud: Redirect reMarkable cloud to rmfakecloud server (default)
# - qmldiff: Qt resource data registration hooking (WIP)
# - dev: Development/reverse engineering mode with all hooks
option(BUILD_MODE_RMFAKECLOUD "Build with rmfakecloud support" ON)
option(BUILD_MODE_QMLDIFF "Build with QML diff/resource hooking" OFF)
option(BUILD_MODE_DEV "Build with dev/reverse engineering hooks" OFF)

# Compiler settings for macOS
set(CMAKE_MACOSX_RPATH 1)
set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15" CACHE STRING "Minimum OS X deployment version")

# Architecture: x86_64 only for reMarkable
set(CMAKE_OSX_ARCHITECTURES "x86_64")

# Project root directory
set(PROJECT_ROOT_DIR ${CMAKE_CURRENT_SOURCE_DIR})

# Include directories
include_directories(
    ${PROJECT_ROOT_DIR}/src/core
    ${PROJECT_ROOT_DIR}/src/utils
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
    ${PROJECT_ROOT_DIR}/libs/libtinyhook.a
    z  # zlib for compression/decompression
)

# Locate Qt libraries
set(QT_LIB_TARGETS "")
set(_qt_candidate_roots "$ENV{HOME}/Qt/6.10.0")

foreach(_qt_root ${_qt_candidate_roots})
    if(_qt_root AND EXISTS "${_qt_root}")
        list(APPEND CMAKE_PREFIX_PATH "${_qt_root}")
    endif()
endforeach()

find_package(Qt6 COMPONENTS Core Network WebSockets QUIET)
if(Qt6_FOUND)
    set(QT_LIB_TARGETS Qt6::Core Qt6::Network Qt6::WebSockets)
else()
    find_package(Qt5 COMPONENTS Core Network WebSockets QUIET)
    if(Qt5_FOUND)
        set(QT_LIB_TARGETS Qt5::Core Qt5::Network Qt5::WebSockets)
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

# reMarkable dylib
set(REMARKABLE_SOURCES
    ${PROJECT_ROOT_DIR}/src/reMarkable/reMarkable.m
)

add_library(reMarkable SHARED 
    ${COMMON_SOURCES}
    ${REMARKABLE_SOURCES}
)

# Set source files as Objective-C++
set_source_files_properties(
    ${REMARKABLE_SOURCES}
    PROPERTIES LANGUAGE OBJCXX
)

set_target_properties(reMarkable PROPERTIES
    PREFIX ""
    SUFFIX ".dylib"
    OUTPUT_NAME "reMarkable"
    LIBRARY_OUTPUT_DIRECTORY "${PROJECT_ROOT_DIR}/build/dylibs"
    MACOSX_RPATH ON
)

add_definitions(-DQT_NO_VERSION_TAGGING)

# Add build mode compile definitions
if(BUILD_MODE_RMFAKECLOUD)
    target_compile_definitions(reMarkable PRIVATE BUILD_MODE_RMFAKECLOUD=1)
    message(STATUS "Build mode: rmfakecloud (cloud redirection)")
endif()

if(BUILD_MODE_QMLDIFF)
    target_compile_definitions(reMarkable PRIVATE BUILD_MODE_QMLDIFF=1)
    message(STATUS "Build mode: qmldiff (resource hooking)")
endif()

if(BUILD_MODE_DEV)
    target_compile_definitions(reMarkable PRIVATE BUILD_MODE_DEV=1)
    message(STATUS "Build mode: dev (reverse engineering)")
endif()

target_link_libraries(reMarkable PRIVATE 
    ${LIBS}
    ${QT_LIB_TARGETS}
    ${PROJECT_ROOT_DIR}/libs/libzstd.1.dylib
)