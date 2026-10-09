#!/bin/bash
# git_scan.sh — survey every git repo under a root dir (default ~/Development)
# Emits: a summary table (one row per repo, then a TOTAL row), then a detail block
# for every repo with pending work. "Pending work" is any of:
#   - the main checkout has dirty or untracked files, stashes, or is ahead of upstream;
#   - a commit is on no remote, on ANY local branch or detached worktree HEAD — side
#     branches count even when main is clean and synced;
#   - a linked worktree (`git worktree list`) is dirty, sits in a temp dir the OS
#     clears on reboot, or is prunable (its checkout is gone).
# Read-only and offline: no fetch, and GIT_OPTIONAL_LOCKS=0 stops `git status` from
# taking index.lock in a worktree another session may be committing in.
# Portable: /bin/bash 3.2 (stock macOS, so no associative arrays), BSD or GNU stat
# and date. After changing it, run scripts/test_git_scan.sh (a throwaway fixture workspace).

ROOT="${1:-$HOME/Development}"
ROOT=$(CDPATH= cd -- "$ROOT" && pwd) || exit 1   # absolute: the loop cd's into each repo
SKIP_DIRS="go|_archive|secrets"                  # top-level dirs never scanned (regex alternation)
# Scope = every top-level dir with a .git, minus SKIP_DIRS. Linked worktrees have a
# .git FILE, so they are reached through their repo's `git worktree list` wherever
# they live, never swept as repos of their own.

export GIT_OPTIONAL_LOCKS=0
US=$'\x1f'   # field separator: never in a ref name, and not IFS whitespace, so empty fields survive

