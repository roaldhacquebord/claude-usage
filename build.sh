#!/bin/bash
# Builds "Claude Usage.app" into build/. With `install`, also copies it to /Applications and relaunches it.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP="build/Claude Usage.app"

swift build -c release --product ClaudeUsage
BIN="$(swift build -c release --show-bin-path)/ClaudeUsage"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsage"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x ClaudeUsage || true
    rm -rf "/Applications/Claude Usage.app"
    cp -R "$APP" /Applications/
    open "/Applications/Claude Usage.app"
    echo "Installed to /Applications and launched"
fi
