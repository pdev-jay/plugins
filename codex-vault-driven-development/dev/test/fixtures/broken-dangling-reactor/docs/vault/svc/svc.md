---
title: svc
zoom: 0
parent: null
children: []
status: active
reacts_to:
  - svc/_state-contract#svc:ghost
code_refs:
  - src/svc/svc.ts#Svc
updated: 2026-05-20
---

# svc

Reacts to `svc:ghost` — a key that NO page broadcasts. Intentional dangling
reactor edge for the lint detection test.

## Structure

```
svc/
└── svc.md (this page)
```

## Flow

```
svc:ghost ──► (dangling — no emitter)
```

## Capability boundary

Owns: nothing real (fixture).
