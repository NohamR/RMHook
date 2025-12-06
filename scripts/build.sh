#!/bin/bash
# Script to compile the reMarkable dylib with different build modes

# Build modes:
#   rmfakecloud - Redirect reMarkable cloud to rmfakecloud server (default)
#   qmlrebuild     - Qt resource data registration hooking
#   dev         - Development/reverse engineering mode with all hooks

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)

# Qt path detection
QT_PATH=${QT_PATH:-$(ls -d "$HOME/Qt/6."* 2>/dev/null | sort -V | tail -n1)}

# Parse build mode argument
BUILD_MODE=${1:-rmfakecloud}

# Determine final dylib name for the selected build mode
case "$BUILD_MODE" in
    rmfakecloud)
        DYLIB_NAME="rmfakecloud.dylib"
        ;;
    qmlrebuild)
        DYLIB_NAME="qmlrebuild.dylib"
        ;;
    dev)
        DYLIB_NAME="dev.dylib"
        ;;
    all)
        DYLIB_NAME="all.dylib"
        ;;
    *)
        DYLIB_NAME="reMarkable.dylib"
        ;;
esac

# Set CMake options based on build mode
CMAKE_OPTIONS=""
case "$BUILD_MODE" in
    rmfakecloud)
        CMAKE_OPTIONS="-DBUILD_MODE_RMFAKECLOUD=ON -DBUILD_MODE_QMLREBUILD=OFF -DBUILD_MODE_DEV=OFF"
        ;;
    qmlrebuild)
        CMAKE_OPTIONS="-DBUILD_MODE_RMFAKECLOUD=OFF -DBUILD_MODE_QMLREBUILD=ON -DBUILD_MODE_DEV=OFF"
        ;;
    dev)
        CMAKE_OPTIONS="-DBUILD_MODE_RMFAKECLOUD=OFF -DBUILD_MODE_QMLREBUILD=OFF -DBUILD_MODE_DEV=ON"
        ;;
    all)
        CMAKE_OPTIONS="-DBUILD_MODE_RMFAKECLOUD=ON -DBUILD_MODE_QMLREBUILD=ON -DBUILD_MODE_DEV=ON"
        ;;
    *)
        echo "❌ Unknown build mode: $BUILD_MODE"
        echo "Available modes: rmfakecloud (default), qmlrebuild, dev, all"
        exit 1
        ;;
esac

echo "🔨 Compiling reMarkable.dylib (mode: $BUILD_MODE)..."
echo "📦 Qt path: $QT_PATH"

# Create build directories if necessary
mkdir -p "$PROJECT_DIR/build"
cd "$PROJECT_DIR/build"

# Configure with CMake and compile
if [ -d "$QT_PATH" ]; then
    cmake -DCMAKE_PREFIX_PATH="$QT_PATH" $CMAKE_OPTIONS ..
else
    echo "⚠️  Qt not found at $QT_PATH, trying without specifying path..."
    cmake $CMAKE_OPTIONS ..
fi

make reMarkable

if [ $? -eq 0 ]; then
    # Rename the produced dylib so each build mode has a distinct file name
    DYLIB_DIR="$PROJECT_DIR/build/dylibs"
    DEFAULT_DYLIB="$DYLIB_DIR/reMarkable.dylib"
    TARGET_DYLIB="$DYLIB_DIR/$DYLIB_NAME"

    if [ -f "$DEFAULT_DYLIB" ]; then
        mv "$DEFAULT_DYLIB" "$TARGET_DYLIB"
    else
        echo "⚠️  Expected dylib not found at $DEFAULT_DYLIB"
    fi

    echo ""
    echo "✅ Compilation successful!"
    echo "📍 Dylib: $TARGET_DYLIB"
    echo ""
    echo "🚀 To inject into the reMarkable application:"
    echo "   DYLD_INSERT_LIBRARIES=\"$TARGET_DYLIB\" /Applications/reMarkable.app/Contents/MacOS/reMarkable"
    echo ""
else
    echo "❌ Compilation failed"
    exit 1
fi