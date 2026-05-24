import Foundation

public enum DefaultConfigTemplates {
    public static let mainConfig = """
    app_name = "AnySee"
    quiet_by_default = true
    max_signals_in_popover = 30
    """

    public static let manualSource = """
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

    [[signal.action]]
    label = "Open site"
    type = "open_url"
    url = "https://anysee.bar"

    [[signal.action]]
    label = "Copy config path"
    type = "copy_text"
    text = "~/Library/Application Support/AnySee"

    [[signal.action]]
    label = "Dismiss"
    type = "dismiss"
    """

    public static let httpSource = """
    id = "template-http-health"
    name = "Template: HTTP Health Check"
    kind = "http"
    enabled = false

    [refresh]
    kind = "interval"
    interval_seconds = 300

    [http]
    url = "https://example.com/health.json"
    method = "GET"
    expected_status = 200
    signal_on_status_mismatch = true
    json_path = "status"
    not_equals = "ok"
    title = "HTTP health check needs attention"
    body = "The configured HTTP health check did not report status=ok."
    priority = "high"
    state = "needs_attention"
    """

    public static let scriptSource = """
    id = "template-script-signal"
    name = "Template: Script Signal"
    kind = "script"
    enabled = false

    [refresh]
    kind = "manual"

    [script]
    path = "sample-signal.sh"
    timeout_seconds = 10
    """

    public static let sampleScript = """
    #!/bin/sh
    printf '%s\\n' '{
      "id": "sample-script-signal",
      "title": "Sample script signal",
      "body": "This signal came from scripts/sample-signal.sh",
      "priority": "low",
      "state": "needs_attention",
      "source": "template-script-signal",
      "actions": [
        { "label": "Dismiss", "type": "dismiss" }
      ]
    }'
    """

    public static let sampleSignalJSON = """
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
    """

    public static let signalSchema = """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "$id": "https://anysee.bar/schemas/signal.schema.json",
      "title": "AnySee Signal",
      "type": "object",
      "required": ["id", "title", "priority", "state", "source"],
      "additionalProperties": false,
      "properties": {
        "id": { "type": "string", "minLength": 1 },
        "title": { "type": "string", "minLength": 1 },
        "body": { "type": "string" },
        "priority": { "type": "string", "enum": ["none", "low", "normal", "high", "critical"] },
        "state": { "type": "string", "enum": ["ok", "needs_attention", "running", "paused", "unknown"] },
        "source": { "type": "string", "minLength": 1 },
        "url": { "type": "string" },
        "actions": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["label", "type"],
            "additionalProperties": false,
            "properties": {
              "label": { "type": "string", "minLength": 1 },
              "type": { "type": "string", "enum": ["open_url", "copy_text", "run_command", "dismiss", "snooze"] },
              "url": { "type": "string" },
              "text": { "type": "string" },
              "command": { "type": "string" },
              "arguments": { "type": "array", "items": { "type": "string" } },
              "duration_minutes": { "type": "integer", "minimum": 1 }
            }
          }
        }
      }
    }
    """

    public static let agentsGuide = """
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
    - Do not use shell pipelines in generated config. AnySee runs script sources directly and run_command actions without a shell.
    - Keep scripts narrowly scoped, readable, and deterministic. Avoid network calls unless the user explicitly asked for that source.
    - If future credentials are needed, instruct the user to store them in macOS Keychain and reference only a key name from config.
    - Keep signals actionable and sparse. AnySee is an attention feed, not a dashboard or log stream.
    """
}
