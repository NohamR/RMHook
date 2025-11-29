#!/bin/bash
# Script to compile the reMarkable dylib with different build modes

# Build modes:
#   rmfakecloud - Redirect reMarkable cloud to rmfakecloud server (default)
#   qmldiff     - Qt resource data registration hooking (WIP)
#   dev         - Development/reverse engineering mode with all hooks

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)

# Qt path detection (adjust according to your installation)
QT_PATH=${QT_PATH:-"$HOME/Qt/6.10.0"}

# Parse build mode argument
BUILD_MODE=${1:-rmfakecloud}

# Set CMake options based on build mode
CMAKE_OPTIONS=""
case "$BUILD_MODE" in
    rmfakecloud)
        CMAKE_OPTIONS="-DBUILD_MODE_RMFAKECLOUD=ON -DBUILD_MODE_QMLDIFF=OFF -DBUILD_MODE_DEV=OFF"
        ;;
    qmldiff)
        CMAKE_OPTIONS="-DBUILD_MODE_RMFAKECLOUD=OFF -DBUILD_MODE_QMLDIFF=ON -DBUILD_MODE_DEV=OFF"
        ;;
    dev)
        CMAKE_OPTIONS="-DBUILD_MODE_RMFAKECLOUD=OFF -DBUILD_MODE_QMLDIFF=OFF -DBUILD_MODE_DEV=ON"
        ;;
    all)
        CMAKE_OPTIONS="-DBUILD_MODE_RMFAKECLOUD=ON -DBUILD_MODE_QMLDIFF=ON -DBUILD_MODE_DEV=ON"
        ;;
    *)
        echo "❌ Unknown build mode: $BUILD_MODE"
        echo "Available modes: rmfakecloud (default), qmldiff, dev, all"
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
    echo ""
    echo "✅ Compilation successful!"
    echo "📍 Dylib: $PROJECT_DIR/build/dylibs/reMarkable.dylib"
    echo ""
    echo "🚀 To inject into the reMarkable application:"
    echo "   DYLD_INSERT_LIBRARIES=\"$PROJECT_DIR/build/dylibs/reMarkable.dylib\" /Applications/reMarkable.app/Contents/MacOS/reMarkable"
    echo ""
else
    echo "❌ Compilation failed"
    exit 1
fi