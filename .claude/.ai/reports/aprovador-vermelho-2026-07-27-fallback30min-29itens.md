---
tema: aprovador-vermelho-corrida · data: 2026-07-27 · gatilho: FALLBACK_30MIN (29 itens, item mais antigo parado 8122+min)
---

# 🚦 Aprovador-Vermelho — Triagem da fila 🔴 (2026-07-27, corrida ~17:29 UTC)

## Resumo executivo
- **29 itens** em `robot_suggestions.status='nova'` (count confirmado por SELECT direto, MCP Supabase `ojykpzwqrtusfeakzrna`).
- **0 itens genuinamente novos** desde a corrida anterior do mesmo dia (~17:22:09 UTC): os 29 IDs, `dedup_key`, `created_at` e evidência são **byte-a-byte idênticos** aos já triados nas 2 corridas anteriores de hoje (~16:57 UTC e ~17:22 UTC — ver `admin_audit_log`).
- **0 Balde A** nesta fila (os 3 itens Balde A vistos hoje — `9391dfac…`, `a950e75e…`, `a68ff603…` — já saíram de `nova` em corridas anteriores, status `aprovada-emerson`).
- **29 Balde B**, todos reconfirmação sem novidade. Registados em `admin_audit_log` (ação `robot_suggestion_baldeB_reconfirmado`, 29 linhas). **Telegram suprimido** (gap ~7 min desde o último aviso real, muito abaixo do limiar anti-spam ~60 min).
- Nenhuma escrita em `reservations`/`orders`/`platform_settings` financeiros/zona protegida. Nenhuma mudança de `status` em `robot_suggestions` (todos continuam `nova`, aguardando decisão do Danilo). Única escrita: 29 INSERTs em `admin_audit_log` (auditoria de roteamento).

## Balde A (recomendo aprovar) — nenhum item nesta corrida
Não há itens Balde A na fila `nova` atual. Os 3 já vistos hoje foram auto-aprovados em corridas anteriores (auto-Balde-A ligado):
- `9391dfac-00ac-4eaf-b5d9-1e1732bf1dd9` — `infra:otimizar-cron-jobs-marcacoes-drivers` (mislabel do gerador; conteúdo real = `_cron_check_orphan_orders` + `_cron_check_ghost_drivers`, só leitura).
- `a950e75e-c03a-4682-8762-0e20ab414c5d` — `catalogo:backlog-produtos-revisao` (flag de revisão, sem escrita em preço/visibilidade).
- `a68ff603-d5c4-48b8-8755-47a91f5f0e78` — `catalogo:produtos-preco-suspeito-revisao` (idem, "preço" no título é falso-positivo do filtro T3).

## Balde B (dinheiro real / impacto de negócio sem prova de segurança) — 29 itens, por família

**Família `marcacoes:ajustar-no-show-rate-threshold` (base + v2..v17) — 18 itens**
IDs: `7b91d830`, `aca99667`(v2), `bb244433`(v3), `8b04e458`(v4), `1eb83b51`(v5), `38072232`(v6), `a90f7a0e`(v7), `a65c6c52`(v8), `1633f4d1`(v9), `4e17a34e`(v10), `55a734bd`(v11), `b662d4d5`(v12), `9e605549`(v13), `e1a6d24d`(v14), `c8f799f4`(v15), `42ec3820`(v16), `251649a7`(v17).
Faz: ajustar limiar de taxa de no-show para marcações, propondo a setting `reservation_no_show_rate_threshold` (que **não existe** — distinta da real `reservation_no_show_threshold_count=3`). Risco: mexe (indiretamente) em política de retenção de depósito em no-show — dinheiro real. Evidência idêntica (`{"total":3,"no_show":1}`) reciclada em todas as 18 variantes — **bug de dedupe do gerador de sugestões**, não é 18 problemas distintos.
⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico. *(reconfirmação; sem novidade desde a última triagem)*

**Família `marcacoes:resolver-marcacoes-pendentes-orfas` (base + v2/v3 + `2efe0a26901c`) + `marcacoes:resolver-marcacoes-orfas` — 5 itens**
IDs: `b8627b62`, `11f97170`(v2), `c3d1cd8b`(v3), `c1caf38d`(`2efe0a26901c`), `7cf1a393` (nível 3).
Faz: mecanismo de cancelamento/reatribuição automática de reserva paga; cita 2 reservas (`7c61663d…`, `091ac601…`) já confirmadas **stale** (0 linhas em `reservations`). Risco: automatiza escrita sobre reserva com `prepayment_pi` Stripe real, sem regra de refund definida.
⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico. *(reconfirmação; sem novidade)*

**`marcacoes:liberar-slots-orfãos-ttl`** (`1efa3e60`) e **`marcacoes:ajustar-politica-no-show`** (`c068f901`, propõe `deposit_required_threshold:0.5`) — 2 itens já conhecidos, dinheiro real (depósito/no-show). Reconfirmação sem novidade.

