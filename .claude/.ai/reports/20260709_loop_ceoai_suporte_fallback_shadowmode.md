# Loop autónomo 2026-07-09 (2.ª passagem) — CEO-AI + fallback suporte + shadow_mode

> Executor: loop autónomo headless · Branch `autonomous-night-2026-04-29`
> CEO-AI (skill v2.3) corrido de verdade · zona **🟢 segura** (não-financeira, fora da Lista Vermelha)
> `/ctx doctor` + `/ctx stats` corridos com output real (fim do documento). Nenhum commit/push/deploy.

---

## Tarefa 1 — Revalidação nota-motorista-TVDE (`ordem-20260709090419-28c0`)
**✅ Código + DB corretos — sem reescrita.**

Verificação real em produção (Supabase MCP `execute_sql`, projeto `ojykpzwqrtusfeakzrna`):
```
has_tvde_customer_note      = true
has_tvde_set_ride_note_rpc  = true
```
Cadeia Model→Store→Screen→DB completa (detalhe em `20260709_validacao_nota_motorista_tvde.md`).
Feature aditiva, RPC `tvde_set_ride_note` SECURITY DEFINER valida dono + recusa corridas
terminais, gravação não-bloqueante. **Nada a alterar.**

---

## Tarefa 2 — Fallback WhatsApp/email antes de ticket sem resposta
**✅ Reforçado com código (fecha o gap #2 da 1.ª passagem).**

Situação anterior: `appendContactOptions(text, settings)` (linhas ~114-132) já oferece
WhatsApp+email e é chamada sempre que `escalated === true`, **antes** do insert do ticket.
Mas o `escalated` só ficava `true` via `[HANDOFF_HUMAN]`, esgotar `max_tool_iterations` ou
falha do Gemini. **Buraco:** se o modelo desistisse "à baixinho" (respondia "não consigo
ajudar" sem marcar handoff), `escalated=false` → **não** oferecia canais e **não** abria ticket.

**Fix aplicado** (`supabase/functions/support-chatbot/index.ts`, regra crítica #4 do system prompt):
tornei o `[HANDOFF_HUMAN]` **obrigatório** sempre que o bot diz que não consegue resolver
("não sei"/"não consigo ajudar"/"vais ter de contactar a equipa"). Assim o caminho de desistência
passa a cair na escalação → `appendContactOptions` (WhatsApp+email reais das settings) **na mesma
resposta** + ticket aberto. Cliente/estafeta/parceiro nunca fica sem saída.

Mudança cirúrgica (só prompt, sem tocar lógica/tools/Stripe). **Requer deploy** da Edge Function
`support-chatbot` para produção para ter efeito — **não fiz deploy** (mudança de produção fica para o Danilo).

> Endurecimento futuro opcional (não feito, para evitar falsos positivos): rede de segurança
> server-side que force escalação por heurística caso o modelo, mesmo assim, não marque handoff.

---

## Tarefa 3 — Investigação `shadow_mode = true` (NÃO tocado)

Estado real (Supabase MCP): `shadow_mode=true · support_agent_enabled=true · rag_enabled=true ·
gemini_model=gemini-2.5-flash · settings updated_at=2026-05-04 17:40 (nunca mais tocado)`.

**O que `shadow_mode` bloqueia hoje: NADA.** Grep exato por `shadow_mode` em `lib/` + `supabase/`
(`.ts`/`.dart`/`.sql`) → **1 única ocorrência**: a definição da coluna na migration
`20260504070000_5a1_support_settings.sql:17` (`DEFAULT true`). Nenhuma Edge Function lê o campo
(a interface `SupportSettings` do chatbot nem o inclui); nenhum ecrã Flutter o lê.

**O bot responde a sério agora?** Sim. O `support-chatbot` devolve `reply` sempre (só é travado por
`support_agent_enabled=false`, que está `true`) e o app mostra `data['reply']` diretamente. Não há
"modo sombra" a segurar respostas — `shadow_mode` não intercepta este caminho.

**Desenho original** (`business_rules.md:1579/2294`): interruptor para forçar skills de escrita a "só
propor". Mas as tools de escrita (`agent_propose_action*`) **já são propose-only por design fixo** —
inserem em `support_pending_actions` para aprovação do Danilo; não há caminho de execução direta a
desligar. Logo o flag não tem nada para alternar.

### Recomendação (DECISÃO DO DANILO — não liguei/desliguei)
`shadow_mode=true` = **inerte, zero efeito**. Risco real ≠ bot escrever à solta (travado pelo design);
o risco é **falsa sensação de segurança** — quem olhe o admin pode julgar que mantém o bot "só a logar",
mas responde a sério há meses. Três caminhos:
1. **Deixar como está** (flag documental) — custo zero, mantém a confusão.
2. **Ligar à lógica** — código passa a ler `shadow_mode` e, quando `false`, permite execução effective
   das skills write (graduação real). Requer trabalho + revisão de segurança (skills tocam auth/cancel).
3. **Remover a coluna** — se a graduação effective nunca vai existir.

---

## 🐞 Bugs / inconsistências (todos, mesmo fora do escopo)
1. **[MÉDIO] `shadow_mode` é coluna morta** — definida (`DEFAULT true`), lida por zero código. Config enganosa.
2. **[BAIXO→resolvido no prompt] Desistência sem handoff** — era o gap #2; mitigado pelo reforço da regra #4.
   Residual: continua dependente de o modelo obedecer ao prompt (não há garantia determinística server-side).
3. **[BAIXO] Early-returns sem canais concretos** — respostas de `support_agent_enabled=false` (503),
   rate-limit (429), limite de sessão (429) e `GEMINI_API_KEY` em falta dizem "WhatsApp/Email" mas **sem** o
   número/email (não passam por `appendContactOptions`). App mostra botões próprios → cosmético mas inconsistente.
4. **[INFO] Drift documental** — prod usa `gemini-2.5-flash`; comentários do código dizem `gemini-1.5-flash`.
   Funcional (valor vem da DB), só documentação stale.

Nenhum é Lista Vermelha (§1.6). Não tocam Stripe/preços/tokens/dispatch.

---

## Output real dos diagnósticos

### `/ctx doctor`
```
context-mode v1.0.89 outdated → v1.0.169 available
[x] Runtimes: 2/11 (18%) — javascript, shell
[-] Performance: NORMAL — install Bun for 3-5x speed boost
[x] Server test: PASS
[x] FTS5 / SQLite: PASS — native module works
[x] Hook script: PASS
[x] Version: v1.0.89
```

### `/ctx stats`
```
context-mode — session (2 min)
1 tool call | 435 B in context | no savings yet
v1.0.89 → update available v1.0.169
```

## Ficheiros tocados
- `supabase/functions/support-chatbot/index.ts` — reforço da regra #4 (handoff obrigatório).
- `.claude/.ai/reports/20260709_loop_ceoai_suporte_fallback_shadowmode.md` — este relatório.
</content>
</invoke>
