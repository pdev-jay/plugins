---
title: connection
zoom: 0
parent: null
children: []
status: active
reacts_to:
  - auth/_state-contract#auth:expired
emits_to:
  - auth/_state-contract#auth:verified
intent_refs:
  - [[auth/auth]]
code_refs:
  - src/connection/socket.ts#SocketManager
decisions:
  - {date: 2026-05-20, note: "reconnect policy lives here, not in auth; auth only signals expiry"}
updated: 2026-05-20
---

# connection

Socket transport. Reacts to auth signals to tear down / resume the connection.

## Structure

```
connection/
└── connection.md (this page)
```

## Flow

```
auth:expired ──► SocketManager.teardown()
auth:verified ─► SocketManager.resume()
```

## Capability boundary

Owns: socket lifecycle, reconnect/backoff policy.
Does NOT own: auth token state (subscribes to `auth/_state-contract`).

## Architectural conventions

Reconnect policy is owned here. Auth only signals expiry; this layer decides
when and how to reconnect.
