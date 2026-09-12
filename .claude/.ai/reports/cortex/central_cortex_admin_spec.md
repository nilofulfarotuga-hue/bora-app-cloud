# Central do Córtex — Spec do Painel Admin (Bloco 6 · PR-ready)

> **Estado: SPEC PRONTO, NÃO construído.** Implementar a Central toca no **app Flutter de produção**
> (ecrã admin novo) → é **mudança de app**, que por regra do Danilo se **PROPÕE** (fica PR-ready), não
> se faz autónomo. **Não é zona 🔴 de dinheiro** — não mexe em Stripe/pricing/tokens/RLS — por isso
> **não** precisa do "vai"; precisa só de tu correres o build quando quiseres. Data: 2026-07-08.

## 1. Princípio (guardrail herdado da Fase 5)
A Central do Córtex é o **cabeçalho** da caixa de aprovação que já existe
(`AdminRobotSuggestionsScreen` / `robot_suggestions`) — **não** um segundo inbox. Reusa a mesma
superfície de aprovação, o kill switch e o dial de confiança.

## 2. Pontos de UI (o que o Danilo precisa de ver/fazer)
1. **Ver o índice + log** do cérebro — `INDEX.md` (o quê existe) + `log.md` (quem/quando/de-que-lado escreveu).
2. **Fila de aprovação** — páginas `zona: vermelha` propostas + as *revisões* da contradiction engine
   (nightly). Cada item: aprovar / rejeitar (1 toque).
3. **Ver de que lado veio cada nota** — coluna repo|vps (fonte: `log.md`).
4. **Ver o Knowledge Debt** — `_debt.md` (páginas < 50% confiança / stale / NAO_VERIFICADO).
5. **Auditar autor** — filtrar por `claude` vs `hermes` vs `bibliotecario`, por data, por anel.
6. **Estado do sync repo↔VPS** — última sync, nº de notas, timestamp, saúde do bridge Tailscale.
7. **Kill switch / dial** — reusa `robot_b_enabled` + `robot_b_auto_level1_enabled` (Fase 5).

## 3. O problema de dados (e a solução recomendada)
O cérebro vive em **ficheiros no repo** (`.claude/.ai/knowledge/`), não na DB. O app admin lê da DB.
**Ponte recomendada (sem tocar zonas 🔴):**
- O `cortex_nightly.py` (ou um passo de CI) publica um **snapshot read-only** para uma tabela nova
  `cortex_status` (index + debt + log + fila) — **verde**, sem dados financeiros.
- Um ecrã `AdminCortexScreen` (read-only + aprovar/rejeitar fila) lê essa tabela via uma view/RPC admin
  já no padrão dos outros ecrãs admin. Aprovar/rejeitar escreve em `cortex_queue` (não no cérebro
  diretamente — o Bibliotecário aplica no repo no ciclo seguinte).

## 4. Paridade & próximos passos (para o Danilo)
- **Gatilho de paridade cumprido**: esta feature (Córtex) tem o seu ecrã admin **especificado**.
- **Para construir:** (a) migration `cortex_status`/`cortex_queue` (verde, não-financeira); (b) publisher
  no `cortex_nightly.py`; (c) `AdminCortexScreen` Flutter. Fica como PR/tarefa — corre quando quiseres.
- **Convocar** o agente `admin` para a implementação (dono do painel), com `backend-supabase` para as tabelas.
