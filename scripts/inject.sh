#!/bin/bash

set -e

# Function to display usage instructions
usage() {
    echo "Usage: $0 <dylib> <app_path>"
    echo "  dylib      - The dynamic library to inject."
    echo "  app_path   - The path to the .app bundle."
    exit 1
}

# Ensure required arguments are provided
if [ "$#" -ne 2 ]; then
    echo "[ERROR] Incorrect number of arguments."
    usage
fi

DYLIB=$1
APP_PATH=$2

# Validate inputs
if [ ! -f "$DYLIB" ]; then
    echo "[ERROR] The specified dynamic library ($DYLIB) does not exist."
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "[ERROR] The specified app path ($APP_PATH) does not exist."
    exit 1
fi

INFO_PLIST_PATH="$APP_PATH/Contents/Info.plist"
if [ ! -f "$INFO_PLIST_PATH" ]; then
    echo "[ERROR] Info.plist not found at $INFO_PLIST_PATH"
    exit 1
fi

# Get the executable name from Info.plist
APP_NAME=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$INFO_PLIST_PATH")
if [ -z "$APP_NAME" ]; then
    echo "[ERROR] Could not read CFBundleExecutable from $INFO_PLIST_PATH"
    exit 1
fi

echo "[INFO] Executable name: $APP_NAME"

# Change ownership to current user
CURRENT_USER=$(whoami)
CURRENT_GROUP=$(id -gn)
echo "Changing ownership to $CURRENT_USER:$CURRENT_GROUP for $APP_PATH ..."
sudo chown -R "$CURRENT_USER:$CURRENT_GROUP" "$APP_PATH"

EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$APP_NAME"
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "[ERROR] The specified executable ($EXECUTABLE_PATH) does not exist."
    exit 1
fi

mkdir -p "$APP_PATH/Contents/Resources/"

# Copy the dylib to the Resources folder
cp "$DYLIB" "$APP_PATH/Contents/Resources/"
echo "[INFO] Copied $DYLIB to $APP_PATH/Contents/Resources/"

# Use optool from the scripts folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy libzstd dependency and fix the reference in reMarkable.dylib
LIBZSTD_PATH="$SCRIPT_DIR/../libs/libzstd.1.dylib"
if [ -f "$LIBZSTD_PATH" ]; then
    cp "$LIBZSTD_PATH" "$APP_PATH/Contents/Resources/"
    echo "[INFO] Copied libzstd.1.dylib to $APP_PATH/Contents/Resources/"
    
    # Update the dylib reference to @executable_path/../Resources (handle multiple possible source paths)
    DYLIB_IN_APP="$APP_PATH/Contents/Resources/$(basename "$DYLIB")"
    install_name_tool -change "/usr/local/lib/libzstd.1.dylib" "@executable_path/../Resources/libzstd.1.dylib" "$DYLIB_IN_APP"
    install_name_tool -change "/usr/local/opt/zstd/lib/libzstd.1.dylib" "@executable_path/../Resources/libzstd.1.dylib" "$DYLIB_IN_APP"
    install_name_tool -change "/opt/homebrew/lib/libzstd.1.dylib" "@executable_path/../Resources/libzstd.1.dylib" "$DYLIB_IN_APP"
    install_name_tool -change "/opt/homebrew/opt/zstd/lib/libzstd.1.dylib" "@executable_path/../Resources/libzstd.1.dylib" "$DYLIB_IN_APP"
    echo "[INFO] Updated libzstd references in $(basename "$DYLIB")"
else
    echo "[WARNING] libzstd.1.dylib not found at $LIBZSTD_PATH - app may fail on systems without zstd"
fi

"$SCRIPT_DIR/optool" install -c load -p "@executable_path/../Resources/$(basename "$DYLIB")" -t "$EXECUTABLE_PATH"
echo "[INFO] Injected $DYLIB into $EXECUTABLE_PATH"

sudo codesign --remove-signature "$EXECUTABLE_PATH"
sudo xattr -cr "$EXECUTABLE_PATH"
sudo codesign -f -s - --timestamp=none --all-architectures "$EXECUTABLE_PATH"
sudo xattr -cr "$EXECUTABLE_PATH"

echo "Signed successfully."

# Remove _MASReceipt if it exists
RECEIPT_PATH="$APP_PATH/Contents/_MASReceipt"
if [ -d "$RECEIPT_PATH" ]; then
  echo "Removing _MASReceipt..."
  rm -r "$RECEIPT_PATH"
else
  echo "No _MASReceipt directory found."
fi

exit 0