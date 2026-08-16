# Message Protocol

## Overview

The current `ai: ...` text syntax is ad-hoc. This document specifies the formal protocol envelope that all transports map onto, and the role-based coordinator addressing system built on top of it.

---

## Canonical Message Envelope

Every message, regardless of transport, maps to the following fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | `String` | yes | Protocol version (e.g. `"1"`) |
| `role` | `String\|nil` | no | Coordinator role target; `nil` uses the default role |
| `verb` | `String\|nil` | no | Routing verb: `claude`, `main`, `new`, `bash`, or `nil` |
| `workspace` | `String\|nil` | no | tmux workspace name or alias |
| `instructions` | `String` | yes | Instruction payload |
| `work_item_ref` | `String\|nil` | no | Work item identity |
| `source` | `String\|nil` | no | Transport hint: `imessage`, `socket`, or `http` |

---

## Text Syntax Grammar

The `ai:` text syntax parses left to right in the following order:

1. Strip the `ai:` prefix.
2. Peek at the next token. If it matches `word:` (a word immediately followed by a colon, with **no** space between the word and the colon), extract it as `role` and consume the trailing colon and optional space.
3. Peek at the next token. If it is a known verb (`claude`, `main`, `new`, `bash`), extract it as `verb`.
4. Try to match the `WORKSPACE - instructions` pattern.
5. Treat the remainder as `instructions` (free-form text).

### Examples

| Text | role | verb | workspace | instructions |
|------|------|------|-----------|--------------|
| `ai: MS - add validation` | nil | nil | MS | add validation |
| `ai: claude MS - add validation` | nil | claude | MS | add validation |
| `ai:home: claude MS - add validation` | home | claude | MS | add validation |
| `ai:h: MS - add validation` | h | nil | MS | add validation |
| `ai:work: new MS - add validation` | work | new | MS | add validation |

### Disambiguation

- `ai:home: ...` (no space after `ai:`) → `role=home`
- `ai: home - fix it` (space after `ai:`) → `role=nil`, `workspace=home`

These two forms are unambiguous.

---

## Role Addressing

### Configuration

Each coordinator has one configured role. The role is resolved in the following order (highest to lowest precedence):

1. `--role` CLI flag
2. `WC_ROLE` environment variable
3. `role:` key in `config.yml`

The default role when none is configured is `"default"`.

Role aliases can be declared alongside the role:

```yaml
role: home
role_aliases:
  - h
  - hm
```

### Matching

An incoming message's role (downcased) must equal the coordinator's configured role, or be present in `role_aliases`, for the message to be processed.

A `nil` role (no role token in the message) is accepted by coordinators with `role: default` or no role configured. This preserves full backward compatibility — all existing `ai: ...` messages continue to work without modification.

Messages whose role does not match the coordinator's role are **silently dropped**; another coordinator on the network is expected to handle them.

---

## Verb Vocabulary

| Verb | Meaning | Routes to |
|------|---------|-----------|
| `claude` | Deliver to main session pane | `DeliverToMainSession` |
| `main` | Alias for `claude` | `DeliverToMainSession` |
| `new` | Open a new tmux pane | *(future)* |
| `bash` | Open a new bash pane | *(future)* |
| *(nil)* | Free-form dispatch | `AiCommandHandler` |

---

## JSON Socket Wire Format

Structured delivery uses the `command_v1` message type:

```json
{
  "version": "1",
  "type": "command_v1",
  "role": "home",
  "verb": "claude",
  "workspace": "MS",
  "instructions": "add validation",
  "work_item_ref": "WC-42",
  "source": "socket"
}
```

The plain-text `"<ref> <body>"` socket format continues to work for backward compatibility.

---

## Versioning

- The `version` field is an integer string (`"1"`, `"2"`, ...).
- **Text syntax**: breaking changes use a new prefix (e.g. `ai2:`). Additive changes (new role token, new verbs) are backward-compatible within `ai:`.
- **JSON socket**: the `type` field carries a version suffix if the shape changes incompatibly (e.g. `command_v2`).
- The coordinator echoes its supported version in the epoch reply:

```json
{"ok": true, "epoch": "...", "protocol_version": "1"}
```

---

## Implementation Phases

1. Add `role` and `role_aliases` to Config, plus a `--role` CLI flag. No behavior change.
2. Extend the text parser to extract the role token before verb and workspace resolution.
3. Add a role gate in `AiCommandReceiver` — drop non-matching messages.
4. Add `command_v1` JSON envelope handling to `SocketMessageReceiver`.
5. Echo `protocol_version: "1"` in the socket epoch reply.

---

## Backward Compatibility

All existing `ai: ...` messages produce `role: nil`. A coordinator without a role configured, or configured with `role: default`, processes all such messages exactly as it does today. No changes are required to existing clients or message senders.
