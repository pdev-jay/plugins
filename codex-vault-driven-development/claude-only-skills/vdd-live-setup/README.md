---
name: vdd-live-setup
description: Toggle the vdd-live opt-in observability layer (statusLine + 3 hooks) on or off in the current project's .claude/settings.json. Handles install, remove, and inspect. Korean triggers — "vdd-live 깔자/켜자/세팅/등록/statusLine 붙여줘/대시보드 켜줘 / 꺼줘/제거/비활성화/없애줘 / 상태 확인/지금 깔려있나". English triggers — "enable vdd-live / install vdd-live / set up the VDD statusline / wire up vdd-live hooks / disable vdd-live / remove vdd-live / turn off the VDD statusline / vdd-live status / is vdd-live installed". Does NOT trigger on general questions about vdd-live, on `/loop` / `/schedule`, or on any non-VDD statusline talk.
user-invocable: true
---

# vdd-live-setup — one-command toggle for vdd-live

**Announce on entry:** `▸ vdd-live-setup — <mode> against <project>/.claude/settings.json`

This skill manages the vdd-live opt-in config (statusLine one-liner + 3
event-stream hooks) in the **project's** `.claude/settings.json`, in three
modes:

| Mode | What it does |
| --- | --- |
| **Install** | Merge statusLine + hooks idempotently. Asks before touching an existing `statusLine`. Tests the resulting command. |
| **Remove** | Strip VDD's statusLine + VDD's hook entries only, preserving every other key. If statusLine was installed via the combined wrapper, asks whether to keep the wrapper (and just remove the VDD branch) or remove the wrapper file entirely. Optionally wipes the per-project event state directory. |
| **Inspect** | Read-only: report which VDD components are currently wired, where, and whether the locator still resolves to an installed plugin cache. Does NOT modify anything. |

The skill never edits the user (`~/.claude`) settings file. Scope is
intentional: vdd-live state is per-project, so its wiring belongs in the
project's settings.

## When to use

- The user explicitly asks to install / enable / wire up vdd-live → Install.
- The user explicitly asks to disable / remove / turn off vdd-live → Remove.
- The user asks "is vdd-live installed?" / "status" / "확인" → Inspect.
- Re-runs to repair a partial install or to migrate after a plugin update → Install (safe, idempotent).

## When NOT to use

- The user is just asking "what does vdd-live do?" — answer from `tools/vdd-live/README.md`, do not run the skill.
- The plugin is not installed via marketplace (no plugin cache dir resolvable). Surface the cause and stop — but **Remove** can still run, because it only needs the user's settings file to strip from.

## Hard constraints

- **Project scope only.** Target is `<project-root>/.claude/settings.json`. Never touch `~/.claude/settings.json`.
- **Idempotent (Install).** Detect existing entries by exact `.command` string match. If our command is already there, do not duplicate.
- **Surgical (Remove).** Only strip entries whose `.command` contains `vdd-live-status.sh` (statusLine) or `vdd-live-emit.sh` (hooks). Preserve every other entry, key, and matcher group.
- **JSON-safe.** Read → mutate as JSON → write. Never string-concatenate. If the file exists but is invalid JSON, stop and surface the parse error instead of clobbering.
- **No silent overwrite or deletion.** Pre-existing non-VDD `statusLine` → Install asks (Wrapper / Overwrite / Skip). Wrapper-routed install → Remove asks (keep wrapper / remove wrapper file).
- **Restart required after Install or Remove.** Tell the user; hooks and statusLine load at session start. (Inspect needs no restart.)

---

## Step 0 — preflight + path resolution

```bash
command -v jq >/dev/null 2>&1 && echo OK_JQ || echo MISSING_JQ
PLUGIN_DIR="$(ls -td "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/pdev-jay/vault-driven-development/*/ 2>/dev/null | head -1)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
SETTINGS="$PROJECT_ROOT/.claude/settings.json"
WRAPPER="$HOME/.claude/scripts/statusline-combined.sh"
# STATE_DIR must equal vdd-live-lib.sh's vdd_live_base() exactly, or Remove /
# Inspect look in the wrong dir. Source the lib (via PLUGIN_DIR) so the path
# logic stays single-sourced; fall back to the legacy top-level dir only when
# the plugin isn't installed (dev clone without a marketplace cache).
if [ -n "$PLUGIN_DIR" ] && . "${PLUGIN_DIR}tools/vdd-live/vdd-live-lib.sh" 2>/dev/null; then
  STATE_DIR="$(vdd_live_base)"
else
  STATE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vdd-live"
fi
echo "PLUGIN_DIR=${PLUGIN_DIR:-NONE}"
echo "SETTINGS=$SETTINGS"
```

