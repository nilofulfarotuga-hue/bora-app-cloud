---
tema: indice-cerebro · escopo: projeto · estado: atual · atualizado: 2026-07-06
---

# 🧠 CÉREBRO DO BORA — Índice

> **Entry point.** TODO agente lê este ficheiro **antes** de trabalhar e carrega **só** os
> ficheiros do seu tema — nunca o Cérebro inteiro. Só o agente **`bibliotecario-cerebro`**
> escreve aqui (ver `PROTOCOLO.md`).
>
> **Invariante:** este índice e cada ficheiro carregam **abaixo do limite de leitura (~24 KB)**.
> Se um ficheiro crescer, o Bibliotecário parte-o por sub-tema.

## Como está organizado

```
knowledge/
  INDEX.md            ← estás aqui (índice minúsculo)
  PROTOCOLO.md        ← como ler/escrever no Cérebro
  permanente/         ← factos que valem no tempo
    semantica/        ← regras & factos (o que É verdade)
    episodica/        ← história (o que ACONTECEU)
    procedural/       ← como-fazer & lições (como se FAZ)
  sessao/             ← memória de trabalho efémera (gitignored)
  _arquivo/           ← histórico bruto + mapas de migração (nunca apagar)
```

## Frescura & escopo (ler antes de confiar num facto)
- **Escopo** por bloco: `escopo: projeto` (partilhado) ou `escopo: agente:<nome>`.
- **Estado** por facto: `estado: atual` ou `estado: superado (por X, data)`.
  Um facto `superado` fica na história para contexto — **não** o apliques; segue o `atual`.

---

## 📚 PERMANENTE

### Semântica — regras & factos
| Tema | Ficheiro | Quando ler |
|---|---|---|
| Regras de negócio (ponteiro p/ canónico 192KB) | `permanente/semantica/business-rules.md` | pricing, tokens, fees, dispatch, refund, cancelamento |
| Pricing / tokens / comissões (resumo) | `permanente/semantica/pricing.md` | qualquer cálculo de dinheiro (só leitura) |
| DNA — filosofia de decisão do Danilo | `permanente/semantica/dna.md` | dúvida de "como o dono decidiria" |
| 🔴 Zonas protegidas (a Trava, Fase 1) | `permanente/semantica/zonas-protegidas.md` | **antes de editar código/DB** |
| Backend map (tabelas/RPCs/edge fns/triggers/RLS) | `permanente/semantica/backend-map.md` | mexer no Supabase; "o que existe" |
| Vertical LIMPEZA (regras, pagamento, crons, telas, caveats) | `permanente/semantica/vertical-limpeza.md` | qualquer trabalho na limpeza doméstica |
| Vertical MULTIPAPEL (duplo-papel estafeta⇄limpeza, ponte) | `permanente/semantica/multipapel.md` | 2.º papel sem conta nova; my_roles_summary; badges/prefill |
| Exército (elenco de agentes) | `permanente/semantica/exercito.md` | escolher/delegar a um agente |
| 📜 Constituição (10 princípios, índice) | `permanente/semantica/constituicao.md` | topo de contrato de agente; dúvida de princípio |
| 🔁 Loop Registry (5 perguntas + cores + economy) | `permanente/semantica/loops.md` | criar/alterar qualquer loop; watchdog |
| 📸 Estado Vivo (foto da empresa — reescrito) | `permanente/semantica/estado-vivo.md` | precisar da "foto da empresa" |
| 🛎️ Hermes Concierge (rotas + limites) | `permanente/semantica/hermes-concierge.md` | mexer no Hermes/Telegram; governança |
| 🎨 Brand-brain (marca, personas, anti-slop) | `permanente/semantica/brand-brain.md` | qualquer peça de marketing |
| Mapa de fluxos (índice + cliente/estafeta/parceiro/anti-regressão) | `permanente/semantica/mapa-de-fluxos.md` | testes E2E; entender um fluxo ponta-a-ponta |

### Episódica — história
| Tema | Ficheiro | Quando ler |
|---|---|---|
| Bugs resolvidos (sagas + causa-raiz) | `permanente/episodica/bugs-resolvidos.md` | antes de "corrigir" algo já corrigido |
| Decisões arquiteturais | `permanente/episodica/decisoes.md` | refactors, mudanças de estrutura |
| Auditoria 360° (5 P0 + placar admin) | `permanente/episodica/auditoria-360.md` | prioridades de produto/gaps |

### Procedural — como-fazer & lições
| Tema | Ficheiro | Quando ler |
|---|---|---|
| Convenções (ambiente, git, MCP, Windows) | `permanente/procedural/convencoes.md` | build/push/MCP/encoding |
| 🧮 Decision Brain (checklist de score 0–16) | `permanente/procedural/decision-brain.md` | CEO-AI/maestro antes de decisão não-trivial |
| Lições (cresce com o tempo) | `permanente/procedural/licoes/` | evitar repetir erros |
| ↳ CRLF em scripts `.sh` (Windows) | `permanente/procedural/licoes/licao-crlf-sh-eol.md` | criar hooks/scripts bash |
| ↳ Não enfraquecer asserções (Juiz) | `permanente/procedural/licoes/licao-asserts-weakened.md` | consertar teste/código sob teste |
| ↳ anti_trapaca em branch longa: usar `--base` da sessão | `permanente/procedural/licoes/licao-anti-trapaca-base-stale.md` | correr o Juiz nesta branch |
| ↳ `context.watch` em getter chamado por callback → crash | `permanente/procedural/licoes/licao-context-watch-getter.md` | Flutter/Provider: getters vs callbacks |
| ↳ Policy de Storage não pode ler `auth.users` (usar claim JWT) | `permanente/procedural/licoes/licao-storage-policy-auth-users.md` | criar/editar policies de storage.objects; upload 400 opaco |

---

## 🗂️ Fontes canónicas (fora do Cérebro, referenciadas por ele)
| Fonte | Ficheiro | Papel |
|---|---|---|
| Regras de negócio (verdade dos números) | `.claude/.ai/business_rules.md` (192 KB) | ler por secção, nunca inteiro |
| Trava determinística (Fase 1) | `.claude/HOOKS.md` | o que está bloqueado e porquê |
| Auditoria 360° (relatório completo) | `audits/AUDITORIA_PARIDADE_360_2026-07-01.md` | detalhe por superfície |
| Memória partilhada dos agentes | `.claude/agents/agent-memory.md` | regras de comportamento dos agentes |
| Skill CEO-AI (orquestrador) | `.claude/skills/ceo-ai/SKILL.md` | identidade, prioridades, workflow |

## 🔗 Espelho Obsidian
O vault (`C:\Users\danil\Desktop\Bora`) é espelhado pelo agente **`obsidian-sync`** (unidirecional,
SHA256). **Não** construir sync nova aqui.
