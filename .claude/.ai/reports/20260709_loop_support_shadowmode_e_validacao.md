# Loop autónomo 2026-07-09 — Validação TVDE + Fallback suporte + Investigação shadow_mode

> Executor: loop autónomo (headless) · Branch: `autonomous-night-2026-04-29`
> CEO-AI orchestrator corrido de verdade (skill `ceo-ai` v2.3). Nenhum commit/push.
> `shadow_mode` **NÃO** foi ligado/desligado (proibido pela tarefa) — só investigado.

---

## Tarefa 1 — Revalidação da nota do cliente para o MOTORISTA (TVDE)
**Ordem `ordem-20260709090419-28c0` · já aprovada · resultado: ✅ código já correto, sem reescrita.**

### Output real das verificações
- **DB (prod, via MCP execute_sql):**
  `has_customer_note_col = true` · `has_tvde_set_ride_note_rpc = true` ✅
- **`flutter analyze` (3 ficheiros tocados, corrido agora, 42.2s):** **0 erros**, 3 `info`
  **pré-existentes** — nenhum na feature da nota:
  - `use_build_context_synchronously` — `tvde_request_ride_screen.dart:233` e `:235`
  - `deprecated_member_use` (`activeColor`→`activeThumbColor`) — `tvde_request_ride_screen.dart:952`

### Conclusão
Cadeia Model→Store→Screen→DB completa e coerente (ver detalhe em
`20260709_validacao_nota_motorista_tvde.md`). Feature aditiva, não-financeira (🟢),
RPC `tvde_set_ride_note` SECURITY DEFINER valida dono + recusa corridas terminais,
gravação não-bloqueante. **Nada a alterar.**

---

## Tarefa 2 — Fallback WhatsApp/Email antes de ticket sem resposta
**Estado: ✅ já implementado e correto no working tree — validado, sem reescrita.**

`supabase/functions/support-chatbot/index.ts`:
- `appendContactOptions(text, settings)` (linhas 114-132) monta a oferta explícita a
  partir de `whatsapp_number` + `support_email` das settings, sem duplicar se já
  constarem do texto.
- É chamada **sempre que `escalated === true`** (linha 1019-1021), **ANTES** do insert
  do ticket (linha 1036). Ou seja: o cliente/estafeta/parceiro recebe na MESMA resposta
  "Se preferires falar já com uma pessoa: WhatsApp … ou email …. Também vou abrir um
  pedido de atendimento…". O ticket nunca fica aberto sem resposta imediata.
- Gatilhos de escalação cobertos: `[HANDOFF_HUMAN]`, `max_tool_iterations` esgotado,
  falha do Gemini, e ferramenta não-whitelisted.

**Não precisou de alteração de código** (regra cirúrgica: não reescrever o que já está certo).

---

## Tarefa 3 — Investigação `support_settings.shadow_mode = true`

### Estado real em produção (via MCP execute_sql)
```
shadow_mode=true · support_agent_enabled=true · rag_enabled=true
whatsapp_number=+351937501673 · support_email=boraappbora@gmail.com
gemini_model=gemini-2.5-flash · updated_at=2026-05-04 17:40 (nunca mais tocado)
```

### O que `shadow_mode` bloqueia HOJE: **NADA.**
Grep exato por `shadow_mode` em `lib/` + `supabase/` (`.ts`/`.dart`/`.sql`) só encontra
**uma** ocorrência: a definição da coluna na migration
`20260504070000_5a1_support_settings.sql:17` (`DEFAULT true`).
- **Nenhuma Edge Function lê `shadow_mode`** — a interface TS `SupportSettings` do
  `support-chatbot` nem sequer inclui o campo.
- **Nenhum ecrã Flutter lê `shadow_mode`** (os "shadow" em `lib/` são `BoxShadow` de UI).

### O bot está a responder a sério aos utilizadores AGORA?
**Sim.** O `support-chatbot` devolve `reply` sempre (só é bloqueado por
`support_agent_enabled=false`, que está `true`), e o app
(`support_chat_screen.dart:220,234`) mostra `data['reply']` diretamente como mensagem
do assistente. **Não há "modo sombra" a segurar respostas** — o utilizador vê a
resposta real. `shadow_mode` **não intercepta nada** deste caminho.

### O que `shadow_mode` foi DESENHADO para ser (docs)
`business_rules.md:1579` e `:2294`: *"skills write/cancel apenas propõem"* /
*"write_shadow vs effective"*. Ou seja: um interruptor global para forçar as skills de
escrita a **só propor** (shadow) em vez de **executar** (effective).
**Mas essa graduação nunca foi ligada:** as tools de escrita (`agent_propose_action*`)
**já são propose-only por design fixo** — chamam a RPC `agent_propose_action` que só
insere em `support_pending_actions` para o Danilo aprovar. Não existe caminho de
execução direta a desligar. Logo o flag não tem nada para alternar.

### Recomendação para o Danilo (DECISÃO TUA — não mexi)
`shadow_mode=true` hoje = **inerte / zero efeito**. O risco não é o bot escrever à
solta (isso está travado pelo design). O risco é **falsa sensação de segurança**: se
alguém no admin pensar que `shadow_mode` mantém o bot "só a logar", está enganado — o
bot responde a sério há meses. Três caminhos possíveis (escolhe tu):
1. **Deixar como está** (flag documental inofensivo) — custo zero, mas mantém a confusão.
2. **Ligar mesmo à lógica** — fazer o código ler `shadow_mode` e, quando `false`,
   permitir execução effective das skills write (graduação real). Requer trabalho +
   revisão de segurança (algumas skills tocam auth/cancel).
3. **Remover a coluna** — se a graduação effective nunca vai existir, tirar o campo
   evita a confusão.

**Não liguei nem desliguei nada.** Fica à tua decisão.

---

## 🐞 Bugs / inconsistências encontrados (todos, mesmo fora do escopo)

1. **[MÉDIO] `shadow_mode` é coluna morta** — definida (`DEFAULT true`) mas lida por
   zero código. Config enganosa: passa a ideia de proteção que não existe. (Tarefa 3.)
2. **[BAIXO] Gap de cobertura da Tarefa 2** — se o modelo responder texto tipo "não
   consigo ajudar" **sem** marcar `[HANDOFF_HUMAN]` e **sem** esgotar
   `max_tool_iterations`, `escalated` fica `false` → NÃO oferece WhatsApp/email e NÃO
   abre ticket. O fallback depende de o modelo marcar handoff. Mitigação futura possível:
   heurística server-side (ex.: detetar frases de desistência) ou instrução mais forte no
   system prompt para marcar sempre `[HANDOFF_HUMAN]` quando não resolve.
3. **[BAIXO] Early-returns não incluem os canais reais** — as respostas de
   `support_agent_enabled=false` (503), rate-limit diário (429), limite de sessão (429)
   e `GEMINI_API_KEY` em falta dizem "contacta WhatsApp/Email" mas **sem** o número/email
   concretos (não passam por `appendContactOptions`). O app mostra botões próprios, por
   isso é cosmético — mas inconsistente com o resto.
4. **[INFO] Drift documental do modelo** — prod usa `gemini_model=gemini-2.5-flash`, mas
   migration/comentários do código dizem `gemini-1.5-flash`. Funcional (o valor vem da DB),
   só documentação stale.

Nenhum destes é Lista Vermelha (§1.6) — não tocam Stripe/preços/tokens/dispatch.
