---
name: grill-codex
description: >-
  Lock down a solid, codebase-grounded implementation plan by having Claude relentlessly
  interrogate the OpenAI Codex CLI — one question at a time — about a feature, change, or
  design. Codex inspects the real code (read-only) and answers each question with file/line
  evidence; Claude pushes back on weak answers, walks every branch of the decision tree, and
  escalates to the human ONLY for genuine product/business decisions the code can't settle.
  The two models go back and forth until they share a complete, written plan. Use when the
  user says "grill codex", "have codex answer", "grill the codebase", "make a plan with codex",
  "pressure-test this against the code", or wants two models to converge on a build plan before
  any code is written. Requires the `codex` CLI installed and logged in. Not for casual Q&A or
  when the user just wants a quick answer.
---

# Grill Codex

You (Claude) are the **grill-master**. Your job is to produce a rock-solid, codebase-grounded
implementation plan — not by quizzing the user, but by **relentlessly interrogating Codex**, an
agent that can read the actual code. You ask the hard questions; Codex goes and finds the
answers in the repository; you decide whether each answer holds up.

- **Codex is your codebase expert — not an infallible oracle.** It runs read-only and answers with
  concrete `file:line` evidence. Treat that as the best available read on the code, but a claim is
  only as good as the `file:line` it cites — verify it, don't defer to it.
- **You are the skeptic.** Do not accept hand-wavy answers. Push back, demand evidence, chase
  every dependency and edge case down its branch — exactly like a tough design review.
- **Escalate real product calls to the human.** If a decision materially affects product behavior,
  business policy, user experience, cost, or an external integration *and the code doesn't settle
  it*, ask the user — prefer over-escalating to silently baking in a wrong assumption. Code and
  established conventions count as evidence, so don't escalate what they reasonably settle, and
  don't ask the human what the code can answer.

The output is a plan grounded in the real code — stamped **CONVERGED** only when every open
question is resolved, or honestly **PARTIAL** when it isn't (Step 4). It's written to disk so it
survives context limits, and a fresh, independent model attacks it before it's ever called done.

## Step 0 — Preflight (do this silently, before anything else)

1. **Confirm Codex is available.** Run `command -v codex`. If missing, stop and tell the user:
   "This skill needs the OpenAI Codex CLI. Install it (`npm i -g @openai/codex`) and run
   `codex login`, then try again." Do not fake the loop without it.
2. **Locate the helper script** that drives Codex. It ships next to this skill. Find it once
   (this is bash- and zsh-safe — don't use bare `*` globs in a list, zsh aborts on no-match):
   ```bash
   GRILL=""
   for c in "${CLAUDE_PLUGIN_ROOT}/skills/grill-codex/ask-codex.sh" \
            "$HOME/.claude/skills/grill-codex/ask-codex.sh"; do
     [ -f "$c" ] && GRILL="$c" && break
   done
   [ -z "$GRILL" ] && GRILL="$(find "$HOME/.claude/plugins" -path '*grill-codex/skills/grill-codex/ask-codex.sh' 2>/dev/null | head -1)"
   echo "using helper: $GRILL"
   ```
   Remember `$GRILL`. Every question to Codex goes through it, tagged with this topic's **slot** so
   a new topic never inherits a previous topic's thread:
   `"$GRILL" --root "$ROOT" --slot "$SLUG" "your question"`
   The first call opens a Codex thread for that slot; later calls resume it automatically, so Codex
   keeps full memory of *this* conversation. (You set `$SLUG` in item 4 below.)
3. **Set `$ROOT`** to the project root you're planning against (the git root, or the cwd).
4. **Open the capture files.** Find a brainstorm folder, else create one:
   ```bash
   find . -type d -iname 'brainstorm*' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
   ```
   Use it if found (nearest the repo root); otherwise create `brainstorms/`. Set `$SLUG` to the
   `{topic-slug}` for this session and **reuse it as the Codex `--slot`** (above) so this topic's
   thread stays isolated. Inside the folder, create two files named `{YYYY-MM-DD}-{SLUG}.plan.md`
   and `{YYYY-MM-DD}-{SLUG}.grill-log.md` (get the date with `date +%F`). The **plan** file holds
   the converged decisions and the Open Branches ledger; the **grill-log** holds the round-by-round
   transcript. Write a header into each immediately.
5. Add `.grill-codex/` to the project's `.gitignore` if a `.gitignore` exists (that folder holds
   Codex's transient session state — not a deliverable).

## Step 1 — Get the topic (one short prompt to the user)

Ask the user, in one message, what you're planning: the feature, change, bug fix, or design, and
the goal/constraints they already know. This is the only thing you ask the user up front — from
here on, the codebase answers through Codex. Write the goal into both capture files.

## Step 2 — Open the thread (set Codex's role + ask the first question)

The first call to `$GRILL` (with `--slot "$SLUG"`) should brief Codex on its role, then ask the
single most important opening question. Brief it once, like this:

> You are the codebase expert in a planning session. I (Claude) will interrogate you one
> question at a time to build an implementation plan for: **<topic + goal>**. For every question:
> read the actual code and answer with concrete `path/to/file:line` evidence — never guess. If a
> decision materially affects product behavior, business policy, user experience, cost, or an
> external integration *and the code does not settle it*, reply on its own line with
> `NEEDS-HUMAN: <the decision, restated plainly>` and answer the rest — prefer flagging it to
> guessing. (Code and established conventions count as evidence; don't flag what they reasonably
> settle.) Be concise and specific. First question: **<your sharpest opening question>**

## Step 3 — The grilling loop (one question at a time)

Repeat until the **Open Branches ledger is empty** (see the checkpoint rule), or you reach the
round budget:

1. **Ask one focused question** through `$GRILL` (always with `--slot "$SLUG"`). One question per
   turn — never stack several.
   Aim each question at a single decision branch (data model, call sites, edge cases, failure
   modes, migration, auth, perf, tests, rollout…), resolving upstream choices before downstream
   ones.
2. **Read Codex's answer** from the `===CODEX-ANSWER-START===` block (full text is also in
   `.grill-codex/{SLUG}.last-answer.md`). Judge it like a reviewer:
   - **Grounded?** Did it cite real `file:line` evidence, or wave its hands? If unverified,
     ask it to point to the exact code.
   - **Complete?** Did it cover the edge cases, or only the happy path? Name the gap and ask.
   - **Did it open a new branch?** Add it as a row in the Open Branches ledger and walk it before
     moving on.
   - **Do you disagree?** Say so and make Codex defend or revise its answer with evidence. You
     are allowed to be wrong too — converge on what the code supports.
