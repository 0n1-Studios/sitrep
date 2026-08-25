#!/bin/bash
# git_scan.sh — survey every git repo under a root dir (default ~/Development)
# Emits: a summary table, then a detail block for every repo with pending work.
# "Pending work" = dirty files, untracked files, stashes, or commits not on a remote.

ROOT="${1:-$HOME/Development}"
SKIP_DIRS="go|_archive|secrets"

printf "%-22s %-28s %5s %5s %6s %7s %6s  %-12s %s\n" \
  "REPO" "BRANCH" "DIRTY" "UNTRK" "AHEAD" "BEHIND" "STASH" "LAST-COMMIT" "REMOTE"
echo "---------------------------------------------------------------------------------------------------------"

PENDING=()

for d in "$ROOT"/*/; do
  name=$(basename "$d")
  echo "$name" | grep -qE "^($SKIP_DIRS)$" && continue
  [ -d "$d/.git" ] || continue

  cd "$d" || continue
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "DETACHED@$(git rev-parse --short HEAD 2>/dev/null)")
  dirty=$(git status --porcelain 2>/dev/null | grep -cv '^??')
  untracked=$(git status --porcelain 2>/dev/null | grep -c '^??')
  stashes=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
  last=$(git log -1 --format='%cs' 2>/dev/null || echo "-")

  if git remote get-url origin >/dev/null 2>&1; then
    remote="origin"
    # ahead/behind of current branch vs upstream (if upstream exists)
    ab=$(git rev-list --left-right --count @{upstream}...HEAD 2>/dev/null)
    if [ -n "$ab" ]; then
      behind=$(echo "$ab" | awk '{print $1}')
      ahead=$(echo "$ab" | awk '{print $2}')
    else
      # no upstream for this branch: count commits not on any remote branch
      ahead=$(git rev-list HEAD --not --remotes --count 2>/dev/null || echo "?")
      behind="-"
      remote="origin (no upstream)"
    fi
  else
    remote="NONE"
    ahead=$(git rev-list HEAD --count 2>/dev/null)  # everything is local-only
    behind="-"
  fi

  printf "%-22s %-28s %5s %5s %6s %7s %6s  %-12s %s\n" \
    "$name" "$branch" "$dirty" "$untracked" "$ahead" "$behind" "$stashes" "$last" "$remote"

  if [ "${dirty:-0}" -gt 0 ] || [ "${untracked:-0}" -gt 0 ] || [ "${stashes:-0}" -gt 0 ] || { [ "$ahead" != "0" ] && [ "$ahead" != "?" ] && [ "$remote" != "NONE" ]; }; then
    PENDING+=("$d")
  fi
done

echo ""
echo "========================= DETAIL: repos with pending work ========================="
for d in "${PENDING[@]}"; do
  name=$(basename "$d")
  cd "$d" || continue
  echo ""
  echo "--- $name ---"
  changed=$(git status --porcelain | head -25)
  [ -n "$changed" ] && { echo "[changes]"; echo "$changed"; }
  total=$(git status --porcelain | wc -l | tr -d ' ')
  [ "$total" -gt 25 ] && echo "... and $((total - 25)) more"
  unpushed=$(git log --branches --not --remotes --oneline 2>/dev/null | head -10)
  [ -n "$unpushed" ] && { echo "[unpushed commits]"; echo "$unpushed"; }
  stash=$(git stash list | head -5)
  [ -n "$stash" ] && { echo "[stashes]"; echo "$stash"; }
  # local branches and their sync state — surfaces unpushed side branches
  echo "[branches]"
  # * = checked out here; > ahead / < behind / = synced with upstream; blank = no upstream (local-only)
  git for-each-ref refs/heads --format='%(HEAD) %(refname:short) %(upstream:trackshort)' | head -10 | sed 's/^/  /'
done
