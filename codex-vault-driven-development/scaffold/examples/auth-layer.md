---
title: auth
zoom: 0
parent: null
children:
  - login
  - signup
  - forgot-password
  - sign-out
  - withdraw
status: active
broadcasts: []
reacts_to: []
emits_to: []
code_refs:
  - lib/features/auth/
  - lib/shared/bloc/auth/
  - lib/infrastructure/auth/
  - lib/native/server/auth/
tasks:
  - {todo: "iOS runCatching isolation missing — unify with login force-sync", priority: high}
  - {todo: "Domains other than AuthFailure use String message — review for consistency", priority: low}
decisions:
  - {date: 2026-04-30, note: "Confirmed contract that splits two streams (flutter-bloc + native). Mixing them produces immediate bugs"}
  - {date: 2026-04-30, note: "Down-chain (handler → datasource → channel) is shared across every feature. Hoist into a single page"}
updated: 2026-04-30
---

# auth

User authentication domain. phone+password credentials + SMS verification + session management + profile/info changes.

## Capability boundary

What this layer is responsible for:
- Delegating credential (phone+password) verification to native and mapping the result to a domain outcome (`Either<Failure, Unit>`)
- Broadcasting auth state (`AuthState`) across the app via BLoC
- Bundling 9 features into the single `AuthBloc` class (event-based dispatch)

What this layer is NOT responsible for:
- Token storage / expiry / refresh — handled by native (Flutter only invokes the channel)
- Automatic logout (401 handling) — slice #7 infrastructure (separate layer)
- Permissions (RBAC) — `permission` layer
- Role selection — `role_select` layer

## Children (zoom-in)

| Feature | Channel method | Category |
|---|---|---|
| Login | [[login]] / `login` | simple dispatch |
| Signup | [[signup]] / `register` | multi-step |
| Password reset | [[forgot-password]] / `forgotPassword` | SMS-dependent |
| Logout | [[sign-out]] / `logout` | simple dispatch |
| Withdraw | [[withdraw]] / `withdraw` | simple dispatch |

## State broadcast contract

[[auth/_state-contract]] — defines two independent state streams (flutter-bloc per-action + native session-wide). Always use the full path `<layer>/_state-contract` — bare `[[_state-contract]]` is ambiguous across layers and the lint blocks it.

## Cross-layer dependencies

- → `core/error/failure.dart` — domain failure types
- → `lib/shared/bloc/sms/` — SmsBloc (used by signup phone-verify, phone-change, forgot-password)
- → `native/server/auth/` — MethodChannel boundary
- ← slice #7 infrastructure — 401 auto-logout (triggered by the success this layer emits)
- ← `permission`, `role_select` — branching after successful auth

## Architectural conventions

1. **AuthBloc stays thin** — 8 of the 9 handlers are 3-line folds. The exception is [[info-change]] (multi-call orchestration). Thinness is a convention, not an accident.
2. **Down-chain is shared** — the Handler → DataSource → Channel → Native chain is identical across every feature; only the method name changes. Hoisted into a single [[handler-channel]] page.
3. **SMS dependency lives in a separate BLoC** — split into `SmsBloc(purpose: ...)`. The `purpose` enum drives server-side policy branching.
4. **Failure branching belongs to the UI** — BLoC emits the Failure as-is. The UI maps `failure.code` to the appropriate localized message.
5. **Side effects live in native** — calls like `ApartmentModule.scheduler.onLogin()` represent native-side behavior that is invisible from Flutter.

## Open issues / drift watch

- iOS bridge `runCatching {}` isolation missing — only Android isolates it; if force-sync throws on iOS, the login result itself breaks
- Clarify the session-restore entry point (auth vs routing)