3. **Handle escalation.** If Codex returns `NEEDS-HUMAN:`, collect it; when a few have accumulated,
   **ask the user in one batch** (don't interrupt them one question at a time). Record each answer
   **verbatim** in the plan's "Decided by the human" section — summarize the implications
   *separately*, never let a paraphrase replace their words — then feed it back into the next Codex
   turn. **Before writing any human answer to disk, screen it for secrets, PII, or sensitive
   business data** (see Guardrails) and redact if needed.
4. **Checkpoint before the next question** (non-negotiable — see below).

## The checkpoint rule (do this after every exchange)

A long grilling fills up context; if you keep answers only in your head you will eventually drop
or conflate something. So after each Codex answer, *before* the next question:

- **Append to the grill-log** file: round number, the branch/topic, your question, a tight
  summary of Codex's answer **with its key `file:line` evidence**, and your verdict (accepted /
  pushed back / escalated).
- **Update the plan** file and its **Open Branches ledger** so they always reflect the current
  shared understanding — the decision, why, and the affected files. Correct earlier entries when a
  later answer changes them; the plan is a living document, not an append-only log of contradictions.
- **Maintain the Open Branches ledger** (a table in the plan file) as the objective done-signal.
  One row per open question, with columns: `ID`, `question`, `owner` (codex / human), `status`
  (open / resolved), `blocking evidence`, `resolution`. Add a row whenever a new branch appears;
  mark it resolved only when it's genuinely settled. You are **done only when no rows are open** —
  not when you "feel" the plan is solid. (An empty ledger proves you resolved the branches you
  *found*; the fresh adversarial pass in Step 4 is the backstop for branches you never found.)
- Only then ask the next question. Checkpoint one exchange at a time; never batch several writes.

## Step 4 — Converge and finish

Keep going until the **Open Branches ledger is empty**. Treat **~10 exchanges as a soft budget** —
a cost/latency checkpoint, *not* a quality bar. If you reach it with rows still open, **stop and
ask the user whether to continue**; if you stop, label the plan **`PARTIAL / UNRESOLVED`** and list
the open branches. Never call a plan converged while the ledger has open rows. Then:

1. **Run a fresh, independent adversarial pass** — the convergence gate, on by default:

   ```bash
   "$GRILL" --root "$ROOT" --slot "$SLUG-adversary" --new "<attack prompt>"
   ```

   It runs in **its own session slot with `--new`**, so it has *no memory* of the grilling thread
   (an unanchored second opinion — and it can't clobber the main thread's session). Feed it the
   **finished plan file + the Open Branches ledger + a redacted digest of the load-bearing claims**
   (not the raw transcript — that just re-anchors it). Tell it to *attack*: disprove the plan, find
   missed files, surface alternative interpretations and unsupported assumptions, and cite
   `path:line`. **Any finding reopens the ledger** — add rows and resolve them; don't fold fixes in
   ad hoc. (This replaces the old same-thread self-review, which let the planner grade its own
   work.) The user may skip this gate only if they explicitly say so.
2. **Finalize the plan file**: an ordered, concrete implementation plan grounded in real files; the
   verbatim "Decided by the human" list; residual risks; and the final ledger state — `CONVERGED`
   (no open rows) or `PARTIAL` (rows listed).
3. **Tell the user** where the plan and grill-log live, and give a 3–5 line summary: what you're
   building, the key decisions, what (if anything) is still open, and whether it's **CONVERGED** or
   **PARTIAL**. Offer implementation as a separate next step — this skill produces the plan; it
   does not write feature code.

## Guardrails

- **Codex is read-only.** The helper enforces `-s read-only`; never switch it to a write mode.
  Codex investigates and answers — it does not edit the repo. All file writes (plan, log) are
  yours.
- **One question at a time.** The discipline is the point. A wall of questions gets a shallow
  answer; a single sharp question gets a deep, evidence-backed one.
- **Evidence over assertion.** Treat any claim without a `file:line` as unverified until Codex
  shows the code.
- **Protect sensitive data.** Before writing anything a human told you into the plan or log, screen
  it for secrets, credentials, PII, or sensitive business context. Redact it or store a reference
  instead — never commit raw sensitive data — and tell the user when you do.
- **Ask Codex what the code can answer; ask the human what it can't.** Don't spend a user's
  attention on something the code or its conventions already settle. But when a real
  product/business/external decision *isn't* settled by the code, err toward asking rather than
  guessing (the escalation rule above) — a wrong silent assumption is worse than one extra question.
