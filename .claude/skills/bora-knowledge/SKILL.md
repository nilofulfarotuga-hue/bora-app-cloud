---
name: bora-knowledge
description: Referência viva do projeto BORA — design system, regras de negócio, categorias home, widgets, fluxos, DB, Edge Functions. CONSULTA OBRIGATÓRIA por todas as outras skills antes de agir. Atualiza apenas esta skill quando algo mudar no projeto — as filhas leem daqui.
metadata:
  type: foundation
  version: 1.0.0
  consulted_by: [onboard-partner-restaurant, onboard-partner-store, onboard-partner-pharmacy, add-home-category, update-design-token]
---

# bora-knowledge — Memória viva do projeto

> Mapa/índice canónico do Bora App. **NÃO duplica** os ~82 ficheiros detalhados
> em `.claude/.ai/knowledge/` (na raiz do workspace, fora do repo git `bora_app`).
> Cada ficheiro aqui acrescenta o que faltava (design Fase 3-4, widgets novos,
> Edge Functions atuais via MCP) e termina com **"## Fontes adicionais"** a
> apontar para o(s) documento(s) detalhado(s).

## Quando usar
Sempre antes de qualquer ação. Outras skills **DEVEM** ler os ficheiros
relevantes em `knowledge/` antes de planear mudanças.

## Protocolo de leitura (obrigatório)
1. Ler `knowledge/01-design-system.md` SEMPRE antes de UI changes
2. Ler `knowledge/05-business-rules.md` SEMPRE antes de pricing/fees changes
3. Ler `knowledge/10-protected-zones.md` SEMPRE antes de qualquer edit
4. Receitas em `knowledge/12-recipes.md` cobrem operações comuns
5. Se MCP (Supabase) contradisser este conteúdo → **MCP ganha**; atualizar este ficheiro

## Localização dos artefactos
- Esta skill: `bora_app/.claude/skills/bora-knowledge/` (git tracked, branch `autonomous-night-2026-04-29`)
- Knowledge detalhado: `.claude/.ai/knowledge/` (raiz workspace — NÃO git tracked)
- Regras no código: `bora_app/lib/config/`, `bora_app/.claude/.ai/business_rules.md`

## Índice dos 12 ficheiros
| # | Ficheiro | 1-liner |
|---|----------|---------|
| 01 | [design-system](knowledge/01-design-system.md) | Paleta #16A34A/#065F46/#F97316, Inter, gradients, sombras, raios, regra "1 laranja/ecrã", tokens AppColors |
| 02 | [home-categories](knowledge/02-home-categories.md) | 7 categorias atuais + receita "adicionar 8ª categoria" |
| 03 | [navigation](knowledge/03-navigation.md) | BoraBottomNavV2 4 tabs + padrão `_RootNavigator` |
| 04 | [widgets-bora](knowledge/04-widgets-bora.md) | 14 widgets `bora/`: quando usar, construtores, params |
| 05 | [business-rules](knowledge/05-business-rules.md) | Comissões 10+5+5%, taxas estafeta, €40 cash, sacos, cancelamento, reservas, tokens |
| 06 | [flows](knowledge/06-flows.md) | Pedido cliente, dispatch-engine, parceiro, takeaway, reservas, storeShopping v2 |
| 07 | [database-key-tables](knowledge/07-database-key-tables.md) | Colunas-chave + defaults de 10 tabelas (via MCP) |
| 08 | [edge-functions](knowledge/08-edge-functions.md) | 44 Edge Functions ativas (via MCP); payloads das principais |
| 09 | [platform-settings](knowledge/09-platform-settings.md) | 67 settings runtime (via MCP); como ler/alterar |
| 10 | [protected-zones](knowledge/10-protected-zones.md) | Dispatch, pricing, triggers, tokens, Stripe, fotos, realtime — não tocar |
| 11 | [conventions](knowledge/11-conventions.md) | PT-PT app / PT-BR admin, 1 laranja/ecrã, git, versionCode, commits |
| 12 | [recipes](knowledge/12-recipes.md) | 6 receitas passo-a-passo |

## Manutenção
Quando o design, regras ou schema mudarem: **atualizar SÓ esta skill**.
As skills filhas (onboarders) leem daqui — não duplicam conteúdo.
Última sincronização MCP: 2026-05-29 (projeto Supabase `ojykpzwqrtusfeakzrna`).