- `MISSING_JQ` → required for both Install and Remove (jq does the JSON merge). Surface the install hint for the user's OS, then stop.
- `PLUGIN_DIR=NONE` → required for **Install** (snippet read + sanity test). For **Remove** / **Inspect**, plugin-missing is OK — the skill still works against the user's settings file. Just note it in the final report.

---

## Step 1 — detect mode

Parse the user's invocation text (the prompt that triggered this skill):

| If prompt matches | Mode |
| --- | --- |
| `enable`, `install`, `set up`, `wire up`, `setup`, `깔`, `켜`, `세팅`, `등록`, `붙여` | **Install** |
| `disable`, `remove`, `uninstall`, `turn off`, `strip`, `꺼`, `제거`, `비활성`, `없애` | **Remove** |
| `status`, `inspect`, `check`, `installed?`, `상태`, `확인`, `깔려` | **Inspect** |

If multiple categories match or none does, ask via `AskUserQuestion` (single
select, header `Mode`, default Install):

- `Install — 활성화` / `Remove — 비활성화` / `Inspect — 상태만 확인 (변경 없음)`

Branch on the chosen mode. Steps 2–6 below are mode-specific.

---

## ── Install mode ──────────────────────────────────────────────

### I-2. Load snippet + ask components

Read the canonical commands from the snippet (use jq, not regex):

```bash
cat "${PLUGIN_DIR}tools/vdd-live/settings.snippet.json"
```

Extract:
- `STATUS_CMD = .statusLine.command`
- `HOOK_CMD   = .hooks.SubagentStop[0].hooks[0].command` (same locator on all three events)
- `PRE_MATCH  = .hooks.PreToolUse[0].matcher`   (`"Skill|Task"`)
- `POST_MATCH = .hooks.PostToolUse[0].matcher`  (`"Bash|Edit|Write|MultiEdit|Read"`)

Use these strings **verbatim**. Pulling them at runtime keeps this skill
correct across future snippet edits — do not retype from memory.

Ask via `AskUserQuestion` (multiSelect, header `Components`, default both
selected):
- `statusLine 한 줄 뷰` — same window, glanceable. Silent when no VDD activity.
- `이벤트 hooks` — PreToolUse/PostToolUse/SubagentStop emitters. Required for the statusLine to show anything (it reads the event stream they append).

If user picks neither, stop with no changes. If user picks only `statusLine`
without `hooks`, warn that the line will stay permanently empty and confirm.

### I-3. Load or initialize target file

```bash
mkdir -p "$(dirname "$SETTINGS")"
if [ -f "$SETTINGS" ]; then
  jq . "$SETTINGS" >/dev/null 2>&1 || { echo "INVALID_JSON"; exit 1; }
else
  echo '{}' > "$SETTINGS"
fi
```

`INVALID_JSON` → stop, show jq's parse error. User must fix manually.

### I-4. Merge statusLine (if selected)

```bash
CUR_STATUS="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
```

- **Empty** → write ours:
  ```bash
  jq --arg c "$STATUS_CMD" '.statusLine = {type:"command", command:$c}' "$SETTINGS" \
    > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  ```
- **Equals `STATUS_CMD`** → no-op. Report `statusLine 이미 등록됨, skip`.
- **Equals `bash $WRAPPER`** (wrapper already managed by us — detect by file existence + its content containing `vdd-live-status.sh`) → ensure wrapper still has our VDD branch; if missing, append it. No settings.json change needed.
- **Different (foreign command)** → ask `AskUserQuestion` (single select):
  - `Wrapper 생성 (Recommended)` — write `$WRAPPER` with the foreign command preserved + VDD branch beneath, then set `.statusLine.command = "bash $WRAPPER"`.
  - `덮어쓰기` — replace; existing line disappears.
  - `건너뛰기` — leave `statusLine` alone; only hooks merge.

#### Wrapper write template

If `$WRAPPER` exists, ask before overwrite (the user may already maintain
one). Write with HEREDOC, then `chmod +x`:

```bash
#!/usr/bin/env bash
set -uo pipefail
IN="$(cat 2>/dev/null || true)"

OTHER="$(printf '%s' "$IN" | bash -c '<paste CUR_STATUS here verbatim>' 2>/dev/null)"

VDD="$(printf '%s' "$IN" | bash -c 'd=$(ls -td "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/pdev-jay/vault-driven-development/*/ 2>/dev/null | head -1); [ -n "$d" ] && exec bash "${d}tools/vdd-live/vdd-live-status.sh"' 2>/dev/null)"

[ -n "$OTHER" ] && printf '%s\n' "$OTHER"
[ -n "$VDD" ]   && printf '%s\n' "$VDD"
```

