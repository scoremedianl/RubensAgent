#!/bin/zsh
# Wrapper so launchd gets the same PATH as an interactive login shell:
# this is how the daemon finds nvm's `node` and, crucially, the `claude` CLI
# it spawns for each session.
source "$HOME/.zprofile" 2>/dev/null
cd "$(dirname "$0")/.." || exit 1
exec node src/server.mjs
