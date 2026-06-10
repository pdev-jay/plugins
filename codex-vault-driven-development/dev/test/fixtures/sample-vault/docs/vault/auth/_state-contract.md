---
title: auth state contract
zoom: 1
parent: [[auth]]
children: []
status: active
broadcasts:
  - auth:expired
  - auth:verified
code_refs:
  - src/auth/session.ts#AuthSession
updated: 2026-05-20
---

# auth state contract

Signal emitter for the auth layer.

## State variants

| Key | Payload | Meaning |
|---|---|---|
| `auth:verified` | session id | token validated, session live |
| `auth:expired` | none | token expired, session dead |

## Reactor matrix

| Key | Reactor | How |
|---|---|---|
| `auth:expired` | [[connection]] | tears down socket |
| `auth:verified` | [[connection]] | resumes socket |
