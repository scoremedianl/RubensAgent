#!/bin/zsh
# Installs the bridge as an always-on launchd user agent on this Mac.
# Run ON the mini: zsh deploy/install.sh
set -e
source "$HOME/.zprofile" 2>/dev/null

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="nl.score.claude-bridge"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "[install] app dir: $APP_DIR"
echo "[install] installing npm deps…"
( cd "$APP_DIR" && npm install --omit=dev --no-audit --no-fund )

mkdir -p "$HOME/.claude-bridge" "$HOME/Library/LaunchAgents"

echo "[install] writing launch agent → $PLIST_DEST"
sed -e "s|__APP_DIR__|$APP_DIR|g" -e "s|__HOME__|$HOME|g" \
  "$APP_DIR/deploy/nl.score.claude-bridge.plist" > "$PLIST_DEST"

# Reload cleanly.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

sleep 1
echo "[install] token:"
cat "$HOME/.claude-bridge/token" 2>/dev/null && echo
echo "[install] done. Health: curl http://localhost:$(grep -o 'port || [0-9]*' "$APP_DIR/src/config.mjs" | grep -o '[0-9]*')/health"
