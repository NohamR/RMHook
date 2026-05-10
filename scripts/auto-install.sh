#!/usr/bin/env bash
REPO="NohamR/RMHook"
FILE="rmfakecloud.dylib"
APP_PATH="/Applications/remarkable.app"

echo "[INFO] Downloading $FILE..."
curl -sL \
  -o "/tmp/$FILE" \
  "https://github.com/$REPO/releases/latest/download/$FILE"

# Fix the sandbox
echo "[INFO] Linking sandbox directory..."
ln -sf ~/Library/Containers/com.remarkable.desktop/Data/Library/Application\ Support/remarkable \
      ~/Library/Application\ Support/remarkable

echo "[INFO] Downloading inject script..."
curl -sL \
  -o "/tmp/inject.sh" \
  "https://raw.githubusercontent.com/$REPO/refs/heads/main/scripts/inject.sh"

echo "[INFO] Downloading optool..."
curl -sL \
  -o "/tmp/optool" \
  "https://raw.githubusercontent.com/$REPO/refs/heads/main/scripts/optool"

chmod +x /tmp/inject.sh /tmp/optool
echo "[INFO] Running inject script..."
/tmp/inject.sh "/tmp/$FILE" "$APP_PATH"