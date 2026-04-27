#!/usr/bin/env bash
# auto-rules-sync notification hook
# Runs on PostToolUse:Bash. Reads tool_input from stdin, checks if it was a
# git commit, and if the commit touched business-rule files, prints a
# one-line suggestion to invoke /auto-rules-sync.
# NEVER blocks, NEVER modifies files. Read-only + stdout.

set +e

cmd=$(python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

case "$cmd" in
  *"git commit"*)
    files=$(git diff HEAD~1 HEAD --name-only 2>/dev/null \
      | grep -E '^(CLAUDE[.]md|PROJECT_CONTEXT[.]md|lib/models/.+[.]dart)$' \
      | paste -sd ' ' -)
    if [ -n "$files" ]; then
      echo "[auto-rules-sync] Business rule files changed in last commit: ${files}- Consider invoking /auto-rules-sync to update CEO-AI + Obsidian."
    fi
    ;;
esac

exit 0
