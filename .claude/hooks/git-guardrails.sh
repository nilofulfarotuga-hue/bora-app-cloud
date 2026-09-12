#!/bin/bash
# Atalho: sem "git" no comando, nem se paga o arranque do python.
INPUT=$(cat)
case "$INPUT" in *git*) ;; *) exit 0 ;; esac
printf "%s" "$INPUT" | python "$(dirname "$0")/git-guardrails.py"