gt0() { [ "${1:-0}" -gt 0 ] 2>/dev/null; }   # false for 0, "-", "?" and empty
trim() { echo "${1%"${1##*[! ]}"}"; }        # drop the padding an empty last column leaves

# Epoch mtimes of the NUL-separated paths on stdin. GNU stat reads -f as "file system"
# and still exits 0, so probe for GNU's -c rather than trying BSD's -f first.
if stat -c %Y / >/dev/null 2>&1; then
  mtimes() { xargs -0 stat -c %Y 2>/dev/null; }
else
  mtimes() { xargs -0 stat -f %m 2>/dev/null; }
fi

# Newest mtime among a checkout's changed and untracked files ("YYYY-MM-DD HH:MM");
# empty when every change is a deletion. date -r is BSD, date -d @ is GNU.
newest_edit() {
  local t
  t=$(cd "$1" 2>/dev/null && { git diff --name-only -z HEAD 2>/dev/null
                               git ls-files --others --exclude-standard -z 2>/dev/null; } |
      mtimes | sort -rn | head -1)
  [ -n "$t" ] && { date -r "$t" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$t" '+%Y-%m-%d %H:%M'; }
}

# Worktree path for display: repo-relative inside the repo, ~-relative under $HOME.
short_path() {
  local p=${1#"$main_wt"/}
  case $p in "$HOME"/*) p="~${p#"$HOME"}" ;; esac
  printf '%s' "$p"
}

# One `git worktree list --porcelain` record, fields already in wt_*. Entry 1 is the
# main checkout; every later one is a linked worktree and gets a detail line.
wt_record() {
  local ref state flags n ne orphan why=""
  wt_seen=$((wt_seen + 1))
  [ -z "$wt_ref" ] && detached_heads="$detached_heads $wt_head"   # commits here may be on no branch
  if [ "$wt_seen" -eq 1 ]; then main_wt=$wt_path; return; fi

  wt_n=$((wt_n + 1))
  ref=${wt_ref:-"detached@${wt_head:0:7}"}
  flags=""
  case $wt_path in   # temp dirs the OS empties: a worktree there loses its files
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*)
      wt_tmp=$((wt_tmp + 1)); flags="$flags  AT-RISK: temp dir, cleared on reboot" ;;
  esac
  if [ ! -d "$wt_path" ]; then why="directory gone"
  elif [ ! -e "$wt_path/.git" ]; then why=".git link gone"   # directory left, no longer a checkout
  elif [ -n "$wt_prunable" ]; then why=$wt_prunable
  fi
  if [ -n "$why" ]; then
    wt_prune=$((wt_prune + 1)); state="PRUNABLE: $why"
  else
    n=$(git -C "$wt_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if gt0 "$n"; then
      wt_dirty=$((wt_dirty + n)); ne=$(newest_edit "$wt_path")
      state="$n dirty${ne:+ · newest $ne}"
    else
      state="clean"
    fi
  fi
  if [ -z "$wt_ref" ]; then
    orphan=$(git rev-list --count "$wt_head" --not --branches --remotes 2>/dev/null)
    gt0 "$orphan" && flags="$flags  $orphan commit(s) on no branch or remote"
  fi
  [ -n "$wt_locked" ] && flags="$flags  locked: $wt_locked"
  wt_lines="$wt_lines$(printf '  %-34s %-40s %s%s' "$ref" "$state" "$(short_path "$wt_path")" "$flags")"$'\n'
}

# Detail block for the current repo; runs in a $(...) subshell, reading the loop's vars.
repo_detail() {
  local total ne here br wtp sync n mark others=0 gone=0
  echo ""
  echo "--- $name ---"
  if [ -n "$status" ]; then
    total=$(printf '%s\n' "$status" | wc -l | tr -d ' ')
    ne=$(newest_edit .)
    echo "[changes]  $total in the main checkout${ne:+ · newest edit $ne}"
    printf '%s\n' "$status" | head -25
    [ "$total" -gt 25 ] && echo "... and $((total - 25)) more"
  fi
  if gt0 "$unpushed"; then
    echo "[unpushed commits]  $unpushed on no remote, all branches + detached HEADs (newest 10)"
    git log --branches $detached_heads --not --remotes --oneline 2>/dev/null | head -10
  fi
  if gt0 "$stashes"; then
    echo "[stashes]"
    printf '%s\n' "$stash_list" | head -5
  fi
  # Every branch holding unpushed commits or checked out somewhere; the rest collapse
  # to one count. Sync is vs the branch's own upstream as of the last fetch.
  echo "[branches]  * checked out here · + checked out in a linked worktree · sync vs upstream · unpushed = on no remote"
  while IFS="$US" read -r here br wtp up sync; do
    n=0
    if gt0 "$unpushed"; then
      case $up:$sync in
        refs/remotes/*:synced | refs/remotes/*:behind*) ;;   # its remote upstream holds every commit
        *) n=$(git rev-list --count "refs/heads/$br" --not --remotes 2>/dev/null) ;;
      esac
    fi
    if [ "$here" = "*" ]; then mark="*"; wtp=""
    elif [ -n "$wtp" ]; then mark="+"
    elif gt0 "$n"; then mark=" "
    else
      others=$((others + 1)); [ "$sync" = "gone" ] && gone=$((gone + 1)); continue
    fi
    gt0 "$n" && n="$n unpushed" || n=""
    trim "$(printf '  %s %-40s %-14s %-14s %s' "$mark" "$br" "$sync" "$n" "${wtp:+→ $(short_path "$wtp")}")"
  done < <(git for-each-ref refs/heads --format="%(HEAD)$US%(refname:short)$US%(worktreepath)$US%(upstream)$US%(if)%(upstream)%(then)%(if)%(upstream:track)%(then)%(upstream:track,nobracket)%(else)synced%(end)%(else)no upstream%(end)")
  if [ "$others" -gt 0 ]; then
    printf '  … %s more, every commit on a remote' "$others"
    [ "$gone" -gt 0 ] && printf ' (%s with upstream gone)' "$gone"
    echo ""
  fi
  if [ "$wt_n" -gt 0 ]; then
    printf '[worktrees]  %s linked · %s dirty entries' "$wt_n" "$wt_dirty"
    gt0 "$wt_tmp" && printf ' · %s in a temp dir' "$wt_tmp"
    gt0 "$wt_prune" && printf ' · %s prunable' "$wt_prune"
    echo ""
    printf '%s' "$wt_lines"
  fi
}

row() {
  trim "$(printf "%-18s %-28s %5s %5s %5s %6s %5s %8s %3s %8s  %-11s  %-20s %s" "$@")"
}
row REPO BRANCH DIRTY UNTRK AHEAD BEHIND STASH UNPUSHED WT WT-DIRTY LAST-COMMIT REMOTE WT-FLAGS
echo "-------------------------------------------------------------------------------------------------------------------------------------------"

repos=0 T_DIRTY=0 T_UNTRK=0 T_STASH=0 T_UNPUSHED=0 T_WT=0 T_WTDIRTY=0 T_TMP=0 T_PRUNE=0
DETAILS=""

for d in "$ROOT"/*/; do
  name=$(basename "$d")
  echo "$name" | grep -qE "^($SKIP_DIRS)$" && continue
  [ -d "$d/.git" ] || continue

  cd "$d" || continue
  repos=$((repos + 1))
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "DETACHED@$(git rev-parse --short HEAD 2>/dev/null)")
  status=$(git status --porcelain 2>/dev/null)
  dirty=$(printf '%s\n' "$status" | grep -c '^[^?]')
  untracked=$(printf '%s\n' "$status" | grep -c '^??')
  stash_list=$(git stash list 2>/dev/null)
  stashes=$(printf '%s' "$stash_list" | grep -c .)
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

  # Walk every worktree; this also collects the detached HEADs the unpushed count needs.
  # Git older than 2.36 has no -z: fall back to its newline records, same fields.
  wt_seen=0 wt_n=0 wt_dirty=0 wt_tmp=0 wt_prune=0 wt_lines="" detached_heads="" main_wt=""
  wt_path="" wt_head="" wt_ref="" wt_locked="" wt_prunable=""
  while IFS= read -r -d '' f; do
    case $f in
      "")           wt_record   # an empty field ends a record
                    wt_path="" wt_head="" wt_ref="" wt_locked="" wt_prunable="" ;;
      "worktree "*) wt_path=${f#worktree } ;;
      "HEAD "*)     wt_head=${f#HEAD } ;;
      "branch "*)   wt_ref=${f#branch refs/heads/} ;;
      locked*)      wt_locked=${f#locked}; wt_locked=${wt_locked# }; wt_locked=${wt_locked:-"(no reason given)"} ;;
      prunable*)    wt_prunable=${f#prunable}; wt_prunable=${wt_prunable# }; wt_prunable=${wt_prunable:-"git says prunable"} ;;
    esac
  done < <(git worktree list --porcelain -z 2>/dev/null ||
           git worktree list --porcelain 2>/dev/null | tr '\n' '\0')
  [ -n "$wt_path" ] && wt_record   # an older git may not end the last record

  # Commits on no remote across ALL local branches and detached HEADs; with no remote
  # at all, that is every commit.
  unpushed=$(git rev-list --count --branches $detached_heads --not --remotes 2>/dev/null)
  [ -n "$unpushed" ] || unpushed="?"

  wt_flags=""
  gt0 "$wt_tmp" && wt_flags="tmp:$wt_tmp"
  gt0 "$wt_prune" && wt_flags="${wt_flags:+$wt_flags }prunable:$wt_prune"
  row "$name" "$branch" "$dirty" "$untracked" "$ahead" "$behind" "$stashes" "$unpushed" \
      "$wt_n" "$wt_dirty" "$last" "$remote" "$wt_flags"

  T_DIRTY=$((T_DIRTY + dirty)); T_UNTRK=$((T_UNTRK + untracked)); T_STASH=$((T_STASH + stashes))
  gt0 "$unpushed" && T_UNPUSHED=$((T_UNPUSHED + unpushed))
  T_WT=$((T_WT + wt_n)); T_WTDIRTY=$((T_WTDIRTY + wt_dirty))
  T_TMP=$((T_TMP + wt_tmp)); T_PRUNE=$((T_PRUNE + wt_prune))

  if gt0 "$dirty" || gt0 "$untracked" || gt0 "$stashes" || gt0 "$ahead" || gt0 "$unpushed" ||
     gt0 "$wt_dirty" || gt0 "$wt_tmp" || gt0 "$wt_prune"; then
    DETAILS="$DETAILS$(repo_detail)"$'\n'
  fi
done

echo "-------------------------------------------------------------------------------------------------------------------------------------------"
row "TOTAL ($repos repos)" "" "$T_DIRTY" "$T_UNTRK" "" "" "$T_STASH" "$T_UNPUSHED" "$T_WT" "$T_WTDIRTY" "" "" \
    "tmp:$T_TMP prunable:$T_PRUNE"
echo ""
echo "AHEAD/BEHIND: checked-out branch vs its upstream. UNPUSHED: commits on no remote, across every local"
echo "branch and detached worktree HEAD (every commit, when there is no remote). WT: linked worktrees;"
echo "WT-DIRTY: their status entries; WT-FLAGS: tmp = in a temp dir the OS clears on reboot,"
echo "prunable = the worktree's checkout is gone."

echo ""
echo "========================= DETAIL: repos with pending work ========================="
printf '%s' "$DETAILS"
