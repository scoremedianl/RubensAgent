#!/bin/zsh
# Wrapper so launchd gets the same PATH as an interactive login shell:
# this is how the daemon finds nvm's `node` and, crucially, the `claude` CLI
# it spawns for each session.
source "$HOME/.zprofile" 2>/dev/null
# Long-lived Claude auth (from `claude setup-token`) + any daemon overrides,
# kept out of the repo. Makes the daemon work headless, independent of the
# GUI login keychain.
[ -f "$HOME/.claude-bridge/env" ] && source "$HOME/.claude-bridge/env"
# Force the subscription login (OAuth token / keychain), never API-key billing.
unset ANTHROPIC_API_KEY
cd "$(dirname "$0")/.." || exit 1
exec node src/server.mjs
