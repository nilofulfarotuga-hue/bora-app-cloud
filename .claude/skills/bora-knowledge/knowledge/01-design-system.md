# 01 — Design System

> Fonte de verdade no código: `bora_app/lib/config/app_theme.dart` (base) +
> `bora_app/lib/config/app_colors.dart` (tokens semânticos estendidos).
> Handoff oficial 2026-05-28. Fases 3-4 do design system fechadas (27 ecrãs re-skinned).

## Regra de ouro — "1 laranja por ecrã"
O laranja (`secondary` / `accent` #F97316) é a cor de **ação primária única**.
Cada ecrã tem **no máximo um** elemento laranja (o CTA principal). Tudo o resto
usa verde, superfícies neutras ou texto. `BoraAccentButton` = laranja;
`BoraPrimaryButton` = verde. Em ecrãs sensíveis (checkout) o CTA final é laranja.

## Paleta (AppTheme)
| Token | Hex | Uso |
|-------|-----|-----|
| `primary` | `#16A34A` | verde principal (marca, CTAs verdes, success) |
| `primaryDark` | `#065F46` | hover / meio do gradient header |
| `primaryDeep` | `#053D28` | extremo do gradient header |
| `primaryMid` | `#15803D` | verde médio (era `primaryLight` pré-3.1A) |
| `primaryLight` | `#DCFCE7` | tint suave (NOVA semântica 3.1A — fundo de chips/badges) |
| `primaryWash` | `#F0FDF4` | tint ultra leve (fundos de secção) |
| `secondary` / `accent` | `#F97316` | laranja acento — ação primária única |
| `secondaryDark` / `accentDark` | `#EA580C` | laranja hover/pressed |
| `secondaryLight` / `accentLight` | `#FB923C` | legacy compat |
| `background` | `#F0F2EF` | fundo geral (verde-acinzentado) |
| `surface` / `card` / `cardBg` | `#FFFFFF` | cards, sheets, inputs |
| `surface2` | `#F7F8F6` | superfície alternativa (resumos, blocos) |
| `divider` | `#E5E7EB` | divisórias suaves |
| `dividerStrong` | `#D1D5DB` | divisórias fortes |
| `textPrimary` | `#111111` | texto principal |
| `textSecondary` | `#6B7280` | texto secundário |
| `textSubtle` | `#9CA3AF` | placeholder / ícones inativos |
| `textOnPrimary` | `#FFFFFF` | texto sobre verde/laranja |

## Semânticos / status (AppColors)
- `success` `#16A34A` · `warning` `#F59E0B` (amarelo — era laranja pré-3.1A) ·
  `error` `#DC2626` · `info` `#2563EB`
- Mapa: `mapPickup` `#F97316` (laranja) · `mapDropoff` `#1C6EF2` (azul)

## Tipografia
- Família única **Inter** (variable font, bundled ~856KB). `fontFamily: 'Inter'`.
- TextTheme: headlineLarge 28/w800 · headlineMedium 24/w700 · headlineSmall 20/w700
  · titleLarge 18/w600 · titleMedium 16/w600 · titleSmall 14/w600
  · bodyLarge 16 · bodyMedium 14 · bodySmall 12/textSecondary.

## Gradientes
- `headerGradient` — 135° (topLeft→bottomRight), 3 stops: `primaryDeep` 0.0 →
  `primaryDark` 0.45 → `primary` 1.0. Usado em headers/app bars decorativas.
- `promoGradient` — `secondary` → `secondaryDark` (banners promo).
- Tiles de categoria (ver [02](02-home-categories.md)): `tileRestaurants`,
  `tileSupermarkets`, `tilePharmacy`, `tileStores`, `tileSendPackage`,
  `tileCarryGroceries`, `tileReserveTable`.

## Sombras (elevation) — base slate-900 `#0F172A`
- `shadowSm` — (0,1) blur 2, alpha 6% — chips, botões pequenos
- `shadowCard` — (0,2) blur 8, alpha 8% — cards
- `shadowLg` — (0,8) blur 24, alpha 12% — modais/sheets elevados
- `shadowNav` — (0,**-4**) blur 16, alpha 6% — sombra no topo de bottom nav / painéis fixos

## Raios
- Cards: **16** (`cardTheme`) · Botões: **14** (elevated/outlined) ·
  Inputs: **12** · SnackBar: 10. (Constantes `Radii.lg`/`Radii.md` em uso em alguns widgets.)

## Componentes-tema chave
- ElevatedButton: verde, minSize 88×52, raio 14, elevation 2.
- OutlinedButton: contorno verde 1.5, raio 14.
- Input: filled branco, raio 12, foco verde 2px, prefixIcon verde.
- AppBar (tema): fundo verde, foreground branco, elevation 0 — mas os ecrãs usam
  preferencialmente `BoraScreenAppBar` (branca, ver [04](04-widgets-bora.md)).

## Fontes adicionais
- `.claude/.ai/knowledge/` (raiz) — não tem doc dedicado de design; este ficheiro é canónico.
- Memória de sessões: design system Fases 1→4 (ver `memory/MEMORY.md`, entradas
  `project_sessao_design_system_*` e `project_sessao_fase4_*`).
- Código: `bora_app/lib/config/app_theme.dart`, `bora_app/lib/config/app_colors.dart`.
