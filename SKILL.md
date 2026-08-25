---
name: sitrep
description: Situation report across every git repo in a workspace — scans for uncommitted changes, unpushed commits, stashes, and parked feature branches (anything pending a decision), then cross-references project docs for planned roadmap items and renders it all as a self-contained HTML infographic (branch graphs, dirty-tree meters, stash flags). Use whenever the user asks for a sitrep, status report, "what's pending", "where did I leave off", "state of my projects", "anything uncommitted?", "what's left on the roadmap", or wants a morning/weekly overview of the whole workspace — even if they only vaguely ask what needs attention.
---

# Sitrep

Produce a decision-oriented situation report for a whole workspace of repos: what work
is sitting uncommitted or unpushed (and what to do about it), plus what's planned-but-not-started
according to project docs.

The goal is not a data dump — it's to answer two questions the user actually has:
1. **What did I leave hanging, and what decision does each item need?** (commit / push / PR / discard / finish)
2. **What's next on each project's roadmap?**

## Setup

The scan defaults to `~/Development` as the workspace root. If the user's repos live
elsewhere, pass the root as an argument, or edit `ROOT` at the top of
`scripts/git_scan.sh`. Same for `SKIP_DIRS` — the directories to ignore.

## Step 1 — Git scan

Run the bundled script (fast, read-only):

```bash
~/.claude/skills/sitrep/scripts/git_scan.sh              # defaults to ~/Development
~/.claude/skills/sitrep/scripts/git_scan.sh ~/src        # or point it anywhere
```

It prints a summary table for every repo, then detail blocks (changed files, unpushed commit
subjects, stashes, local branches) for repos with pending work.

Treat these as **pending decisions**, in rough priority order:
- **Dirty working tree** — uncommitted edits. The bigger and older, the more urgent the decision.
- **Unpushed commits** — including on side branches; the summary AHEAD column only tracks the
  current branch, so read the `[unpushed commits]` and `[branches]` detail (branches with no
  `>`/`=` marker have no upstream — fully local).
- **Repo parked on a non-main branch** — usually a feature mid-flight; is it done, abandoned,
  or waiting on a PR?
- **Stashes** — easily forgotten; either worth recovering or worth dropping.
- **Agent-created branches** (`claude/*`, `codex/*`, or whatever your tooling names them) —
  leftovers from agent sessions; usually safe to flag for deletion once merged, but check
  `git branch --no-merged main` before saying so.
- **No remote** — every commit is one disk failure from gone; suggest adding a remote.

## Step 2 — Identify what the pending work IS

A count of dirty files is not a decision. For each repo with pending work, spend one or two
cheap commands to characterize it so you can recommend an action:

```bash
git -C <repo> diff --stat | tail -5        # shape of the edits
git -C <repo> log --oneline -3             # what was last happening
git -C <repo> stash show stash@{0} --stat  # what a stash contains
```

Then classify: *ready to commit* (coherent, complete-looking), *needs review* (mixed concerns,
generated assets + code together), *probably discardable* (build artifacts, lockfile churn,
doc regen), or *mid-flight feature* (partial implementation). Say which and why in one line
each. Don't commit, push, or discard anything yourself — this skill reports; the user decides.

## Step 3 — Roadmap scan

Planned work lives in per-project docs under inconsistent names. Per repo, check for whichever
of these exist (skip repos with none):

- `ROADMAP.md`, `TODO.md`, `BACKLOG.md`, `PLAN*.md`, `MIGRATION.md`
- `CLAUDE.md` / `.claude/CLAUDE.md` / `AGENTS.md` — often ends with "current state" or
  "next steps" notes
- Any design doc the project treats as canonical (`GDD.md` for games, `masterplan.md`,
  `docs/*.md`): look for "Roadmap", "Planned", "Future", "Phase" sections

A cheap way to find them:

```bash
ls <repo>/*.md <repo>/docs/*.md 2>/dev/null
```

Extract only items that are **planned but not visibly started** — cross-reference against the
git scan: a roadmap item with a matching in-flight branch belongs in the pending-decisions
section ("mid-flight"), not the roadmap section. Note doc staleness when a "planned" item was
clearly already shipped.

If the workspace has a project-tracker MCP connected, it's a richer live source — use it as a
supplement, never a requirement; the skill must work from files alone.

## Step 4 — Build the infographic

The deliverable is a **single self-contained HTML infographic**, not a text report. Start from
`~/.claude/skills/sitrep/assets/template.html` — it contains the full stylesheet, section
skeleton, and a fully worked example card in comments. Copy its structure into a new file;
never edit the template in place. It needs no external resources, so it renders anywhere.

Fill the four sections with these visual encodings (all classes documented in the template):

- **Needs-a-decision cards**, ordered by work at risk (a 90-file dirty tree before a 1-commit
  doc push). Per card:
  - risk class `risk-high` / `risk-med` / `risk-low` → colored left stripe + chip
  - dirty-tree size → the `.meter` bar, width % ≈ `min(100, dirty + untracked)` — big
    half-finished work should *look* big
  - each local branch → a `.branch` lane in the mini git-graph, with the right dot + status
    chip: `cur` (checked out), `ahead` (▲n unpushed), `local` (no upstream — exists only on
    this disk), `gone` (upstream deleted), or synced
  - a repo parked on a non-main branch → `badge parked` on the header chip
  - stashes → the dashed `.stash` box (dashed = orphaned work attached to no branch)
  - unpushed commits → purple `.cdot` dots, one per commit
  - the one-line classification from Step 2 in `.what`, and the action in the `.rec` footer
- **Roadmap items** → one `.ritem` per item with the project tag and source doc; use
  `ritem midflight` (dashed purple) for items that turn out to be already started on a branch.
- **Quiet repos** → green `.chip` cloud, no detail.
- **Housekeeping** → `.house` list; `alert` class for data-loss risks (no-remote repos,
  orphaned stashes).

Fill the header stat blocks (repos scanned / need decision / unpushed commits / stashes /
clean) — they're the 5-second version of the whole report.

Save the file somewhere temporary (a session scratchpad if your harness has one, else `/tmp`),
named `sitrep-<YYYY-MM-DD>.html`, and present it — render it inline if your harness can,
otherwise `open <file>`. Then give a 3–6 line text summary in chat — top decisions first —
that stands alone if the HTML is never opened. If everything is clean, say so prominently and
let the roadmap lead the infographic.