**`infra:otimizar-queries-lentas-cron`** (`13ec022c`) — item agrupado: além das 2 funções Balde A (`_cron_check_orphan_orders`/`_cron_check_ghost_drivers`), inclui `_appointment_cron_auto_no_show` (escreve `deposit_status`). Regra de item agrupado: **item inteiro cai em Balde B**, mesmo com 2/3 partes isoladamente seguras. Reconfirmação sem novidade.

**Subpadrão `catalogo:*ocultar` — 3 itens**: `3a6d6cd0` (sem-foto, 59 produtos), `048e7340` (sem-foto v2), `222e0b2b` (sem-categoria, 1546 produtos). Faz: `UPDATE is_available=false` em massa — escrita direta, diferente do padrão Balde A já validado ("marcar para revisão", sem escrita). Risco: impacto de negócio (produtos deixam de poder ser comprados), sem precedente de auto-aprovação para "ocultar". Balde B por cautela/precedente.

**`catalogo:produtos-sem-categoria-revisao-ocultar`** (`b454e9bc`) — funde os 2 subpadrões antagônicos catalogo (revisão=A vs ocultar=B); texto final propõe ocultação de 1546 produtos. Já tinha sido surfaçado às 17:22:09 UTC (só 7 min antes desta corrida); reconfirmado sem novidade.

## Telegram — suprimido nesta corrida
Último aviso real: `robot_suggestion_baldeB_surfaced`/`approved_baldeA` às **17:22:09 UTC**; lote anterior às **16:57:45 UTC**. Esta corrida (~17:29 UTC) fica a **~7 min** do aviso mais recente — muito abaixo do limiar anti-spam (~60 min) e sem nenhum item novo para justificar reenvio. Registei os 29 reconfirmações em `admin_audit_log` com `telegram_enviado:false` + motivo explícito.

## Achado sobre a causa do backlog (29 itens, item mais antigo 8122+ min)
1. **Não é um ataque nem uma família nova de dinheiro** — é o mesmo backlog já diagnosticado nas 2 corridas anteriores de hoje: bug de **dedupe quebrado no gerador de sugestões** (evolution-engine/robot-b), que reciclou evidência idêntica/stale em variantes `-v2`...`-v17` em vez de checar o estado atual antes de criar mais uma linha. Fora do mandato de roteamento deste agente corrigir — candidato a ordem para `maestro-autonomia`.
2. **Sinal reforçado sobre a anomalia de backoff do script de gatilho** (`permanente/procedural/aprovador-vermelho-anomalia-backoff-script.md`): confirmei por `grep` direto em `.claude/scripts/hermes-aprovador-vermelho.sh` que o repo **ainda só tem `STALE_MIN=30` fixo**, sem `MAX_BACKOFF_MIN`/`STATE_FORCE_N`/`STATE_FORCE_COUNT` (o fix de `e4444a4` continua revertido desde `f169f96`, como já documentado em 2026-07-24). O gap de **~7 min** entre esta corrida e a anterior (17:22:09 UTC) é ainda mais chamativo que os gaps de 5-12 min já vistos em 2026-07-20/24 — está **abaixo até do piso não corrigido de 30 min** entre disparos forçados, o que sugere que o `STATE_FORCE` (cooldown) pode não estar a persistir entre execuções do cron VPS (`*/10min`), ou que múltiplas invocações estão a correr em paralelo/fora de sincronia. Fora do escopo deste agente alterar infra da VPS — reportado para quem cuidar do loop (`maestro-autonomia` ou revisão manual do script + do cron VPS).
3. **Teto `robot_b_max_open_suggestions=30`** — fila em 29, a **1 item do teto**. Combinado com o bug de dedupe (#1), o próximo disparo do gerador pode colidir com o teto. Não é urgente agora (nada quebrou), mas vale o Danilo saber que os dois problemas (dedupe quebrado + teto quase cheio) estão a caminho de se cruzar.

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado) — confirmado antes desta corrida. Sem efeito nesta corrida (0 itens Balde A na fila).

## Rastro
- 29 INSERTs em `admin_audit_log` (`action='robot_suggestion_baldeB_reconfirmado'`, `entity_type='robot_suggestion'`, `telegram_enviado:false`), `created_at` ~2026-07-27 17:2x-17:3x UTC.
- Zero UPDATE em `robot_suggestions` (todos continuam `status='nova'`).
- Zero escrita em zona protegida (`reservations`, `orders`, `platform_settings` financeiros, dispatch, pricing).

## Ver também (memória)
- `.claude/.ai/knowledge/permanente/procedural/aprovador-vermelho-triagem.md`
- `.claude/.ai/knowledge/permanente/procedural/aprovador-vermelho-historico-corridas.md`
- `.claude/.ai/knowledge/permanente/procedural/aprovador-vermelho-anomalia-backoff-script.md`
