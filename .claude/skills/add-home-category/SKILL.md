---
name: add-home-category
description: Gera o diff (Modo A — patch generator) para adicionar uma 8ª categoria à home do cliente — gradient em app_colors.dart, tile em client_home_screen.dart, asset e rota. NÃO toca lib/ sem --apply. Audita a regra "1 laranja/ecrã".
metadata:
  type: codegen
  category: ui
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Add Home Category (Modo A — patch generator)

Adiciona uma categoria ao grid da home **gerando diffs para revisão humana**.
**Não edita `lib/` por defeito** (zona Fase 4 fechada). `--apply` é explícito + faz backup + auditoria.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/01-design-system.md` (tokens, regra 1 laranja/ecrã)
2. `bora-knowledge/knowledge/02-home-categories.md` (Receita oficial)
3. `bora-knowledge/knowledge/10-protected-zones.md`

## Input
```bash
python scripts/generate_patch.py \
  --label "Flores" \
  --gradient-start "#16A34A" --gradient-end "#22C55E" \
  --asset "assets/images/categories/flores.png" \
  --screen "StoresScreen(category: BusinessCategory.store)"   # ou rota nova
```
Alternativa: `--gradient-token tileSupermarkets` (reutiliza gradient existente).

## Modos
- **DEFAULT (gerar)**: produz em `_preview/`:
  - `app_colors.proposed.dart` + `app_colors.diff` (insere `tile<Label>` antes do fecho da classe)
  - `client_home_screen.snippet.dart` (descritor do tile a inserir na lista `.map`)
  - `relatorio.md` (passos, auditoria 1-laranja, lembrete de asset + pubspec)
  - **NÃO toca `lib/`.**
- **`--apply`**: backup dos originais → escreve `app_colors.dart`, tenta inserir o descritor em
  `client_home_screen.dart` (heurística; senão deixa snippet + instrução), corre `flutter analyze`
  (best-effort) e regista em `admin_audit_log`.

## Regra "1 laranja por ecrã"
Se o gradient da nova categoria for **laranja** (`#F97316`/`#FB923C`/`#EA580C` ou `--gradient-token`
laranja), a skill **exige `--confirm-orange`** e avisa no relatório (já há tiles laranja:
Restaurantes, Enviar Encomenda).

## Salvaguardas
- Sem `--apply` → zero escrita em `lib/`.
- Asset PNG e entrada em `pubspec.yaml` são responsabilidade do humano (a skill lembra, não cria binários).
- Não altera pricing/dispatch/tokens.