Then `jq --arg c "bash $WRAPPER" '.statusLine = {type:"command", command:$c}'` etc.

### I-5. Merge hooks (if selected)

Per event, idempotent matcher-aware merge:

> Find a `hooks` entry whose `.matcher` matches the canonical matcher (or no matcher, for SubagentStop). Inside that entry's nested `hooks[]` array, check whether any element's `.command` equals `HOOK_CMD`. If yes → skip. If no → append. If no matching matcher-entry exists → create one.

```bash
jq --arg cmd "$HOOK_CMD" --arg m "$PRE_MATCH" '
  .hooks //= {}
  | .hooks.PreToolUse //= []
  | (.hooks.PreToolUse
      | map(select(.matcher == $m))
      | length) as $has_matcher
  | if $has_matcher == 0 then
      .hooks.PreToolUse += [{matcher:$m, hooks:[{type:"command", command:$cmd}]}]
    else
      .hooks.PreToolUse |= map(
        if .matcher == $m then
          if (.hooks // [] | map(.command) | index($cmd)) then .
          else .hooks = ((.hooks // []) + [{type:"command", command:$cmd}])
          end
        else . end
      )
    end
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
```

Analogous filter for `PostToolUse` with `$POST_MATCH`, and for `SubagentStop`
with no matcher (entry shape: `{hooks:[{type:"command", command:$cmd}]}`,
matched by absent/`null` `.matcher`).

After all three: `jq empty "$SETTINGS" || stop`.

### I-6. Sanity test (Install)

```bash
printf '{"cwd":"%s"}\n' "$PROJECT_ROOT" \
  | bash -c "$(jq -r '.statusLine.command' "$SETTINGS")" \
  ; echo "[exit $?]"
```

Empty output is OK (no VDD activity yet); non-zero exit → roll back the
statusLine change if the user agrees.

### I-7. Report (Install)

Summarize per component (added / replaced via wrapper / skipped / already-present),
plus the wrapper path if created. Close with:

> **재시작 필요.** statusLine 과 hooks 모두 세션 시작 시점에 로드됨. Claude Code 를 한 번 종료하고 다시 실행해.

---

## ── Remove mode ───────────────────────────────────────────────

### R-2. Read current state

```bash
[ -f "$SETTINGS" ] || { echo "no settings.json — nothing to remove"; exit 0; }
jq . "$SETTINGS" >/dev/null 2>&1 || { echo "INVALID_JSON"; exit 1; }
CUR_STATUS="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
```

Determine the statusLine situation:

| `CUR_STATUS` | Situation | Default Remove action |
| --- | --- | --- |
| empty | Already no statusLine | skip statusLine |
| contains `vdd-live-status.sh` | Direct VDD install | `del(.statusLine)` |
| equals `bash $WRAPPER` AND `$WRAPPER` exists AND `$WRAPPER` contains `vdd-live-status.sh` | Wrapper-routed install | **Ask** the user |
| anything else | Foreign statusLine, not ours | skip statusLine |

