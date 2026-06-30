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

- **Codex is the codebase oracle.** It runs read-only inside the repo and answers with concrete
  `file:line` evidence. It is your source of ground truth about how the code actually works.
- **You are the skeptic.** Do not accept hand-wavy answers. Push back, demand evidence, chase
  every dependency and edge case down its branch — exactly like a tough design review.
- **The human is the last resort.** Only bother the user when Codex hits a question the *code
  cannot answer* — a product call, a business rule, an external constraint. Everything else you
  resolve with Codex.

The output is a **converged plan** both models agree on, written to disk so it survives context
limits.

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
   Remember `$GRILL`. Every question to Codex goes through it:
   `"$GRILL" --root "$ROOT" "your question"`. The first call opens a Codex thread; later calls
   resume it automatically, so Codex keeps full memory of the conversation.
3. **Set `$ROOT`** to the project root you're planning against (the git root, or the cwd).
4. **Open the capture files.** Find a brainstorm folder, else create one:
   ```bash
   find . -type d -iname 'brainstorm*' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
   ```
   Use it if found (nearest the repo root); otherwise create `brainstorms/`. Inside it, create
   two files named `{YYYY-MM-DD}-{topic-slug}.plan.md` and `{YYYY-MM-DD}-{topic-slug}.grill-log.md`
   (get the date with `date +%F`). The **plan** file holds the converged decisions; the
   **grill-log** holds the round-by-round transcript. Write a header into each immediately.
5. Add `.grill-codex/` to the project's `.gitignore` if a `.gitignore` exists (that folder holds
   Codex's transient session state — not a deliverable).

## Step 1 — Get the topic (one short prompt to the user)

Ask the user, in one message, what you're planning: the feature, change, bug fix, or design, and
the goal/constraints they already know. This is the only thing you ask the user up front — from
here on, the codebase answers through Codex. Write the goal into both capture files.

## Step 2 — Open the thread (set Codex's role + ask the first question)

The first call to `$GRILL` should brief Codex on its role, then ask the single most important
opening question. Brief it once, like this:

> You are the codebase expert in a planning session. I (Claude) will interrogate you one
> question at a time to build an implementation plan for: **<topic + goal>**. For every question:
> read the actual code and answer with concrete `path/to/file:line` evidence — never guess. If a
> question is a product, business, or external decision the code cannot answer, reply on its own
> line with `NEEDS-HUMAN: <the decision, restated plainly>` and answer the rest. Be concise and
> specific. First question: **<your sharpest opening question>**

## Step 3 — The grilling loop (one question at a time)

Repeat until the plan is solid:

1. **Ask one focused question** through `$GRILL`. One question per turn — never stack several.
   Aim each question at a single decision branch (data model, call sites, edge cases, failure
   modes, migration, auth, perf, tests, rollout…), resolving upstream choices before downstream
   ones.
2. **Read Codex's answer** from the `===CODEX-ANSWER-START===` block (full text is also in
   `.grill-codex/last-answer.md`). Judge it like a reviewer:
   - **Grounded?** Did it cite real `file:line` evidence, or wave its hands? If unverified,
     ask it to point to the exact code.
   - **Complete?** Did it cover the edge cases, or only the happy path? Name the gap and ask.
   - **Did it open a new branch?** Add that to your mental tree and walk it before moving on.
   - **Do you disagree?** Say so and make Codex defend or revise its answer with evidence. You
     are allowed to be wrong too — converge on what the code supports.
3. **Handle escalation.** If Codex returns `NEEDS-HUMAN:`, pause the loop and ask the user *only*
   that question (batch a few if several have accumulated). Feed their answer back into the next
   Codex turn so the plan stays grounded.
4. **Checkpoint before the next question** (non-negotiable — see below).

## The checkpoint rule (do this after every exchange)

A long grilling fills up context; if you keep answers only in your head you will eventually drop
or conflate something. So after each Codex answer, *before* the next question:

- **Append to the grill-log** file: round number, the branch/topic, your question, a tight
  summary of Codex's answer **with its key `file:line` evidence**, and your verdict (accepted /
  pushed back / escalated).
- **Update the plan** file so it always reflects the current shared understanding — the decision,
  why, the affected files, and any open flags. Correct earlier entries when a later answer
  changes them; the plan is a living document, not an append-only log of contradictions.
- Only then ask the next question. Checkpoint one exchange at a time; never batch several writes.

## Step 4 — Converge and finish

Keep going until every branch of the decision tree is resolved and no open questions remain (or
you hit a sensible round cap — about 12–15 exchanges — or the user calls it). Then:

1. **Do a final pass with Codex:** ask it to read your finished plan file and flag anything that
   contradicts the code, any missed file, or any risk you both glossed over. Fold in what holds up.
2. **Finalize the plan file**: an ordered, concrete implementation plan grounded in real files,
   plus a short "Decided by the human" list (the few `NEEDS-HUMAN` calls) and any residual risks.
3. **Tell the user** where the plan and grill-log live, and give a 3–5 line summary: what you're
   building, the key decisions, and anything still open. Offer implementation as a separate next
   step — this skill produces the plan; it does not write feature code.

## Guardrails

- **Codex is read-only.** The helper enforces `-s read-only`; never switch it to a write mode.
  Codex investigates and answers — it does not edit the repo. All file writes (plan, log) are
  yours.
- **One question at a time.** The discipline is the point. A wall of questions gets a shallow
  answer; a single sharp question gets a deep, evidence-backed one.
- **Evidence over assertion.** Treat any claim without a `file:line` as unverified until Codex
  shows the code.
- **Don't grill the human.** If you catch yourself about to ask the user something the code could
  answer, ask Codex instead.
