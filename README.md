# grill-codex

**Two models, one plan.** A Claude Code skill where **Claude relentlessly interrogates the OpenAI Codex CLI** about your codebase — one question at a time — until the two of them converge on a solid, code-grounded implementation plan. You barely have to type.

The popular [`grill-me`](https://github.com/mattpocock/skills) skill flips the usual dynamic: instead of building immediately, Claude grills *you* with hard questions until the plan is airtight. `grill-codex` flips it again — **Claude grills Codex, not you.** Codex reads the actual code and answers each question with `file:line` evidence; you only get pulled in for decisions the code genuinely can't settle (a product call, a business rule).

The result: a plan that's been pressure-tested by two *different* model families before a single line of feature code is written. A model that plans and writes the build shouldn't be the only one grading it — so a second model does.

---

## Why this is useful

- **The codebase has the answers, not your memory.** Most "grill me" questions are really questions about how the code works today. Codex can just go read it — faster and more accurately than you recalling it.
- **Two model families cross-check.** Claude's blind spots aren't Codex's blind spots. Disagreements surface real risk instead of getting rubber-stamped.
- **Evidence, not vibes.** Every Codex answer is expected to cite `file:line`. Claude treats anything unverified as unverified and pushes back.
- **Nothing gets lost.** Every exchange is checkpointed to disk, so a long session survives context limits.
- **You stay in the loop, lightly.** You set the topic, answer the rare escalation, and read the finished plan.

## How it works

```mermaid
flowchart TD
    U([You: "grill codex about X"]) --> C[Claude forms one sharp question]
    C -->|read-only| X[Codex reads the code,<br/>answers with file:line evidence]
    X --> J{Claude judges the answer}
    J -->|weak / incomplete| C
    J -->|code can't decide it| H[Ask the human just that]
    H --> C
    J -->|solid, branch resolved| K[Checkpoint plan + log to disk]
    K -->|open branches remain| C
    K -->|plan is complete| P([PLAN.md + grill-log.md])
```

1. You say what you want to plan. That's the only thing you're asked up front.
2. Claude opens a persistent Codex session and asks the single most important question.
3. Codex inspects the repo **read-only** and answers with evidence.
4. Claude evaluates: grounded? complete? does it open a new branch? — then pushes back, drills deeper, or moves on. Open questions go into a ledger in the plan file.
5. A decision the code can't settle (a real product/business call) is flagged `NEEDS-HUMAN:` and batched to you — the loop errs toward asking rather than guessing.
6. Every exchange is checkpointed to a plan file and a grill-log. The loop ends when the ledger is empty; if a round budget is hit first, the plan is honestly marked **PARTIAL** and lists what's still open.
7. **A fresh, independent Codex then attacks the finished plan** — a separate, unanchored thread, so the planner can't quietly grade its own work. Anything it finds reopens the ledger.

Codex remembers the whole conversation across rounds (each turn resumes the same thread), so the dialogue compounds instead of resetting — except that final attacker pass, which starts clean on purpose.

## Requirements

- **[Claude Code](https://docs.claude.com/en/docs/claude-code)** — this is where the skill runs.
- **[OpenAI Codex CLI](https://github.com/openai/codex)**, installed and logged in:
  ```bash
  npm i -g @openai/codex
  codex login
  ```

## Install

### Option A — as a Claude Code plugin (shareable, updates by `git pull`)

```text
/plugin marketplace add smroczek2/grill-codex
/plugin install grill-codex@grill-codex
```

### Option B — as a user skill, available in every project

```bash
git clone https://github.com/smroczek2/grill-codex.git
cd grill-codex
./install.sh
```

This symlinks the skill into `~/.claude/skills/grill-codex`, so it's available in all your projects and a later `git pull` updates it everywhere. Uninstall with `rm ~/.claude/skills/grill-codex`.

## Use

In any project, open Claude Code and say:

```text
grill codex about <your feature, change, or design>
```

for example:

```text
grill codex about adding soft-delete to the orders table
grill codex on how I should wire the new webhook into the existing queue
grill the codebase and make a plan for migrating auth to the new provider
```

> ⏱ **Expect minutes, not seconds.** Codex reasons at high effort, so each round takes a few minutes and a full session can run 15–45 minutes. That's the cost of a genuinely code-grounded, double-checked plan — it's a deliberate planning tool, not a quick-answer chat.

## What you get

Two files land in your project's `brainstorms/` folder (or an existing `brainstorm*` folder):

- **`{date}-{topic}.plan.md`** — the implementation plan, grounded in real files: ordered steps, an open-branches ledger, a verbatim "decided by the human" list, residual risks, and a final stamp of **CONVERGED** or **PARTIAL**.
- **`{date}-{topic}.grill-log.md`** — the full round-by-round transcript: each question, Codex's evidence, Claude's verdict, and the final attacker pass.

Transient Codex session state lives in a git-ignored `.grill-codex/` folder (one thread per topic, plus a separate one for the attacker pass) and can be deleted any time.

## Safety

Codex runs **read-only** every round (`-s read-only`): it reads the code and runs read-only commands, but never edits, creates, or deletes files. The only files written are the plan and log, written by Claude — and any answer you give is screened for secrets/PII before it's written, never committed raw. This skill produces a *plan* — implementing it is a separate, deliberate next step.

## License

MIT — see [LICENSE](LICENSE).
