#!/usr/bin/env bash
#
# ask-codex.sh — relay ONE question to a persistent, read-only Codex session
# and return its answer.
#
# The first call in a project opens a fresh Codex thread; every later call
# resumes that same thread, so Codex remembers the entire conversation. This is
# what lets Claude (the "grill-codex" skill) interrogate a codebase through
# Codex across many rounds without re-explaining context each time.
#
# Codex always runs READ-ONLY: it can read the code and run read-only shell
# commands, but it cannot edit, create, or delete files. Nothing is written to
# your repo by Codex itself.
#
set -euo pipefail

die() { printf '\n[ask-codex] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
ask-codex.sh — relay one question to a persistent, read-only Codex session.

The first call opens a fresh Codex thread; later calls resume it, so Codex
remembers the whole conversation. Codex runs READ-ONLY (reads code + runs
read-only commands; never edits files).

Usage:
  ask-codex.sh [options] "your question"

Options:
  --root <dir>   Project root Codex should reason about (default: current dir)
  --slot <name>  Session slot — keeps independent threads side by side in one
                 repo (default: "main"). Use a distinct slot per planning topic
                 so a new topic never inherits an old topic's context, and a
                 separate slot (e.g. the topic + "-adversary") for a fresh,
                 unanchored review thread that must NOT clobber the main one.
  --new          Force a brand-new thread for this slot (forget its existing one)
  --reset        Forget this slot's thread and exit (no question needed)
  --quiet        Don't stream Codex's reasoning live; save it to the run log
  -h, --help     Show this help

Output:
  Codex's final answer is written to <root>/.grill-codex/<slot>.last-answer.md
  and echoed between ===CODEX-ANSWER-START=== / ===CODEX-ANSWER-END=== markers so
  a caller can grab just the reply.
EOF
}

command -v codex >/dev/null 2>&1 \
  || die "the 'codex' CLI is not installed or not on PATH. Install it (e.g. npm i -g @openai/codex) and run 'codex login' first."

ROOT="$(pwd)"
FORCE_NEW=0
QUIET=0
RESET=0
SLOT="main"
PROMPT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)   ROOT="${2:?--root needs a path}"; shift 2 ;;
    --slot)   SLOT="${2:?--slot needs a name}"; shift 2 ;;
    --new)    FORCE_NEW=1; shift ;;
    --quiet)  QUIET=1; shift ;;
    --reset)  RESET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --)       shift; PROMPT="${1:-}"; break ;;
    -*)       die "unknown option: $1 (use --help)" ;;
    *)        PROMPT="$1"; shift ;;
  esac
done

ROOT="${ROOT%/}"
[[ -d "$ROOT" ]] || die "root directory does not exist: $ROOT"
# sanitize the slot to a safe filename component (so topic slugs are usable verbatim)
SLOT="$(printf '%s' "$SLOT" | tr -c 'A-Za-z0-9._-' '-')"
[[ -n "$SLOT" ]] || SLOT="main"

# Per-slot state: independent threads can coexist in one repo. This is what stops
# (a) a new topic inheriting an old topic's thread, and (b) a fresh adversarial
# review (its own slot) from overwriting the primary grilling thread's session id.
STATE="$ROOT/.grill-codex"
mkdir -p "$STATE"
SIDFILE="$STATE/${SLOT}.session"
ANSWER="$STATE/${SLOT}.last-answer.md"
RUNLOG="$STATE/${SLOT}.last-run.log"

if [[ $RESET -eq 1 ]]; then
  rm -f "$SIDFILE"
  echo "[ask-codex] session reset for slot '$SLOT' in $ROOT"
  exit 0
fi

[[ -n "$PROMPT" ]] || { usage; die "no question given."; }

run_codex() {  # honors --quiet: stream live (tee) or save-only.
  # stdin is redirected from /dev/null so codex gets immediate EOF and never
  # blocks "Reading additional input from stdin..." when launched with an open
  # (but empty) stdin pipe — e.g. from an automation/agent harness.
  if [[ $QUIET -eq 1 ]]; then
    codex "$@" </dev/null >"$RUNLOG" 2>&1
  else
    codex "$@" </dev/null 2>&1 | tee "$RUNLOG"
  fi
}

if [[ $FORCE_NEW -eq 0 && -s "$SIDFILE" ]]; then
  SID="$(cat "$SIDFILE")"
  # resume inherits the sandbox (read-only) and workdir from the opening turn
  run_codex exec resume "$SID" --skip-git-repo-check -o "$ANSWER" "$PROMPT" \
    || die "codex resume failed for session $SID — rerun with --new to start a fresh thread."
else
  run_codex exec -s read-only --skip-git-repo-check -C "$ROOT" -o "$ANSWER" "$PROMPT" \
    || die "codex failed to start a thread."
  SID="$(grep -oiE 'session id:[[:space:]]*[0-9a-f-]{36}' "$RUNLOG" 2>/dev/null \
          | grep -oiE '[0-9a-f-]{36}' | head -1 || true)"
  if [[ -n "$SID" ]]; then
    printf '%s' "$SID" >"$SIDFILE"
  else
    echo "[ask-codex] WARN: could not capture Codex session id; the next call will open a new thread." >&2
  fi
fi

printf '\n===CODEX-ANSWER-START===\n'
cat "$ANSWER" 2>/dev/null || echo "(no answer captured — see $RUNLOG)"
printf '\n===CODEX-ANSWER-END===\n'
