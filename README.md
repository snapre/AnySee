# AnySee

AnySee is a customizable macOS menu bar attention center for signals you actually want to watch. It is not a notification center, not a full dashboard, and not a feed. The first version is local-first: configuration, scripts, credentials, and state stay on the Mac by default.

Domain: `anysee.bar`

## MVP Scope

- Native macOS app built with Swift 6, Swift Package Manager, SwiftUI, AppKit, and `NSStatusItem`.
- Menu bar status icon reflects the overall attention state.
- Popover shows an Attention Feed grouped by priority and state.
- Local config directory:

```text
~/Library/Application Support/AnySee/
  anysee.toml
  sources/*.toml
  scripts/*
  schemas/signal.schema.json
  examples/*
  AGENTS.md
```

- Source types:
  - `manual`: static signal entries in TOML.
  - `http`: request a URL and produce a signal on status mismatch or JSON field condition.
  - `script`: run a local executable and parse stdout as Signal JSON.

Not included in the MVP: Gmail, Slack, GitHub integrations, OAuth, cloud sync, AnySee backend services, plugin marketplace, or built-in AI API calls.

## Build

```sh
swift build
swift test
```

Run the menu bar app from source:

```sh
swift run AnySee
```

Run the CLI:

```sh
swift run anysee doctor
swift run anysee validate
swift run anysee preview welcome
swift run anysee run welcome
```

`doctor` creates the local config directory, the welcome source, disabled HTTP
and script source templates in `sources/`, and default examples if they do not
already exist. The templates stay inert until `enabled = true`.

## Website

The first-launch website for `anysee.bar` lives in `public/`. It is a static
Cloudflare Pages site with one optional Pages Function at
`functions/api/waitlist.js` for waitlist/contact capture.

Cloudflare Pages settings:

```text
Build command: none
Build output directory: public
Functions directory: functions
Project name: anysee-bar
```

Local preview with Wrangler:

```sh
npx wrangler pages dev public --kv=ANYSEE_WAITLIST
```

First deploy:

```sh
npx wrangler pages deploy public --project-name anysee-bar
```

The waitlist Function stores submissions only when a Cloudflare KV binding named
`ANYSEE_WAITLIST` is configured. Do not commit API tokens, mailbox credentials,
or webhook secrets. If you add outbound email later, store the secret in
Cloudflare environment variables and keep only the non-secret binding or variable
name in the repo.

## Configuration

Global settings live in `anysee.toml`:

```toml
app_name = "AnySee"
quiet_by_default = true
max_signals_in_popover = 30
```

Each file under `sources/*.toml` defines one source:

```toml
id = "welcome"
name = "Welcome"
kind = "manual"
enabled = true

[refresh]
kind = "manual"

[[signal]]
id = "welcome-to-anysee"
title = "AnySee is ready"
body = "Edit sources/*.toml to decide what deserves attention."
priority = "normal"
state = "needs_attention"
source = "welcome"
url = "https://anysee.bar"
```

Signal priorities are `none`, `low`, `normal`, `high`, and `critical`.
Signal states are `ok`, `needs_attention`, `running`, `paused`, and `unknown`.

## Configure With AI

The app has a “Configure with AI” action that copies a prompt to the clipboard. It does not call GPT, Claude, Codex, or any model API. Paste the prompt into the AI tool of your choice and ask it to generate or modify files under the local config directory.

The generated prompt includes:

- AnySee product rules.
- Current config directory path.
- Existing source summary.
- Supported source types.
- Signal JSON example.
- Validation commands.
- Security constraints.

The config directory also contains `AGENTS.md`, written specifically for AI coding agents.

## Signal JSON

Script sources must write either one Signal JSON object or an array of Signal JSON objects to stdout:

```json
{
  "id": "backup-failed",
  "title": "Backup failed",
  "body": "Last backup exited with code 1",
  "priority": "high",
  "state": "needs_attention",
  "source": "backup-script",
  "url": "file:///Users/me/backup.log",
  "actions": [
    { "label": "Open log", "type": "open_url", "url": "file:///Users/me/backup.log" }
  ]
}
```

Supported actions are `open_url`, `copy_text`, `run_command`, `dismiss`, and `snooze`. `run_command` is executed directly without a shell.

## Credential Policy

Do not put credentials in TOML, scripts, examples, prompts, or signal bodies. Future token-based sources should store secrets in macOS Keychain and reference only a non-secret key name from configuration.