If wrapper-routed, `AskUserQuestion` (single select):
- `wrapper 에서 VDD 분기만 제거 (다른 statusline 유지)` — edit the wrapper file: remove the `VDD="$(...)" ` block and the matching `[ -n "$VDD" ] && printf ...` line. Keep `.statusLine.command` pointing at the wrapper.
- `wrapper 파일 통째 제거 + statusLine 복원` — `rm "$WRAPPER"`, then either restore the original foreign command into `.statusLine.command` (the wrapper's `OTHER="$(printf '%s' "$IN" | bash -c '...'`) line tells you what it was — extract it) OR `del(.statusLine)` if the wrapper had only the VDD branch.
- `건너뛰기` — leave statusLine and wrapper alone.

### R-3. Ask which components to remove

`AskUserQuestion` (multiSelect, default both selected):
- `statusLine` (preselected only if VDD was actually wired into it)
- `이벤트 hooks` (preselected if any of the 3 hook arrays contain a `vdd-live-emit.sh` command)
- `이벤트 상태 파일 ($STATE_DIR)` — wipe all recorded sessions for **all** projects. Off by default; rarely needed.

If nothing selected, stop with no changes.

### R-4. Strip statusLine (if selected and direct-install)

```bash
jq 'if (.statusLine.command // "" | contains("vdd-live-status.sh")) then del(.statusLine) else . end' \
  "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
```

(Wrapper-routed case was handled in R-2 — do the wrapper file edit there, not
here.)

### R-5. Strip hook entries (if selected)

Per event, remove any `hooks[].command` containing `vdd-live-emit.sh`, then
collapse empty matcher groups, then collapse the empty event array:

```bash
for ev in PreToolUse PostToolUse SubagentStop; do
  jq --arg ev "$ev" '
    if (.hooks // {})[$ev] then
      .hooks[$ev] |= (
        map(.hooks |= (map(select(.command | contains("vdd-live-emit.sh") | not))))
        | map(select((.hooks // []) | length > 0))
      )
      | if (.hooks[$ev] | length) == 0 then del(.hooks[$ev]) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    else . end
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
done
```

After all three: `jq empty "$SETTINGS" || stop`.

### R-6. Wipe state files (if selected)

```bash
rm -rf "$STATE_DIR"
```

Confirm with the user before running — this wipes events for **all** projects,
not just the current one.

### R-7. Report (Remove)

Summarize per item (removed / not present / skipped). Close with:

> **재시작 필요.** statusLine / hooks 의 변경은 다음 세션에 반영됨.

---

## ── Inspect mode ──────────────────────────────────────────────

Read-only. No `mv`, no `rm`, no `Write`.

### N-2. Walk the target file

```bash
if [ ! -f "$SETTINGS" ]; then echo "no settings.json"; exit 0; fi
jq . "$SETTINGS" >/dev/null 2>&1 || { echo "INVALID_JSON: $SETTINGS"; exit 1; }

CUR_STATUS="$(jq -r '.statusLine.command // empty' "$SETTINGS")"

# Hook presence: count of hook entries per event whose .command contains vdd-live-emit.sh
for ev in PreToolUse PostToolUse SubagentStop; do
  n=$(jq -r --arg ev "$ev" '[(.hooks // {})[$ev] // [] | .[].hooks // [] | .[] | select(.command | contains("vdd-live-emit.sh"))] | length' "$SETTINGS")
  echo "$ev: $n VDD entries"
done
```

### N-3. Resolve the locator

```bash
echo "Plugin cache: ${PLUGIN_DIR:-NOT FOUND}"
[ -f "$WRAPPER" ] && echo "Wrapper file: $WRAPPER (exists)" || echo "Wrapper file: not present"
[ -d "$STATE_DIR" ] && echo "State dir: $STATE_DIR ($(ls "$STATE_DIR" 2>/dev/null | wc -l) projects)" || echo "State dir: not present"
```

### N-4. Latest events (if any)

```bash
LOG="$(ls -t "${STATE_DIR}/$(printf '%s' "$PROJECT_ROOT" | sed 's#/#-#g')"/events.*.jsonl 2>/dev/null | head -1)"
[ -n "$LOG" ] && echo "Latest events for this project: $LOG ($(wc -l < "$LOG") events)"
```

### N-5. Report (Inspect)

Build a single status block. Example shape:

```
vdd-live status — <project>
  statusLine: <one of: not set | VDD direct | wrapper (VDD branch present|absent) | foreign>
  hooks: PreToolUse=N, PostToolUse=N, SubagentStop=N (N = VDD entries)
  plugin cache: <path or NOT FOUND>
  wrapper file: <path or not present>
  state dir: <path or not present, with project count>
  latest events for this project: <log file or none yet>
```

Close with the appropriate next step: "Install? `/vault-driven-development:vdd-live-setup`",
"Remove? same skill — say 'disable'.", or "All good, no action needed."

---

## Failure modes worth surfacing

- **`PLUGIN_DIR=NONE` during Install** — installed from a marketplace? confirm the marketplace name (`pdev-jay/vault-driven-development`). If from a clone, the locator can't find it; offer to use fixed `bash <clone>/...` paths instead and ask for the clone path. Remove/Inspect are unaffected.
- **`INVALID_JSON`** — the user's existing settings.json is malformed. Do not auto-fix; show the parse error and stop.
- **Sanity test non-zero exit (Install)** — most often a quoting bug. Show the resolved command string and the stderr, then roll back if the user agrees.
- **Wrapper-routed Remove with the wrapper edited externally** — if `$WRAPPER` exists but doesn't contain `vdd-live-status.sh`, treat the statusLine as foreign (not VDD-routed) and skip statusLine removal. Report it so the user can decide manually.
