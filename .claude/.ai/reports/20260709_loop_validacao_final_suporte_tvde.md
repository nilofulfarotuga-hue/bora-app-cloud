# Loop autónomo 2026-07-09 (passagem final) — Validação TVDE + Fallback suporte + shadow_mode

> Executor: loop autónomo headless · Branch `autonomous-night-2026-04-29`
> CEO-AI orchestrator (skill v2.3) corrido de verdade · zona **🟢 verde** (nada da Lista Vermelha §1.6)
> Verificação em produção via Supabase MCP (`ojykpzwqrtusfeakzrna`) · `/ctx doctor` + `/ctx stats` reais no fim
> Nenhum commit · nenhum push · nenhum deploy · `shadow_mode` NÃO tocado

---

## Tarefa 1 — Revalidação nota-motorista-TVDE (`ordem-20260709090419-28c0`)
**✅ Código + DB corretos em produção — sem reescrita (mudança cirúrgica confirmada).**

Verificação real agora (Supabase MCP `execute_sql`):
```
has_customer_note_col      = 1   (tvde_rides.customer_note existe)
has_set_ride_note_rpc      = 1   (RPC tvde_set_ride_note existe)
```
Cadeia Model→Store→Screen→DB completa (detalhe em `20260709_validacao_nota_motorista_tvde.md`):
widget partilhado `customer_note_field.dart`, `tvde_store.setRideNote` (falha silenciosa,
não-bloqueante), RPC SECURITY DEFINER valida dono + recusa corridas terminais. Feature aditiva,
🟢 não-financeira. **Nada a alterar.**

---

## Tarefa 2 — Fallback WhatsApp/email antes de ticket sem resposta
**✅ Implementado e verificado no working tree (não reescrito — só confirmado + auditado o fluxo).**

`supabase/functions/support-chatbot/index.ts` (diff no working tree, 34 linhas +):
- **`appendContactOptions(text, settings)`** (linhas 110-132) monta a oferta explícita a partir de
  `whatsapp_number` + `support_email` das settings; não duplica se já constarem do texto.
- Chamada em **linha 1024** sempre que `escalated === true`, **ANTES** do insert do ticket (linha 1040).
  Ordem verificada linha-a-linha: escala → oferece canais na MESMA resposta → só depois abre ticket.
- **Gatilhos de `escalated`** cobertos: `max_tool_iterations` esgotado (1011), falha do Gemini (1015),
  `[HANDOFF_HUMAN]` (1018), ferramenta não-whitelisted (839).
- **Regra crítica #4 do system prompt reforçada** (linhas 440-448): o `[HANDOFF_HUMAN]` passa a ser
  **obrigatório** sempre que o bot diz que não resolve ("não sei"/"não consigo ajudar"/"vais ter de
  contactar a equipa"). Fecha o caminho de "desistência à baixinho" → agora cai na escalação →
  oferece WhatsApp+email + abre atendimento. Cliente/estafeta/parceiro nunca fica sem saída.

Valores reais em produção que vão na oferta: WhatsApp `+351937501673` · email `boraappbora@gmail.com`.

> ⚠️ **Pendência (não é dinheiro, é produção):** a alteração só tem efeito **após deploy** da Edge
> Function `support-chatbot`. **Não fiz deploy** — deploy a produção é ação de produção; deixo ao Danilo.
> Comando: `supabase functions deploy support-chatbot` (ou skill `deploy-edge-function --commit`).

---

## Tarefa 3 — Investigação `support_settings.shadow_mode = true` (NÃO tocado)

Estado real em produção (MCP):
```
shadow_mode=true · support_agent_enabled=true · rag_enabled=true · max_tool_iterations=5
gemini_model=gemini-2.5-flash · whatsapp=+351937501673 · email=boraappbora@gmail.com
updated_at=2026-05-04 17:40 (nunca mais tocado)
```

**O que `shadow_mode` bloqueia hoje: NADA.** Grep exato em TODO o repo (`*.ts`/`*.dart`/`*.sql`)
→ **1 única ocorrência**: a definição da coluna em `20260504070000_5a1_support_settings.sql:17`
(`DEFAULT true`). **Zero leituras** — nenhuma Edge Function (a interface TS `SupportSettings` nem
inclui o campo), nenhum ecrã Flutter.

**O bot responde a sério agora?** **Sim.** O `support-chatbot` devolve `reply` sempre (só é travado
por `support_agent_enabled=false`, que está `true`) e o app mostra `data['reply']` direto. `shadow_mode`
não intercepta este caminho — não há "modo sombra" a segurar respostas.

**Desenho original** (`business_rules.md:1579/2294`): interruptor para forçar skills de escrita a "só
propor". Mas as tools de escrita (`agent_propose_action*`) **já são propose-only por design fixo** —
inserem em `support_pending_actions` para aprovação. O flag não tem nada para alternar.

### 🟡 DECISÃO DO DANILO — não liguei nem desliguei
`shadow_mode=true` = **inerte, zero efeito**. O risco NÃO é o bot escrever à solta (travado por design);
é **falsa sensação de segurança** — quem olhe o admin pode julgar que o bot só loga, mas responde a
sério há meses. Três caminhos:
1. **Deixar como está** (flag documental) — custo zero, mantém a confusão.
2. **Ligar à lógica** — código lê `shadow_mode`; quando `false`, permite execução effective das skills
   write (graduação real). Requer trabalho + revisão de segurança (skills tocam auth/cancel).
3. **Remover a coluna** — se a graduação effective nunca vai existir.

---

## 🐞 Bugs / inconsistências (todos, mesmo fora do escopo)
1. **[MÉDIO] `shadow_mode` é coluna morta** — definida (`DEFAULT true`), lida por zero código. Config enganosa.
2. **[BAIXO] Residual da Tarefa 2** — o fallback continua a depender de o modelo obedecer ao prompt (marcar
   `[HANDOFF_HUMAN]`). Não há garantia determinística server-side. Endurecimento opcional futuro: rede de
   segurança por heurística — **não feito de propósito** para não gerar falsos positivos (oferecer canais +
   abrir ticket quando o bot afinal resolveu).
3. **[BAIXO] Early-returns sem canais concretos** — respostas de `support_agent_enabled=false` (503),
   rate-limit (429), limite de sessão (429) e `GEMINI_API_KEY` em falta dizem "WhatsApp/Email" mas **sem**
   o número/email (não passam por `appendContactOptions`). App mostra botões próprios → cosmético mas inconsistente.
4. **[INFO] Drift documental** — prod usa `gemini-2.5-flash`; comentários do código dizem `gemini-1.5-flash`.
   Funcional (valor vem da DB), só documentação stale.

Nenhum é Lista Vermelha (§1.6). Não tocam Stripe/preços/tokens/dispatch.

---

## Output real dos diagnósticos

### `/ctx doctor`
```
⚠️ context-mode v1.0.89 outdated → v1.0.169 available
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
- `supabase/functions/support-chatbot/index.ts` — (working tree, de passagens anteriores) `appendContactOptions`
  + reforço da regra #4. Auditado/confirmado nesta passagem; **sem nova edição** (código já correto).
- `.claude/.ai/reports/20260709_loop_validacao_final_suporte_tvde.md` — este relatório.
