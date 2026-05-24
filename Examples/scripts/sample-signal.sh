#!/bin/sh
printf '%s\n' '{
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
