# sitrep — a workspace situation report, as an infographic

A [Claude Code](https://claude.com/claude-code) skill that scans every git repo in your
workspace and renders what's pending as a **single self-contained HTML page** — risk-striped
cards, dirty-tree meters, branch lanes, stash flags — instead of a wall of terminal text.

It answers two questions: *what did I leave hanging, and what decision does each item need?*
and *what's next on each project's roadmap?*

It is **read-only**. It reports; you decide. Nothing is committed, pushed, or discarded.

## Install

Clone it into your skills directory:

```bash
git clone https://github.com/0n1-Studios/sitrep.git ~/.claude/skills/sitrep
chmod +x ~/.claude/skills/sitrep/scripts/git_scan.sh
```

Or take the zip, if you'd rather not have a git remote in there:

```bash
curl -O https://0n1studios.com/downloads/sitrep-skill.zip
unzip sitrep-skill.zip -d ~/.claude/skills/
chmod +x ~/.claude/skills/sitrep/scripts/git_scan.sh
```

Then ask for it in Claude Code:

```
/sitrep
```

…or just say "what's pending across my projects?" — the description is written to trigger on
the vaguer phrasings too ("where did I leave off", "anything uncommitted?", "state of my
projects").

## Configure

The scan defaults to `~/Development` as the workspace root. Point it elsewhere either way:

```bash
~/.claude/skills/sitrep/scripts/git_scan.sh ~/src
```

…or edit `ROOT` and `SKIP_DIRS` at the top of `scripts/git_scan.sh`.

## What's in here

| File | What it is |
|---|---|
| `SKILL.md` | The skill itself — the four-step procedure and the visual encoding rules |
| `scripts/git_scan.sh` | Read-only git survey; prints a summary table + per-repo detail |
| `assets/template.html` | The infographic template — full stylesheet, section skeleton, one worked example card |

The template is deliberately dependency-free: no CDN, no fonts, no scripts. The generated
report opens anywhere, forever, offline.

## Why HTML and not markdown

Because when you're running eight to ten agent sessions, *you* are the bottleneck — and a
linear text report makes you read at exactly the speed you're already too tired to sustain.
Size, colour and position are perceived pre-attentively; prose is not. The point of the
infographic is that a repo in trouble should *look* like a repo in trouble before you've read
a single word.

Written up here: <https://0n1studios.com/journal/drain>

## Licence

MIT. Do whatever you like with it.

Built at [0n1 Studios](https://0n1studios.com).
