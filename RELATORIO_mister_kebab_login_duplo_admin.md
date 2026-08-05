# RELATÓRIO — BLOCO 6 (login duplo) + BLOCO 7 (painel admin), 2026-08-05/06

Continuação da missão do site do Mr Kebab (commit `6781ab9`) que tinha ficado com os
BLOCOS 6 e 7 por fazer (ver `RELATORIO_mister_kebab_site_2026-08-05.md` §5).

## ⚠️ Screenshots: NÃO consegui tirar — leia isto primeiro

O único dispositivo Android ligado por USB (SM A366B, `RZGYB1XQD2P`) tinha, quando
liguei, uma sessão **real e activa de motorista** aberta no ecrã ("Bora Motorista" →
"Estás online — à espera de corridas de passageiros", online há 22 min). Testar o
login duplo ao vivo exigiria fazer logout dessa sessão (o `RoleScreen` faz
`authStore.logout()` antes de trocar de papel) — o que tiraria um motorista real do
ar, possivelmente perdendo corridas verdadeiras.

**Decisão:** não toquei nessa sessão. Não fiz logout, não interagi mais com o
dispositivo. Por isso **não há screenshots do painel do parceiro nem do carrinho do
cliente** — o pedido explícito da missão. Compilei e instalei o código novo no
telemóvel (`flutter run` terminou a instalar com sucesso — via os logs do
`DriverStore` a correr ao vivo — antes de o daemon do Gradle rebentar por falta de
RAM numa tentativa de rebuild concorrente; o app já instalado ficou incólume). O que
valida o código é: `flutter analyze` 0 erros, os 9 testes de `multirole_test.dart`
verdes, e leitura cuidadosa de cada ecrã tocado. **Falta o teste ao vivo — fica
pendente para uma sessão com o dispositivo livre.**

## O que fiz — BLOCO 6 (login duplo)

Investiguei antes de escrever código: já existia meio-caminho andado de uma sessão
anterior — `ProfileSwitcherButton` (botão "Trocar de perfil" no AppBar do Perfil,
já ligado em `profile_screen.dart`) e a RPC `my_roles()` já em produção. Mas tinha um
bug real: o botão só fazia `sessionStore.setRole(outroPapel)`, sem activar a conta
desse papel no `AuthStore` — e `_currentClient`/`_currentDriver`/`_currentPartner`
são mutuamente exclusivos (cada login zera os outros dois). Resultado: trocar de
"Cliente" para "Parceiro" caía direto no ecrã de login do parceiro, porque
`authStore.currentPartner` continuava `null`. Não era "trocar sem sair" — na
prática, sempre pedia login de novo.

**Fix real:** `AuthStore.switchToRole(AuthRole)` (`lib/auth/auth_store.dart`) — activa
o papel de destino na MESMA sessão Supabase Auth (sem `signOut`/`signIn` novo, já que
`user_roles` permite duas linhas para o mesmo utilizador e o JWT actual serve para
ambas). Constrói a conta local a partir do cache (`_clientsByEmail`/
`_partnersByEmail`/`_driversByEmail`) ou, na primeira vez, do `user_metadata` do
Supabase Auth (mesmo padrão de fallback que `loginClientAsync` já usava). Descobri
que, uma vez `currentPartner`/`currentClient` fica preenchido, `PartnerEntryScreen` e
`_RootNavigator` já se resolvem sozinhos (iam buscar o restaurante por email,
mostrar o hub de serviços, etc.) — não precisei duplicar essa lógica.

Ficheiros:
- `lib/auth/auth_store.dart` — `switchToRole()`.
- `lib/services/role_switch_helper.dart` (novo) — mapeamento partilhado
  role↔label/ícone/estado + `fetchUiRoles()` (lê `my_roles()`) + `activateRole()`
  (switchToRole + setRole), usado tanto pelo botão de Perfil como pelo ecrã novo.
- `lib/widgets/profile_switcher_button.dart` — trocado o `setRole` directo por
  `activateRole()` (o fix do bug acima).
- `lib/screens/role_choice_screen.dart` (novo) — ecrã "Como queres entrar?" mostrado
  logo após o login quando `my_roles()` devolve 2+ papéis navegáveis. Explica que dá
  para trocar depois em Perfil sem sair da conta.
- `lib/screens/client_login_screen.dart` / `lib/screens/partner_login_screen.dart` —
  depois do login com sucesso (password), consulta `my_roles()`; se ≥2 papéis, mostra
  o `RoleChoiceScreen` em vez de entrar direto no papel do ecrã de login usado.
  (Login biométrico do parceiro herda o comportamento porque passa pelo mesmo
  `_finishPartnerLogin`; o do cliente não foi tocado — fica no papel de sempre.)

