# Skills do Bora App — Guia navegável

> Gerado por `generate-skills-readme` em 2026-05-30.
> **Não editar à mão** — regenerar. O `INDEX.md` curado é a referência rica.
> Total: **45 skills**.

Consulta obrigatória: **`bora-knowledge`** antes de qualquer ação.

## Foundation (1)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **bora-knowledge** | Referência viva do projeto BORA — design system, regras de negócio, categorias home, widgets, fluxos, DB, Edge Functions. | — | não |

## Validação (1)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **prompt-blindado-validator** | Camada de verificação obrigatória invocada pelo CEO-AI antes de cada tarefa — valida que o prompt recebido respeita as regras do Bora App (MODO PROTEC… | — | não |

## Onboarding (3)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **onboard-partner-pharmacy** | Onboarda farmácia/parafarmácia parceira a partir de pasta com info.yaml + produtos.csv + fotos. | `python scripts/insert_supabase.py --dir ".claude/.ai/onboard/wells-guarda"           # dr | sim |
| **onboard-partner-restaurant** | Onboarda restaurante parceiro a partir de pasta com info.yaml + produtos.csv + fotos cruas. | `# dry-run (default)` | sim |
| **onboard-partner-store** | Onboarda loja parceira (retail — electrónica, vestuário, casa, beleza, brinquedos) a partir de pasta com info.yaml + produtos.csv + fotos. | `python scripts/insert_supabase.py --dir ".claude/.ai/onboard/worten-guarda"            #  | sim |

## Auditoria (3)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **audit-driver-application** | Revê candidatura de estafeta (drivers.approval_status='pending') — valida NIF/IBAN/telefone/fotos, gera relatório PT-BR e aprova/rejeita com auditoria… | `python scripts/list_pending.py                                   # candidaturas pendentes | sim |
| **audit-partner-application** | Revê candidatura de parceiro (restaurants.approval_status='pending') — valida NIF/IBAN/business_hours/lat-lng/categoria/assets, gera relatório PT-BR e… | `python scripts/list_pending.py` | sim |
| **pre-launch-checklist** | Auditoria read-only de prontidão para lançamento — agrega contagens dos pontos críticos (drivers/restaurants pending, produtos sem preço/imagem, setti… | `python scripts/checklist.py                       # imprime + escreve _preview/checklist. | não |

## Operação (3)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **ban-or-reactivate-entity** | Bane ou reativa cliente, estafeta ou parceiro, com auditoria (quem/quando/razão/código). | `python scripts/history.py --type driver --id <uuid>` | sim |
| **force-driver-logout** | Força logout de um estafeta via Edge Fn admin-force-driver-logout (revoga sessões, limpa fcm_token, is_online=false, audita). | `python scripts/logout.py --driver-id <uuid> --reason "Suspeita de fraude"            # pr | não |
| **update-platform-setting** | Altera UMA chave de platform_settings com segurança — dry-run gera SQL + impacto + chaves dependentes; --commit aplica + admin_audit_log + cria nota A… | `python scripts/show_setting.py --key reservation_prepayment_cents` | sim |

## Operações (3)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **manage-promo-codes** | Cria/lista/desativa códigos promocionais via RPCs admin existentes (admin_create_promo_code / admin_list_promo_codes / admin_deactivate_promo_code). | `python scripts/list_promos.py --active-only` | sim |
| **notify-broadcast** | Envia notificação push em massa segmentada (all/clients/drivers/partners) via push_broadcasts + Edge Fn execute-broadcast. | `python scripts/preview_audience.py --segment clients          # conta destinatários` | sim |
| **reservation-ops** | Operações sobre reservas — listar (por restaurante/data/estado) e marcar chegada via RPC partner_mark_arrival (que aplica o desconto €2 internamente). | `python scripts/list_reservations.py --restaurant <id> --status confirmed --date 2026-05-3 | sim |

## Codegen (2)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **add-home-category** | Gera o diff (Modo A — patch generator) para adicionar uma 8ª categoria à home do cliente — gradient em app_colors.dart, tile em client_home_screen.dar… | `python scripts/generate_patch.py \` | não |
| **update-design-token** | Gera o diff (Modo A) para alterar um token de cor global em app_theme.dart/app_colors.dart + lista os ecrãs afetados (grep). | `python scripts/preview_token.py --token warning                       # valor atual + ecr | não |

## Dados / Mercados (3)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **dedupe-market-products** | Identifica e limpa produtos de mercado duplicados (mesmo search_normalized + mesma loja) com merge inteligente — mantém o mais completo, soft-delete d… | `python scripts/find_duplicates.py --store continente-guarda          # grupos com >1 → CS | sim |
| **sync-market-photos** | Preenche photo_url de produtos de mercado com needs_photo=true reutilizando fotos de uma loja "donor" (Mercadona, 100% fotos) por search_normalized —… | `python scripts/list_missing_photos.py                              # needs_photo por loja | sim |
| **weekly-market-prices** | Orquestra o update semanal de preços de mercado. | `python scripts/check_cron_health.py                                  # estado dos pg_cron | sim |

## Suporte (2)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **add-support-faq** | Adiciona uma FAQ ao RAG do support-chatbot (tabela support_knowledge_chunks) e dispara reindex-knowledge para gerar o embedding. | `python scripts/list_faqs.py                                        # chunks FAQ/knowledge | sim |
| **add-support-skill** | Cria um playbook (skill markdown) para o agente de suporte (tabela support_skills). | `python scripts/scaffold_skill.py --name check_reservation --category reservations \` | sim |

## QA (2)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **audit-protected-zones** | Meta-skill de segurança read-only — verifica que as zonas protegidas continuam intactas (pricing_service, dispatch, bora_tokens triggers, Stripe, fich… | `python scripts/audit.py --save-baseline      # 1ª vez: grava baseline (hashes/contagens a | não |
| **smoke-test-critical-paths** | Verifica (read-only / health) os caminhos críticos do Bora sem afetar produção — Edge Functions alcançáveis (OPTIONS), RPCs críticos presentes, realti… | `python scripts/smoke.py            # relatório PT-BR + _preview/smoke.md` | não |

## DevOps (4)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **backup-restore-table** | Backup (read-only, sempre seguro) e restore (UPSERT) de tabelas-chave para JSON em .claude/.ai/backups/. | `python scripts/backup.py --table platform_settings              # → .claude/.ai/backups/{ | sim |
| **deploy-edge-function** | Deploy seguro de uma Edge Function — mostra o diff (local vs versão deployed) ANTES, preserva verify_jwt, e bloqueia funções protegidas (dispatch-engi… | `python scripts/diff_function.py --name notify-driver        # diff local vs deployed` | sim |
| **generate-release-notes** | Gera notas de versão (PT-PT) a partir dos commits git desde o último tag/versão — agrupa por tipo (feat/fix/chore/docs), e inclui secção amigável "Par… | `python scripts/release_notes.py                       # desde o último tag → RELEASE_NOTE | não |
| **seed-demo-data** | Cria dados de demonstração isolados e reversíveis (clientes + pedidos DEMO_) para testes. | `python scripts/seed.py --clients 3 --orders 5             # dry-run (plano)` | sim |

## Design (2)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **audit-orange-rule** | Verifica a regra "1 elemento laranja por ecrã" em lib/screens/ — conta usos de laranja (AppColors.accent/secondary, #F97316/#FB923C/#EA580C) por fiche… | `python scripts/audit.py                      # relatório de todos os ecrãs + _preview/ora | não |
| **migrate-screen-to-design** | Re-skin de 1 ecrã para o design system (MODO A patch generator) — substitui hex de marca/semânticos por AppColors tokens, sinaliza AppBar custom→BoraS… | `python scripts/analyze_screen.py --screen cart_screen          # tabela de mudanças propo | não |

## Financeiro (3)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **audit-ledger-entries** | Forensics financeiras read-only sobre ledger_entries — deteta entries órfãs (sem order), duplicados, sinais inesperados (earning negativo, commission… | `python scripts/audit.py                 # todo o ledger` | não |
| **refund-assistant** | SHADOW MODE — prepara uma PROPOSTA de refund para aprovação humana. | `python scripts/prepare_refund.py --order-id <id>` | não |
| **run-weekly-payouts** | Gera o relatório de payouts semanais (estafetas + parceiros) somando ledger_entries do período — net a pagar por entidade + CSV. | `python scripts/payouts.py                       # últimos 7 dias` | sim |

## Consolidação (meta) (3)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **generate-skills-readme** | Gera o README.md mestre das skills, agrupado por categoria (metadata.type), a partir do frontmatter + corpo de cada SKILL.md — nome, o que faz, comand… | `python scripts/gen_readme.py            # dry-run → _preview/README.generated.md` | sim |
| **skills-doctor** | Meta-skill read-only que valida todas as skills em .claude/skills/ — frontmatter (name/description/type), name == pasta, depends_on bora-knowledge, py… | `python scripts/check.py                      # valida todas` | sim |
| **update-bora-knowledge** | Deteta drift entre a skill bora-knowledge e a realidade do repo (Edge Functions em supabase/functions vs 08-edge-functions.md; pastas de skill vs INDE… | `# 1) Detetar drift (read-only)` | não |

## Outros (10)

| Skill | O que faz | Comando exemplo | Dry-run |
|-------|-----------|-----------------|---------|
| **ask-knowledge-base** | Skill do Robô B (Claude Code) para responder perguntas técnicas registadas pelo Robô A (chatbot Bora App) na tabela `robot_crosstalk` (a_to_b/pending)… | `deno run --allow-env --allow-read --allow-net \` | não |
| **auto-rules-sync** | > | `git diff HEAD~1 HEAD --name-only` | não |
| **category-mapper-v2** | > | — | sim |
| **ceo-ai** | > | — | não |
| **driver-earnings-validator** | Valida driver_earnings de um pedido contra fórmula pricing_service. | — | não |
| **market-data-cleaner** | > | — | sim |
| **market-data-sync** | > | — | não |
| **storage-bucket-validator** | Audita estado de um bucket Supabase Storage e as suas policies RLS. | — | não |
| **storeshopping-v2-debugger** | Diagnostica um pedido storeShopping V2 não-parceiro completo. | — | não |
| **taxonomy-mapper** | > | `supabase migration up  # ou via MCP apply_migration` | não |

