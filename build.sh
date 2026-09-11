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
    # Wait for the old instance to actually exit before relaunching, otherwise
    # LaunchServices can refuse to open the new copy (-600) while it's still exiting.
    for _ in $(seq 1 50); do
        pgrep -x ClaudeUsage >/dev/null || break
        sleep 0.1
    done
    if pgrep -x ClaudeUsage >/dev/null; then
        echo "Warning: old instance still running; install may fail" >&2
    fi
    rm -rf "/Applications/Claude Usage.app"
    cp -R "$APP" /Applications/
    open "/Applications/Claude Usage.app"
    echo "Installed to /Applications and launched"
fi
