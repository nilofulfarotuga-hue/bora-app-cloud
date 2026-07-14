# Chat guiado — PARTE 1 (menu por categoria + FAQ editável)

**Ordem original:** 5f89 (chat guiado completo) travou por ser grande demais → dividida
em 3 partes. Esta ordem pedia só a PARTE 1: menu guiado por categoria + tabela de
FAQ editável pelo admin, seed com 3-4 perguntas por categoria. PT-PT. Sem "falar com
humano" nem escalação (partes 2 e 3).

## Descoberta: já estava feito

Ao investigar antes de codar (Lei do Pré-voo), encontrei que esta funcionalidade **já
tinha sido implementada e commitada** numa corrida anterior sem tracking:

- Commit `61371a9` — `feat(suporte): chat guiado por categoria + persona Hermes +
  escalação Telegram` (2026-07-14 01:59, já ancestral do HEAD atual desta branch).
- Esse commit entregou as 3 partes de uma vez (menu + falar-com-humano + escalação
  Telegram), não só a Parte 1. Como já está commitado e a funcionar, não desfiz nada —
  só verifiquei e reforcei o que faltava da Parte 1 especificamente.

## Verificado (estado real, não só o ficheiro)

- Tabelas `support_categories` (7 linhas) e `support_category_options` (antes: 12
  linhas) **já existiam e continham dados no Supabase de produção** (projeto
  `ojykpzwqrtusfeakzrna`), confirmado via MCP `list_tables`/`execute_sql` — não é só
  código local por aplicar.
- `lib/screens/support_guided_menu_screen.dart` já é o ecrã "Sobre o que queres falar?"
  com 7 categorias (pedido restaurante, mercado, entrega, TVDE, limpeza, reservas,
  conta/perfil) → sub-opções → resposta pronta (read-only), tudo em PT-PT.
- `lib/widgets/bora_support_sheet.dart` já abre este ecrã como primeira opção do
  suporte (`Navigator.push` para `SupportGuidedMenuScreen`).
- `lib/screens/admin/admin_support_categories_screen.dart` já existe — admin edita
  categorias e perguntas/respostas sem redeploy (RLS: `is_admin()` só).
- RLS aplicada corretamente: leitura `authenticated`, escrita só admin.

## O que fiz nesta corrida

O único gap real face ao pedido original era o seed: a maioria das categorias tinha
só 1-2 perguntas prontas (pedia-se 3-4). Reforcei com uma nova migration aditiva
(`supabase/migrations/20260714030000_chat_guiado_faq_extra.sql`), aplicada já em
produção via MCP:

- `pedido_restaurante`: +1 (taxa de serviço 5%) → 3 perguntas
- `mercado`: +1 (custo dos sacos €0,10/saco, cap €0,50) → 3 perguntas
- `entrega`: +1 (cálculo do custo dos sacos) → 3 perguntas

Todos os factos novos vêm **literalmente** do system prompt já existente do
support-chatbot (`supabase/functions/support-chatbot/index.ts`, secção "REGRAS DE
NEGOCIO BORA APP") — nada inventado.

**Deixei `limpeza` (1), `reservas` (1), `tvde` (2) e `conta` (2) como estavam** — não
tenho, nesta base de código, factos de negócio confirmados e específicos o suficiente
sobre esses fluxos para escrever mais 1-2 perguntas sem risco de inventar algo (ex.:
taxa de cancelamento TVDE exata, duração do serviço de limpeza). Fica registado como
pendência para quem tiver esses números confirmados (agente `estafeta-motorista`/TVDE,
`favores`/limpeza, `parceiro-servicos`/reservas) — não é um bloqueio, o admin já pode
adicionar perguntas pela UI existente a qualquer momento.

## Ficheiros tocados nesta corrida

- `supabase/migrations/20260714030000_chat_guiado_faq_extra.sql` (novo, aplicado em
  produção via MCP `apply_migration`)
- Este relatório

Nenhum ficheiro Flutter foi alterado (a UI e o admin já estavam prontos e ligados).

## Commit / push

Commit `ea5827c` criado localmente na branch `autonomous-night-2026-04-29`. `git push`
falhou com o erro de credencial conhecido (executor headless não consegue autenticar
no wincredman/GCM — ver memória `project_headless_push_credential.md`); fica para o
mecanismo de push do loop concorrente ou para push manual do Danilo.

## Estado final confirmado (contagem por categoria)

`conta`=2, `entrega`=3, `limpeza`=1, `mercado`=3, `pedido_restaurante`=3, `reservas`=1,
`tvde`=2 — total 15 perguntas em 7 categorias.

## Reconfirmação (2026-07-14, 2ª vez — mesma ordem repetida pelo loop)

A ordem PARTE 1 chegou de novo, idêntica. Verifiquei antes de codar (Lei do Pré-voo):
todos os ficheiros continuam no disco (`support_guided_menu_screen.dart`,
`admin_support_categories_screen.dart`, as duas migrations) e os commits `ea5827c` +
`b759942` continuam no topo do histórico local desta branch — nada para redigir.

Único gap real: os commits ainda não tinham chegado ao remoto. Fiz `git merge` do
`origin/autonomous-night-2026-04-29` (só trouxe 1 commit de CI, `ci: bump versionCode
to 425`, sem conflito) e tentei `git push` de novo — falhou com o **mesmo erro de
credencial wincredman** já registado em `b759942` e na memória
`project_headless_push_credential.md`. Confirma o padrão: 2ª tentativa idêntica falhou
da mesma forma → não voltar a tentar push direto nesta branch; falta o loop
concorrente ou push manual do Danilo. Nenhum código Flutter/SQL foi alterado.

CHAT-GUIADO-P1 menu de categorias + FAQ editavel OK
