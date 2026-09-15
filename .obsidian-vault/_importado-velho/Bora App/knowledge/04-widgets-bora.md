# 04 — Widgets `bora/`

> Localização: `bora_app/lib/widgets/bora/`. Barrel: `bora.dart` (importar daqui).
> 14 widgets públicos. Todos consomem tokens de [01-design-system](01-design-system.md).

| Widget | Quando usar | Construtor / params-chave |
|--------|-------------|---------------------------|
| **BoraPrimaryButton** | CTA padrão **verde** | `({required label, required onPressed, icon?, loading=false, expanded=true, color=AppColors.primary})` |
| **BoraAccentButton** | CTA **laranja** (1 por ecrã — ação primária) | `({required label, required onPressed, icon?, loading=false, fullWidth=true})` |
| **BoraTileCard** | tile de categoria/atalho na home | base: `({required label, required gradient, required onTap, icon?, iconData?, imageAsset?, height=140})` |
| **BoraTileCard.image** | tile com imagem PNG de fundo (preferido nas categorias) | `.image({required label, required String imageAsset, required gradient, required onTap, height=140})` |
| **BoraScreenAppBar** | app bar **branca** de ecrã interno | `({required title, actions?})` · `implements PreferredSizeWidget` |
| **BoraAppBar** | header decorativo (home) com gradient+logo | `({title?, subtitle?, showLogo=true, actions?, leading?, height=140})` |
| **BoraBottomNavV2** | bottom nav cliente (4 tabs) | `({required current, required onTabChanged})` — ver [03](03-navigation.md) |
| **BoraBottomNav** | ⚠️ `@Deprecated` — usar V2 | `({required currentIndex, required onTap, items=defaultItems})` |
| **BoraSearchField** | campo de pesquisa | `({required hint, controller?, onChanged?, onSubmitted?, onTap?, readOnly=false})` |
| **BoraAddressBar** | barra de endereço (entrega/header) | `({required label, required address, onTap?, onHeader=false})` |
| **BoraProductCard** | card de produto (listagens loja/restaurante) | `({required product, required onAdd, required onTap, onFavoriteToggle?, isFavorite=false, displayPrice?})` — usa tabular figures |
| **BoraPromoBanner** | banner promocional (`promoGradient`) | `({required title, subtitle?, trailingAsset?, trailingIcon?, onTap?, height=120})` |
| **BoraEmptyPlaceholder** | estado vazio (sem dados) | `({required icon, required title, message?})` |
| **BoraMascot** | mascote/branding | `({variant=BoraMascotVariant.icon, size=96, semanticLabel?})` — variantes `icon` / `logo` |
| **ReservationCard** | card de reserva (lista parceiro/cliente) | `({required reservation, onCancel?, onArrive?, onDetails?})` |

## Notas importantes
- **`BoraTileCard.image()` vs base** — preferir `.image()` para categorias da home
  (imagem PNG + overlay gradient + label). A base (`icon`/`iconData`) é para atalhos
  sem imagem. O construtor original está marcado `@Deprecated` em favor de `.image()`
  onde aplicável (ver memória Fase 3.1B).
- **Regra 1 laranja/ecrã** — só `BoraAccentButton` é laranja. Não usar dois por ecrã.
- Importar sempre via barrel: `import 'package:bora_app/widgets/bora/bora.dart';`.

## Fontes adicionais
- Histórico de re-skin: memória `project_sessao_design_system_fase3*` e `_fase4*`.
- Código: `bora_app/lib/widgets/bora/*.dart`.
