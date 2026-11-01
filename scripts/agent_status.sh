#!/usr/bin/env bash
# Prints the live state an agent needs at session start. Read-only, no network required
# (a fetch is attempted but failure is ignored). Safe to run any time.
cd "$(dirname "$0")/.." || exit 0
git fetch origin --quiet 2>/dev/null || true
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
echo "=== UrduMeaning session start ==="
echo "Branch: $branch @ $(git rev-parse --short HEAD)"
echo "Behind origin/master: $(git rev-list --count HEAD..origin/master 2>/dev/null || echo '?')  Ahead: $(git rev-list --count origin/master..HEAD 2>/dev/null || echo '?')"
echo "Uncommitted files: $(git status --porcelain | wc -l | tr -d ' ')"
echo
echo "--- Recent commits on master ---"
git log origin/master -8 --format='%h %ad %s' --date=short 2>/dev/null
echo
echo "--- Other remote branches (possible unmerged work) ---"
git branch -r 2>/dev/null | grep -v -E 'HEAD|origin/master$' | sed 's/^ */  /'
echo
status_commit=$(git log -1 --format=%H -- docs/STATUS.md 2>/dev/null)
if [ -n "$status_commit" ]; then
  behind=$(git rev-list --count "$status_commit"..HEAD -- api web infrastructure .github scripts 2>/dev/null)
  echo "docs/STATUS.md last updated: $(git log -1 --format='%ad (%h)' --date=short -- docs/STATUS.md)"
  echo "Code/infra commits since then: ${behind:-?}  $([ "${behind:-0}" -gt 0 ] && echo '<-- STATUS.md may be stale; verify against git log before trusting it')"
fi
echo
echo "NEXT: read AGENTS.md -> docs/STATUS.md. Update docs/STATUS.md before you finish."
