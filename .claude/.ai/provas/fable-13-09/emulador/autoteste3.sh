#!/usr/bin/env bash
# Portao do Juiz na arvore unida com origin/autonomous (Codex PR #2) + autoteste no emulador.
cd /c/BoraLocal/projetosflutter/bora_app || exit 9
L=.claude/.ai/provas/fable-13-09/emulador
echo "INICIO3 $(date +%H:%M:%S) HEAD=$(git rev-parse --short HEAD)" > "$L/autoteste3.log"

flutter analyze > "$L/analyze_merged2.log" 2>&1
echo "ANALYZE_EXIT=$? $(grep -cE '^ +error' "$L/analyze_merged2.log") erros; $(tail -1 "$L/analyze_merged2.log")" >> "$L/autoteste3.log"

flutter test > "$L/test_merged2.log" 2>&1
echo "TEST_EXIT=$? $(tail -1 "$L/test_merged2.log")" >> "$L/autoteste3.log"

bash "$L/autoteste2.sh"
cat "$L/autoteste2.log" >> "$L/autoteste3.log"
echo "FIM3 $(date +%H:%M:%S)" >> "$L/autoteste3.log"
