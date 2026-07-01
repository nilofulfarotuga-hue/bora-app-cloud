# 🛡️ Envelope de Segurança — o que torna o loop autónomo SEGURO (Fase 5)

> Isto é o que separa "autónomo seguro" de "incêndio". O loop (`maestro-autonomia`
> sobre a Edge Function `robot-b`) corre **dentro de 5 paredes**. Nenhuma parede sozinha
> chega; juntas fecham a caixa.

## As 5 paredes

1. **A TRAVA (Fase 1) — o dinheiro nunca é tocado.**
   Hooks `PreToolUse` + `permissions.deny` bloqueiam **de verdade** (exit 2 / deny) a edição de
   `pricing_service.dart`, `order_store.dart`, Edge Functions financeiras, DDL de dinheiro, e a
   própria Trava (`.claude/hooks/**`, `settings.json`). Nem `--dangerously-skip-permissions` fura.
   → Itens **N3 🔴** (dinheiro/Stripe/auth/dispatch) só podem ser **PROPOSTOS**. Aplicar = ato humano.

2. **O JUIZ (Fase 4) — nada é aceite sem passar, sem trapaça.**
   `juiz-revisor` corre o **chão determinístico** `.claude/juiz/anti_trapaca.py` (via git diff) SEMPRE
   primeiro (apanha teste apagado/enfraquecido/skip/valor trocado/conserto-fantasma) + 3 camadas
   (TestSprite · analyze+test+zonas+regras · rubrica UI). exit 2 → REJEITA. Rejeição → lição.

3. **OS TETOS — o custo é limitado.**
   Em `autonomy_goals`: `itens_por_ciclo` (1º run = **1**), `teto_max_turns`, `teto_orcamento_tokens`,
   `cadencia_min` (lento para começar). Caps duros do Robot B no SQL (10 auto-exec/ciclo, 15 abertas,
   benchmark obrigatório, dedup, não-repete rejeitadas 60d) — o robô **nunca** os altera.
   Ao atingir um teto → o loop **PARA e avisa**. Não foge.

4. **O HUMANO acima do L1 — nada de alto impacto sozinho.**
   O **dial** (`robot_b_auto_level1_enabled`) COMEÇA **cauteloso** (tudo passa por ti). Só 🟢 N1
   reversível pode auto-aplicar, e só se o dial permitir. N2 = 1 toque. N3 = ato humano.

5. **O KILL SWITCH — tu mandas.**
   Botão "PARAR TUDO" na Central escreve `platform_settings.robot_b_enabled=false`. O RPC
   `maestro_next_backlog_item` devolve `KILL_SWITCH_ATIVO` e o ciclo não arranca. Imediato.

## O handshake (limpo, sem Hermes)
A **fila (Supabase)** é o ponto de encontro. O loop (Claude Code) escreve propostas em
`robot_suggestions` + liga-as a `autonomy_backlog_items` (via MCP Supabase) e **lê** as aprovações;
o admin escreve a aprovação quando o Danilo toca; `notify-admin-urgent` avisa. Offline → aprova no admin.

## Invariante
> O loop só pode: **construir UI/admin não-financeira**, **propor** (nunca aplicar) dinheiro, e
> **registar** na Central. Tudo o resto está atrás de uma das 5 paredes.
