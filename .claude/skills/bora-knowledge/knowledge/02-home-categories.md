# 02 — Categorias da Home (cliente)

> Fonte de verdade: `bora_app/lib/screens/client_home_screen.dart`.
> As categorias são renderizadas como `BoraTileCard.image(...)` a partir de uma
> lista de descritores (`label`, `gradient`, `imageAsset`, `onTap`).

## 7 categorias atuais
| # | Label | Gradient (AppColors) | Destino (Screen) |
|---|-------|----------------------|------------------|
| 1 | Restaurantes | `tileRestaurants` (laranja) | `RestaurantsScreen()` |
| 2 | Supermercados | `tileSupermarkets` (verde) | `StoresScreen(category: supermarket)` |
| 3 | Farmácia | `tilePharmacy` (azul) | `StoresScreen(category: pharmacy)` |
| 4 | Lojas | `tileStores` (cinza-azulado) | `StoresScreen(category: store)` |
| 5 | Enviar\nEncomenda | `tileSendPackage` (laranja) | `SendPackageFormScreen()` |
| 6 | Levar\nCompras | `tileCarryGroceries` (verde) | `CarryGroceriesScreen()` |
| 7 | Reservar\nMesa | `tileReserveTable` (roxo) | `ReservationScreen` (entry) |

> Nota: **Supermercados, Farmácia e Lojas** apontam para o mesmo `StoresScreen`,
> diferenciado pelo enum `BusinessCategory` (`supermarket`/`pharmacy`/`store`).
> Estas 3 categorias **já existem na home** mas algumas **não têm fluxo de
> onboarding** de parceiro dedicado — é o que as skills `onboard-partner-store` e
> `onboard-partner-pharmacy` resolvem (inserção via Edge Fn `register-partner`).

## RECEITA — adicionar uma 8ª categoria à home
1. **Asset** — colocar PNG da categoria em `bora_app/assets/images/categories/`
   (mesmo estilo/tamanho dos 7 existentes) e declarar em `pubspec.yaml` se a pasta
   não estiver já incluída por wildcard.
2. **Gradient** — se precisar de cor nova, adicionar `static const LinearGradient
   tileXxx` em `app_colors.dart` (seguir padrão topLeft→bottomRight, 2 stops).
   Respeitar a regra "1 laranja/ecrã" — preferir verde/azul/roxo.
3. **Destino** — garantir que o `Screen` de destino existe (ou criar). Se reusa
   `StoresScreen`, basta novo valor de `BusinessCategory` + filtro.
4. **Descritor** — em `client_home_screen.dart`, adicionar uma entrada à lista de
   tiles (perto da linha ~408-497): `label`, `gradient`, `imageAsset`, `onTap`
   (com `Navigator.push(MaterialPageRoute(builder: (_) => ...))`).
5. **Render** — a lista é mapeada com `.map((t) => BoraTileCard.image(label:
   t.label, gradient: t.gradient, imageAsset: t.imageAsset, onTap: t.onTap))` — a
   nova categoria aparece automaticamente no grid.
6. **Verificar** — `flutter analyze` (0 erros) + smoke visual. Não tocar noutros ecrãs.

## Fontes adicionais
- `.claude/.ai/knowledge/architecture/` (mapa de ecrãs em `from-obsidian/arquitetura/mapa-ecras.md`).
- Receita resumida também em [12-recipes.md](12-recipes.md#receita-1).
- Código: `bora_app/lib/screens/client_home_screen.dart` (linhas ~408-520).
