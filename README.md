# RubensAgent — Claude mini bridge

A native **SwiftUI app (iOS + macOS)** that drives coding-agent sessions —
**Claude Code**, **OpenCode** or **Codex** — on an always-on Mac (a Mac mini),
plus the **bridge daemon** it talks to. Start, manage and continue sessions from
your phone or laptop; the real work runs on the Mac and survives the app
closing.

## How it works

```
 iPhone / Mac app  ──HTTP + WebSocket over Tailscale──▶  bridge daemon (Node)  ──▶  claude | opencode | codex
   (SwiftUI)                                              launchd, port 8787          (in tmux) + git + files
```

- **Sessions are live tmux terminal-mirrors.** The daemon launches the agent's
  interactive TUI inside a tmux session; the app mirrors the pane
  (`capture-pane`) and types via `send-keys`. Re-entering always shows the true
  current state and sessions survive app close **and** daemon restart.
- **Any agent, same mechanism.** Claude Code, OpenCode and Codex are all
  full-screen TUIs, so they are driven identically; `src/agents.mjs` holds only
  what differs (launch flags, busy pattern, login check). The app greys out an
  agent that isn't installed or signed in on the Mac and tells you the command
  to fix it.
- **Thin client, everything on the Mac.** The app is a window; the filesystem,
  git, MCP servers and Claude auth all live on the Mac.

## Repo layout

| Path | What |
|------|------|
| `src/` | The bridge daemon (Node, ESM). `server.mjs` wires HTTP + WebSocket; modules for term/tmux, git, files, memory, usage, system, repos. |
| `app/` | The SwiftUI multiplatform app. Generated with **XcodeGen** from `app/project.yml`. `app/icon-gen.swift` renders the app icon. |
| `deploy/` | `run.sh` (launchd wrapper), `install.sh`, and the launchd plist. |

## Deploy the daemon (on the Mac mini)

```bash
# from this repo on your laptop, sync to the mini and install
rsync -az --exclude node_modules --exclude .git --exclude app ./ scoremini:Projects/claude-mini-bridge/
ssh scoremini 'zsh Projects/claude-mini-bridge/deploy/install.sh'
```

`install.sh` runs `npm install`, writes the launchd agent `nl.score.claude-bridge`
(always-on, restarts on crash/reboot, listens on `0.0.0.0:8787`) and prints the
auth token. Logs live in `~/.claude-bridge/`.

- **Auth**: uses the Mac's Claude subscription login (Keychain). For rock-solid
  headless auth, run `claude setup-token` and put `CLAUDE_CODE_OAUTH_TOKEN=…` in
  `~/.claude-bridge/env`. `run.sh` `unset`s `ANTHROPIC_API_KEY` so it always uses
  the subscription, never API billing.
- **Token**: `~/.claude-bridge/token` (the app sends it as a Bearer credential).
  Not committed.
- **Reachability**: over Tailscale (e.g. `100.x.x.x:8787`).
- **Temperature** (optional): the system widget shows real CPU temp if `smctemp`
  is installed on the mini — `git clone https://github.com/narugit/smctemp && cd
  smctemp && make && sudo make install`.

## Build the app (on a Mac with Xcode)

```bash
cd app
xcodegen generate        # regenerate the Xcode project from project.yml
open ClaudeConsole.xcodeproj
```

- **Mac**: pick *My Mac* → Run (⌘R).
- **iPhone**: pick your device, set your signing Team under *Signing &
  Capabilities*, Run. Grant Local Network (and mic/speech for voice) on first launch.
- Connection (host `100.121.84.34`, port `8787`, token) is set in the app's
  settings; both devices need Tailscale on.

## Features

- Live tmux terminal-mirror sessions; multiple at once; a sidebar overview with a
  working-spinner while the agent is busy, and a badge showing which agent it is.
- **Agent picker** — Claude Code, OpenCode or Codex per session, always full-auto.
- **Model picker** — Claude's presets (Opus 5, Opus 4.8, Sonnet 5, Haiku 4.5,
  Fable 5); OpenCode reports its own list, searchable and grouped by provider;
  Codex switches model in its TUI. Each model is tinted by family.
- **Search everywhere** — projects and running sessions from the sidebar, your
  GitHub repos while typing, branches in the branch picker, and models in the
  model picker (OpenCode with OpenRouter reports 300+, grouped by provider).
- **Paste anything** — a log or stack trace becomes a compact chip in the
  composer instead of flooding it, and goes to the agent as a single bracketed
  paste (tested at 88k characters / 1500 lines).
- **Scroll the terminal** — swipe on iPhone or use the wheel/trackpad on the
  Mac to page back through an agent's long output, with a "Jump to live" button.
- **Usage & limits** — real Claude Code `/usage` (session + weekly).
- **System widget** — live CPU / RAM / temperature rings.
- **Git** — browse & clone any repo you can access, searchable branch picker with
  switch/force-switch, pull.
- **File explorer** per project — browse, open (text + images), upload files, search.
- **Non-git folders** for things not in git.
- **Attachments / photos** and **Dutch voice dictation** in the chat field.
- Shared **memory** MD files loaded into every session; **loops** (cron + auto-continue)
  and **persistent runs** backed by tmux.

## Adding another agent

One entry in `src/agents.mjs` (binary, full-auto flag, resume flag, model flag,
busy pattern, login check) and one case in the app's `AgentKind`. Nothing else
knows which agent a session runs.

## Notes

Built for the Score Agency Mac mini. The daemon confines file operations to
`~/Projects`; the app icon uses Score Agency's colours (`#FF6B35` on `#000511`).
