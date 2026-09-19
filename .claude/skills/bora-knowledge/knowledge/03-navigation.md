# 03 — Navegação

## `_RootNavigator` (widget-rebuild pattern) — CRÍTICO
Toda a navegação principal é gerida por `_RootNavigator` em `bora_app/lib/main.dart`.
**Não é um `Navigator`** e **não há `Navigator.push/pushReplacement` para os ecrãs
principais**. Observa `SessionStore` + `AuthStore` e devolve widgets diferentes
conforme o estado.

- Login / mudança de papel → chamar `sessionStore.setRole(...)` ou setar auth state;
  `_RootNavigator` faz rebuild automático.
- **Não partir este padrão**: usar `pushReplacement` a partir de `RoleScreen` remove
  `_RootNavigator` da árvore e a auto-navegação deixa de funcionar.
- O papel (`client` / `driver` / `partner`) persiste em `SessionStore`
  (SharedPreferences key `bora_app.user_role`) e comanda toda a árvore.

> Bugfix histórico relacionado: registo de parceiro — remover `setRole` do
> `RegisterPartnerScreen` para evitar interferência do `_RootNavigator` na navegação
> (ver memória `bugfix_partner_nav`).

## `BoraBottomNavV2` — 4 tabs (cliente)
Substituiu o antigo `BoraBottomNav` (`@Deprecated`). Definido em
`bora_app/lib/widgets/bora/bora_bottom_nav_v2.dart`. Sombra no topo (`shadowNav`).

| Index | Tab | Label | Ícone |
|-------|-----|-------|-------|
| 0 | home | Início | home |
| 1 | delivery | Entrega | delivery / moto |
| 2 | reservation | Reserva | calendário |
| 3 | profile | Perfil | pessoa |

API: `BoraBottomNavV2({required current, required onTabChanged})`. `current` é o
enum/índice da tab ativa; `onTabChanged` recebe a tab selecionada. Migração do
antigo nav resolvida na Fase 4.1 (1 caller migrado em `client_main_screen.dart`).

## App bars
- Ecrãs internos: `BoraScreenAppBar(title: ...)` — **branca** (regra 1 laranja/ecrã),
  `implements PreferredSizeWidget`. Ver [04](04-widgets-bora.md).
- Header decorativo (home): `BoraAppBar` com `headerGradient` + logo + `AnnotatedRegion`
  (status bar light) + IconTheme branco.

## Fontes adicionais
- `.claude/.ai/knowledge/from-obsidian/arquitetura/mapa-ecras.md` — mapa completo de ecrãs.
- `.claude/.ai/knowledge/from-obsidian/arquitetura/fluxo-autenticacao.md` — auth/sessão.
- Código: `bora_app/lib/main.dart` (`_RootNavigator`), `bora_app/CLAUDE.md` (secção Navigation).
