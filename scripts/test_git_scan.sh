#!/bin/bash
# test_git_scan.sh — pins git_scan.sh's coverage on a throwaway workspace: repo "app"
# has a clean, synced main, but a side branch with unpushed commits checked out in a
# dirty linked worktree, a detached worktree holding a commit on no branch, and a
# worktree whose directory was deleted; repo "quiet" has nothing pending.
# Offline (the "remotes" are local bare repos). Exits non-zero on any miss.

scan="$(cd "$(dirname "$0")" && pwd)/git_scan.sh"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1   # no signing, hooks or templates
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

repo() {  # $1 = name: a workspace repo with one commit, pushed to a bare "remote"
  git init -q --bare "$tmp/remote/$1.git"
  git init -q -b main "$tmp/ws/$1"
  git -C "$tmp/ws/$1" commit -q --allow-empty -m init
  git -C "$tmp/ws/$1" remote add origin "$tmp/remote/$1.git"
  git -C "$tmp/ws/$1" push -q -u origin main
}
repo app
repo quiet
app="$tmp/ws/app"
echo v1 > "$app/f.txt"; git -C "$app" add f.txt; git -C "$app" commit -q -m f; git -C "$app" push -q

git -C "$app" worktree add -q -b feature "$tmp/wt/feature"
git -C "$tmp/wt/feature" commit -q --allow-empty -m "side 1"
git -C "$tmp/wt/feature" commit -q --allow-empty -m "side 2"
echo v2 > "$tmp/wt/feature/f.txt"; echo new > "$tmp/wt/feature/new.txt"   # 2 status entries

git -C "$app" worktree add -q --detach "$tmp/wt/detached"
git -C "$tmp/wt/detached" commit -q --allow-empty -m "on no branch"

git -C "$app" worktree add -q --detach "$tmp/wt/gone"
rm -rf "$tmp/wt/gone"

out=$(cd "$tmp" && "$scan" ws)   # a relative root: the scan cd's into each repo, so it must resolve it first
fail=0
expect() {  # $1 = what, $2 = extended regex the output must match
  if printf '%s\n' "$out" | grep -Eq -- "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
reject() {
  if printf '%s\n' "$out" | grep -Eq -- "$2"; then echo "FAIL $1"; fail=1; else echo "ok   $1"; fi
}

# summary row: DIRTY UNTRK AHEAD BEHIND STASH UNPUSHED WT WT-DIRTY
expect "app row: clean main; 3 unpushed (2 side + 1 detached); 3 worktrees, 2 dirty entries" \
       '^app +main +0 +0 +0 +0 +0 +3 +3 +2 '
expect "app row flags the prunable worktree"       '^app .*prunable:1'
expect "quiet row: nothing pending"                '^quiet +main +0 +0 +0 +0 +0 +0 +0 +0 '
expect "app gets a detail block despite a clean main" '^--- app ---$'
reject "quiet gets no detail block"                '^--- quiet ---$'
expect "side branch named with its unpushed count and worktree" \
       '^  \+ feature +no upstream +2 unpushed +→ .*/wt/feature$'
expect "dirty worktree: count and newest edit"     "^  feature +2 dirty · newest $(date +%Y-%m-%d) "
expect "detached worktree: its commit on no branch" '^  detached@[0-9a-f]{7} +clean .*1 commit\(s\) on no branch or remote'
expect "deleted worktree is prunable"              '^  detached@[0-9a-f]{7} +PRUNABLE: directory gone '
expect "temp-dir worktree flagged at risk"         'AT-RISK: temp dir'

# Git older than 2.36 rejects `worktree list -z`; the scan must fall back, not go blind.
mkdir "$tmp/oldgit"
cat > "$tmp/oldgit/git" <<EOF
#!/bin/bash
[ "\$1 \$2" = "worktree list" ] && case " \$* " in *" -z "*) exit 129 ;; esac
exec "$(command -v git)" "\$@"
EOF
chmod +x "$tmp/oldgit/git"
if [ "$(PATH="$tmp/oldgit:$PATH" "$scan" "$tmp/ws")" = "$out" ]; then
  echo "ok   same report from a git without worktree list -z"
else
  echo "FAIL same report from a git without worktree list -z"; fail=1
fi

exit $fail
