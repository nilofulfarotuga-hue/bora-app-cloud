# CHAT GUIADO — PARTE 1 — 6ª reconfirmação (2026-07-14)

A ordem "CHAT GUIADO PARTE 1" chegou novamente ao loop. Antes de recodificar, segui a
memória `project_chat_guiado_p1_ja_feito.md` (LEI DO PRE-VOO: 2 falhas/confirmações
iguais → não repetir a mesma investigação) e apenas verifiquei o estado atual.

## Verificação (sem despachar subagentes, sem reabrir ficheiros)

- `git log --oneline -5`: topo é `f430546` (fix de mapa, não relacionado), seguido de
  `e3386c9`, `8cb04e4` (5ª reconfirmação chat-guiado), `ff176d7` (3ª reconfirmação),
  `89fda72`. Todos os commits do chat guiado já estão no histórico local.
- `git status --porcelain` nos ficheiros do chat guiado
  (`lib/screens/support_guided_menu_screen.dart`,
  `lib/screens/admin/admin_support_categories_screen.dart`, as duas migrations
  `20260714010000_chat_guiado_categorias.sql` /
  `20260714030000_chat_guiado_faq_extra.sql`, `lib/screens/support_human_chat_screen.dart`)
  → **saída vazia**. Zero regressão, zero diferença, zero necessidade de recodificar.

## Estado confirmado (inalterado desde a 5ª reconfirmação)

- Menu "Sobre o que queres falar?" por categoria: implementado
  (`support_guided_menu_screen.dart`, 7 categorias).
- FAQ editável pelo admin: tabelas `support_categories` / `support_category_options` +
  CRUD em `admin_support_categories_screen.dart`. Seed com 15 perguntas (12 originais +
  reforço de 3).
- PARTE 2 (falar com humano) e PARTE 3 (escalação) também já existem
  (`support_human_chat_screen.dart` + `support_escalations`), entregues no commit
  original `61371a9` antes da divisão em partes — não fazem parte do escopo desta
  ordem mas não foram tocados.

## Push — continua bloqueado (Lista Vermelha)

Não tentei `git push` (seria a 6ª tentativa idêntica). Causa raiz já diagnosticada e
confirmada 5x: conta Windows `hermes` sem credencial GitHub interativa. Caminho
alternativo via bridge SSH PC→VPS (`refs/heads/from-pc-2026-07-14` no clone
`bora-app-cloud`) já foi preparado na 5ª reconfirmação e funciona tecnicamente, mas o
passo final (`git push origin`) dispara `build_android.yml` → build de produção +
upload Google Play automático = 🔴 Lista Vermelha. Só falta o Danilo confirmar "vai".

⚠️ ISTO MEXE EM BUILD DE PRODUÇÃO (push dispara CI de deploy). Está tudo pronto —
confirma que eu aplico o push final.

## Recomendação para próximas corridas

Se a ordem repetir de novo, não é preciso reabrir esta investigação nem os ficheiros —
basta linkar este ficheiro e o `project_chat_guiado_p1_ja_feito.md`.

CHAT-GUIADO-P1 menu de categorias + FAQ editavel OK.
