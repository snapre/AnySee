# AGENTS.md for AnySee configuration

You are helping configure AnySee, a local-first macOS menu bar attention center. Generate small, auditable config changes only. AnySee does not call model APIs, does not use an AnySee backend, and should not store credentials in TOML files.

## Local directory

`~/Library/Application Support/AnySee/`

- `anysee.toml`: global app settings.
- `sources/*.toml`: one signal source per file.
- `scripts/*`: local scripts used by script sources.
- `schemas/signal.schema.json`: JSON schema for script stdout.
- `examples/*`: reference configs and signal JSON.
- `AGENTS.md`: this file.

## Source TOML

Required root keys:

```toml
id = "stable-source-id"
name = "Human Name"
kind = "manual" # manual, http, or script
enabled = true
```

Refresh policy:

```toml
[refresh]
kind = "manual" # manual, interval, or schedule
interval_seconds = 300
schedule = "09:00" # reserved for future schedule support
```

Manual signals:

```toml
[[signal]]
id = "backup-failed"
title = "Backup failed"
body = "Last backup exited with code 1"
priority = "high"
state = "needs_attention"
source = "backup"
url = "file:///Users/me/backup.log"

[[signal.action]]
label = "Open log"
type = "open_url"
url = "file:///Users/me/backup.log"
```

HTTP source:

```toml
[http]
url = "https://example.com/health.json"
method = "GET"
expected_status = 200
signal_on_status_mismatch = true
json_path = "status"
not_equals = "ok"
title = "Service needs attention"
body = "Health endpoint did not return status=ok."
priority = "high"
state = "needs_attention"
```

Script source:

```toml
[script]
path = "sample-signal.sh"
timeout_seconds = 10
```

Script stdout must be one Signal JSON object or an array of Signal JSON objects matching `schemas/signal.schema.json`.

## Validation commands

From the project checkout:

```sh
swift run anysee doctor
swift run anysee validate
swift run anysee preview welcome
swift run anysee run welcome
```

From an installed binary:

```sh
anysee doctor
anysee validate
anysee preview welcome
anysee run welcome
```

## Security constraints

- Do not put API tokens, passwords, cookies, session IDs, SSH keys, or OAuth credentials in TOML, scripts, examples, prompts, or signal bodies.
- Prefer relative script paths under `scripts/`.
- Prefer relative `run_command` commands under `scripts/`; AnySee resolves them there and rejects traversal outside that directory.
- Do not use shell pipelines in generated config. AnySee runs script sources directly and run_command actions without a shell.
- Keep scripts narrowly scoped, readable, and deterministic. Avoid network calls unless the user explicitly asked for that source.
- If future credentials are needed, instruct the user to store them in macOS Keychain and reference only a key name from config.
- Keep signals actionable and sparse. AnySee is an attention feed, not a dashboard or log stream.
