---
tema: licao-juiz-phantom-fix-em-arnes-de-teste · escopo: projeto · estado: atual · atualizado: 2026-10-05
id: licao-juiz-phantom-fix-em-arnes-de-teste
tipo: licao
origem: [.claude/juiz/anti_trapaca.py:245-250, commit ac626b95, e2e_log 2941, .claude/.ai/reports/2026-10-05-fecho-home-dinheiro.md]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: auto
---

# Lição — `PHANTOM_FIX` acusa em falso quando a avaria é do arnês de teste

- **Contexto:** o chão do Juiz (`python .claude/juiz/anti_trapaca.py --task fix`) dá
  **REJECT `PHANTOM_FIX`** sempre que uma tarefa de conserto só muda ficheiros de teste
  (`if task == "fix" and test_files and not code_files`, `anti_trapaca.py:245-250`). A regra
  existe para apanhar quem "conserta" mexendo no teste (ver `licao-asserts-weakened.md`).
- **A descoberta:** a regra não distingue **arnês** (arranque: `setUp`/`setUpAll`/inicialização)
  de **verificação** (`expect`). Quando a avaria é do próprio arnês — e não da app — o conserto
  certo é só em `test/`, e o Juiz acusa na mesma.
- **O que aconteceu (05/10/2026):** o conserto do iOS #166 (commit `ac626b95`) foi acrescentar
  4 linhas de arranque em cada um de 3 testes (`detectSessionInUri: false`; 12 inserções,
  0 remoções, 0 `expect` mudados) — ver `licao-supabase-em-teste-liga-app-links.md`. O Juiz deu
  REJECT `PHANTOM_FIX`.
- **Como se tratou (e é assim que se trata):**
  1. **Não** se trocou `--task` para fugir à regra.
  2. Mediu-se a causa (1 ligação ao canal `app_links` vs 0) e mostrou-se pelo diff que nenhuma
     verificação mudou.
  3. O REJECT ficou **escrito** como falso positivo no relatório
     (`.claude/.ai/reports/2026-10-05-fecho-home-dinheiro.md`, "iPhone #166") e no `e2e_log`
     (id 2941) — não escondido.
- **Regra a aplicar:** `PHANTOM_FIX` num conserto só de arnês não se contorna nem se cala:
  prova-se a causa com medição, prova-se pelo diff que 0 `expect`/asserções mudaram, e regista-se
  o REJECT como falso positivo com essa prova. Sem medição da causa, o REJECT vale.
- **Proposta (SÓ proposta, NÃO aplicada — mexer no Juiz é decisão do Danilo):** o
  `anti_trapaca.py` separar linhas de arranque (fora de `test(...)`/`testWidgets(...)`, sem
  `expect`) das de verificação antes de acusar `PHANTOM_FIX`, ou baixar para `REVIEW` quando o
  diff de teste tem 0 remoções e 0 `expect` tocados.
- **Evidência:** `git show ac626b95` (3 ficheiros, +12/−0, sem `expect`); `e2e_log` 2941
  (fluxo `fecho-home-dinheiro-2026-10-05`, passo `B3-ios-correccao`). Precedente de outro falso
  positivo do mesmo chão: `licao-anti-trapaca-base-stale.md`.

`estado: atual`