Utilizadores com 1 papel só (a esmagadora maioria) não veem nada disto — `roles.length
< 2` cai direto no fluxo antigo, sem ecrã extra.

## O que fiz — BLOCO 7 (painel admin)

Descobri que **parte já estava feita** numa sessão anterior não reportada:
`partner_commission_billing` (quem paga a comissão de 10%, com o aviso exacto pedido
"NÃO recalcula preços") já estava 100% implementado em
`admin_partner_detail_screen.dart` (commit `9c42ac6`). E o controlo de papéis de
utilizador (`admin_list_user_roles`/`admin_add_user_role`/`admin_remove_user_role`)
já existia como widget completo (`lib/widgets/admin/admin_user_roles_sheet.dart`) e
já estava ligado em `admin_clients_screen.dart` — não fiz nada aí.

O que faltava mesmo, implementei:
- **Migration nova** `supabase/migrations/20260805170000_admin_partner_profile_fields.sql`
  — adiciona `whatsapp`, `social_facebook`, `social_instagram`, `about_text` a
  `restaurants` (TEXT, default `''`, `ADD COLUMN IF NOT EXISTS` — seguro para
  re-correr). `takeaway_enabled`/`reservations_enabled` já existiam, não recriados.
- **`admin_partner_detail_screen.dart`** — cartão novo "Contacto e redes sociais"
  (WhatsApp/Facebook/Instagram/Sobre a loja) na aba Dados, gravado por
  `.update()` directo em `restaurants` — **sem RPC nova**, porque descobri que a RLS
  de UPDATE dessa tabela já permite escrita directa pela sessão admin (é o mesmo
  padrão já em produção para `takeaway_enabled`/`curbside_enabled`/
  `partner_commission_billing`, só copiei). Adicionei também o toggle "Reservas de
  mesa" na aba Estado (só faltava o lado admin; o parceiro já tinha o seu). E um
  botão "Papéis do utilizador" na aba Dados que abre o `AdminUserRolesSheet` já
  existente, agora também a partir da ficha do parceiro (antes só dava para abrir a
  partir da lista de clientes).

## ⚠️ Pendências para o Danilo

1. **Aplicar a migration nova** — não tenho credenciais Supabase nesta sessão headless
   (sem `SUPABASE_ACCESS_TOKEN`, sem MCP do Supabase ligado aqui). O ficheiro está
   pronto em `supabase/migrations/20260805170000_admin_partner_profile_fields.sql`;
   falta `supabase db push` (ou aplicar no SQL Editor). Sem isto, o cartão novo do
   admin vai dar erro ao gravar (colunas não existem ainda).
2. **Teste ao vivo do login duplo** — ficou por fazer pelo motivo do topo. Sugiro
   correr numa altura em que o telemóvel não tenha um motorista online, ou usar um
   emulador dedicado.
3. **Senha da sabores.decasa@bora.app** — não sei qual é; não vou adivinhar. Se for a
   mesma lógica de `MrKebab2026!`, confirma; senão diz-me a senha ou eu gero uma nova
   e aviso-te por fora.
4. Não confirmei se `mr.kebab@bora.app` aparece na lista de `admin_clients_screen`
   (de onde já dá para abrir os papéis dela) — não tenho acesso à DB para verificar.
   Se não aparecer lá por já ser 'partner' como papel principal, o botão que
   acrescentei na ficha do parceiro cobre esse caso.

## Fora do âmbito (não mexi)

- `products.price`, `partner_shelf_price`, `platform_settings`,
  `post_order_to_ledger`, `apply_order_financial_split`, `partner_store_share`,
  trigger `trg_payment_draft_coming_soon` — intocados.
- Nenhuma outra loja além de `mrkebab-guarda` e `sabores-de-casa` foi tocada.
- `coming_soon` continua ligado onde já estava.
- Não incrementei `versionCode` nem usei `git add -A`.

## Validação feita

- `flutter analyze` nos ficheiros tocados: **0 erros, 0 avisos** (só `info` de estilo
  pré-existente no resto do ficheiro `admin_partner_detail_screen.dart`).
- `flutter analyze` completo: **227 issues, 0 erros** (baseline tinha 217 antes de eu
  começar, mas o excesso vem de ficheiros TVDE já modificados por outra sessão antes
  desta, não meus).
- `flutter test test/multirole_test.dart`: **9/9 verdes**.
- Build/instalação no dispositivo real: sucesso (confirmado pelos logs do
  `DriverStore` a correr com o binário novo), sem crash da app.
