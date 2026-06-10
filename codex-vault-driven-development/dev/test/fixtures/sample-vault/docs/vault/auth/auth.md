---
title: auth
zoom: 0
parent: null
children:
  - _state-contract
status: active
broadcasts:
  - auth:expired
  - auth:verified
code_refs:
  - src/auth/session.ts#AuthSession
decisions:
  - {date: 2026-05-20, note: "auth owns session lifecycle; transport layers react via state-contract, never call auth directly"}
updated: 2026-05-20
---

# auth

Session lifecycle owner. Emits `auth:expired` / `auth:verified` for downstream
transport layers to react to.

## Structure

```
auth/
├── auth.md            (this page)
└── _state-contract.md (signal emitter)
```

## Flow

```
AuthSession
   │
   ├──auth:verified──► connection (resume)
   └──auth:expired───► connection (teardown)
```

## Capability boundary

Owns: session token lifecycle, expiry detection.
Does NOT own: socket transport, reconnect policy (that is `connection`).

## Architectural conventions

Transport layers never call auth directly — they subscribe to the
state-contract signals. This keeps auth transport-agnostic.
