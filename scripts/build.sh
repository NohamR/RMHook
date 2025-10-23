#!/bin/bash
# Script to compile the reMarkable dylib

# By default, compile reMarkable
APP_NAME=${1:-reMarkable}
PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)

# Qt path detection (adjust according to your installation)
QT_PATH=${QT_PATH:-"$HOME/Qt/6.10.0"}

echo "🔨 Compiling $APP_NAME.dylib..."
echo "📦 Qt path: $QT_PATH"

# Create build directories if necessary
mkdir -p "$PROJECT_DIR/build"
cd "$PROJECT_DIR/build"

# Configure with CMake and compile
if [ -d "$QT_PATH" ]; then
    cmake -DCMAKE_PREFIX_PATH="$QT_PATH" ..
else
    echo "⚠️  Qt not found at $QT_PATH, trying without specifying path..."
    cmake ..
fi

make $APP_NAME

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Compilation successful!"
    echo "📍 Dylib: $PROJECT_DIR/build/dylibs/$APP_NAME.dylib"
    echo ""
    echo "🚀 To inject into the reMarkable application:"
    echo "   DYLD_INSERT_LIBRARIES=\"$PROJECT_DIR/build/dylibs/$APP_NAME.dylib\" /Applications/reMarkable.app/Contents/MacOS/reMarkable"
    echo ""
else
    echo "❌ Compilation failed"
    exit 1
fi