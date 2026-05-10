#!/usr/bin/env bash
REPO="NohamR/RMHook"
FILE="rmfakecloud.dylib"
APP_PATH="/Applications/remarkable.app"

curl -L \
  -o "/tmp/$FILE" \
  "https://github.com/$REPO/releases/latest/download/$FILE"

# Fix the sandbox
ln -s ~/Library/Containers/com.remarkable.desktop/Data/Library/Application\ Support/remarkable \
      ~/Library/Application\ Support/remarkable

curl -L \
  -o "/tmp/inject.sh" \
  "https://raw.githubusercontent.com/$REPO/refs/heads/main/scripts/inject.sh"

curl -L \
  -o "/tmp/optool" \
  "https://raw.githubusercontent.com/$REPO/refs/heads/main/scripts/optool"

chmod +x /tmp/inject.sh
/tmp/inject.sh "/tmp/$FILE" "$APP_PATH"