# Sistema de Agentes — Bora App

> Path: `bora_app/.claude/agents/` · Criado: Lote 1 (2026-06-22)

## SKILL vs AGENTE — a distinção

- **SKILL** = uma **ferramenta** especializada e determinística (ex.: `category-mapper-v2`,
  `backup-restore-table`). Faz uma coisa bem. Vive em `.claude/skills/`.
- **AGENTE** = um **orquestrador** com identidade, objetivo, limites e memória. **Chama skills**
  para executar; nunca duplica a lógica delas. Vive aqui em `.claude/agents/`.

> **Regra de ouro:** Agentes orquestram skills. O **CEO-AI é o dispatcher master** — escolhe que
> agente responde a cada tarefa. Todos os agentes leem `agent-memory.md` no arranque.

## Agentes disponíveis (elenco canónico — Fase 3, 2026-07-01)

> Proteção: 🟢 zona segura · 🟡 sensível (cautela extra) · 🔴 dinheiro → **PROPOSE-ONLY** (a Trava
> bloqueia a edição; o agente LÊ e PROPÕE, o Danilo aprova).

### Domínio (conhecem uma fatia do produto)
| Agente | 🛡️ | Propósito |
|---|---|---|
| **cliente** | 🟢 | Browse, carrinho, checkout (UI), rastreio, avaliações, tokens (UI). |
| **estafeta-motorista** | 🟡 | App estafeta + TVDE: online gate, oferta/aceitar, PIN, docs, veículo. |
| **parceiro-restaurante** | 🟡 | Menus, aceitar pedido, comissão 10+5+5% (leitura), falta de item, onboarding. |
| **parceiro-servicos** | 🟢 | Barbearia/agendamentos + Reservas Pro; sinal €3, desconto chegada €2. |
| **mercados** | 🟢 | Mercados NÃO-PARCEIRO, crawlers (só categorias estáveis), markup 15% runtime, storeShopping V2. |
| **favores** | 🟢 | Errands: storeShopping/levar/enviar, OCR talão, orçamento €6/€10, consentimento over-budget. |
| **pagamentos-wallet** | 🔴 | Stripe/MBWay/tokens/refund/split/wallet — **PROPOSE-ONLY**. |
| **dispatch** | 🔴 | dispatch_engine, matching, stacking, TTL/claim — monitor + **PROPOSE-ONLY**. |
| **admin** | 🟢 | Painel PT-BR, autoridade total + guardião da **paridade** (feature → ecrã admin). |
| **notificacoes** | 🟢 | FCM cliente/estafeta/parceiro, heads-up/FGS/CallKit, consent GDPR. |
| **chat-suporte** | 🟢 | Chatbot (Robot A), tickets, knowledge base RAG. Robot A/B intocáveis. |

### Ofício (uma habilidade aplicada em tudo)
| Agente | 🛡️ | Propósito |
|---|---|---|
| **flutter-ui** | 🟢 | Design system (Verde `#16A34A`/Laranja `#F97316`/Inter). Nunca altera foto real. |
| **backend-supabase** | 🟡 | RPCs, migrations, RLS, Edge Functions (dry-run+backup+rollback; bloqueia $). |
| **seguranca** | 🟡 | RLS, secrets, buckets, SECURITY DEFINER. SEC-1/SEC-2. Nunca RLS financeira. |
| **dados-sql** | 🟢 | Queries, correção de preço/dados de produto, dashboards. Só SELECT em $. |
| **devops-ci** | 🟡 | `build_android.yml`, versionCode (nunca manual), git push, keystore, Play Internal. |
| **compliance-pt** | 🟡 | TVDE (IMT/DL 45/2018), KYC, GDPR. Cargo novo do buraco da auditoria 360°. |
| **pesquisa-concorrencia** | 🟢 | Benchmark Glovo/Uber/Bolt/iFood. Copia o mercado, não inventa. |
| **catalogo-visual** | 🟢 | Imagens de categoria de mercado (nano-banana). Coordena com `mercados`. |
| **marketing-push** | 🟢 | Push de campanhas/promos + banners. Aprovação > 50 users; máx 2/dia. |
| **obsidian-sync** | 🟢 | Espelho unidirecional do Cérebro no Obsidian (SHA256). |

### Guardião do Cérebro (Fase 2)
| Agente | 🛡️ | Propósito |
|---|---|---|
| **bibliotecario-cerebro** | 🟡 | O **único** que escreve no Cérebro (8-checagens, dedup, marca superado). |

### O Juiz (Fase 4 — gate anti-trapaça)
| Agente | 🛡️ | Propósito |
|---|---|---|
| **juiz-revisor** | 🟡 | **Gate obrigatório**: nenhum trabalho é aceite sem passar as 3 camadas, com o chão determinístico (`git diff`, `.claude/juiz/anti_trapaca.py`) a correr **sempre primeiro**. Rejeição → lição → Bibliotecário. Ver `.claude/juiz/README.md`. |

**Braços do Juiz** (absorvidos da Fase 3 — já não são agentes soltos):
| Agente | Papel sob o Juiz |
|---|---|
| **e2e-test-builder** | Braço de **geração** de teste — cria `integration_test/` para features novas, que o TestSprite corre. |
| **checkout-fixer** | **Fixer** especializado que o Juiz invoca em **regressão de checkout** (propõe patch; dinheiro espera "vai"). |

### O Maestro (Fase 5 — o loop autónomo)
| Agente | 🛡️ | Propósito |
|---|---|---|
| **maestro-autonomia** | 🟡 | Dono do **ciclo do loop** autónomo (paridade admin). Pega item do backlog → **classifica nível (1/2/3)** × zonas-protegidas → convoca esquadrão pequeno → **Juiz obrigatório** → posta na **Central** (`AdminRobotSuggestionsScreen` — superfície única). Evolui `robot-b`. Dial começa cauteloso; kill switch "PARAR TUDO". Ver `docs/fase5/ENVELOPE_SEGURANCA.md`. |

## Zonas protegidas (todos os agentes)
`dispatch_engine` · `pricing_service.dart` · triggers financeiros · Stripe webhook ·
RLS em `orders`/`wallets`/`ledger_entries`/`bora_tokens`. Robot A e Robot B são **intocáveis**.

## Como adicionar um novo agente
1. Copia `template.md` → `meu-agente.md`.
2. Preenche o contrato em 4 partes (Objetivo / Limites / Ferramentas / Protocolo) + as restantes
   secções (Identidade, Formato, Memória, **Admin Panel Check obrigatório**).
3. Adiciona uma linha à tabela acima **e** à secção "## Sistema de Agentes" do `CLAUDE.md`.
4. Frontmatter: `name` (== nome do ficheiro) e `description` obrigatórios. Omite `tools` se o
   agente precisar de MCP (herda tudo); declara `tools` explícitos se for só ficheiros/git.
