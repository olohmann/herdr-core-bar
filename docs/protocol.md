# herdr-core protocol subset

Herdr Core Bar uses a small part of the herdr-core API. Run `hc schema` for the full OpenRPC
document. Everything below was checked against herdr-core 0.1.22, protocol generation 1.

## Transport

- A UNIX stream socket that carries JSON-RPC 2.0, one JSON object per line.
- Socket lookup, in order:
  1. The path set under **Settings → Connection**.
  2. `HC_SOCKET`.
  3. `$XDG_RUNTIME_DIR/herdr-core/<session>.sock`, if `XDG_RUNTIME_DIR` is set.
  4. `${XDG_STATE_HOME:-~/.local/state}/herdr-core/<session>/<session>.sock`.

  `<session>` is `HC_SESSION`, or `default` when that is unset.
- Each connection starts with `hello {"generation": 1}`. A core that doesn't support this
  generation answers with `unsupported_generation`.
- Errors look like `{"code": -32000, "message": "...", "data": {"kind": "not_found"}}`.

## Methods used

| Method | Purpose |
| --- | --- |
| `hello` | Handshake: core name, version and generation |
| `events.subscribe {}` | Snapshot `{seq, terminals}`, followed by notifications on the same connection |
| `terminal.list` | Machines and their state, for **Settings → Connection** |
| `terminal.label {terminal, labels}` | Writes `herdr.seen` after you open an agent |

`events.subscribe` holds a long-lived connection of its own. Each other call opens a short
connection.

## Notifications

```json
{"jsonrpc":"2.0","method":"heartbeat","params":{"seq":500}}
{"jsonrpc":"2.0","method":"event","params":{"seq":501,"terminal":"mini/t4","type":"status","data":{...}}}
```

| `type` | `data` | Effect |
| --- | --- | --- |
| `created` | Full terminal | Insert |
| `status` | `{status, reported, records}` | Replace the status. The time it arrives becomes `status_ms` |
| `turn` | `{turn, state}` | Update the turn |
| `title` | `{title}` | Update the title |
| `labels` | `{labels}` | Replace the whole label set |
| `foreground` | `{argv, cwd, name, pid}` | Update the foreground process |
| `finished` | `{exit_code, reason, finished_ms, signal}` | Mark it finished |
| `removed` | `{}` | Delete |
| `lost`, `restarted` | – | Toggle the lost flag |
| Other types | – | Ignored |

- Events with `seq` at or below the current sequence are dropped.
- `missed` means the subscriber fell behind:
  - If it carries a snapshot, the app replaces its state with that snapshot.
  - Otherwise the app subscribes again.
- If no line arrives for 40 seconds, the app reconnects with exponential backoff, from 1 up
  to 30 seconds. The core sends a heartbeat every 15 seconds.

## Status and read state

- A status is `{state, app?, kind?, progress?, msg?, title?}`.
  - `state` is one of `idle`, `working`, `done`, `blocked` or `error`. Other values are kept as-is.
  - `kind` is one of `permission`, `question` or `auth`.
- A terminal is an **agent** when `reported` is true or it has a status.
- **Unread done** means `status.state == "done"` and `turn > Int(labels["herdr.seen"])`.
  `turn` goes up each time an agent leaves `working`.
  Herdr.app writes `herdr.seen = "<turn>"` when you look at an agent. Herdr Core Bar does the
  same after opening one, so the two apps agree.
- Herdr.app also adds these labels:
  - `herdr.space` and `herdr.tab`: the IDs of the space and tab.
  - `where`: a display string, `"Space / Tab"`, which the popover uses for grouping.

## Opening agents in Herdr.app

```sh
herdr-app do agent.focus --terminal <address>   # show the agent
herdr-app do pane.focus  --terminal <address>   # give its terminal the keyboard
```

Herdr Core Bar activates Herdr.app (`dev.herdr.app`) before these commands. A window that
becomes active afterwards would give focus back to whatever it last had focused.
