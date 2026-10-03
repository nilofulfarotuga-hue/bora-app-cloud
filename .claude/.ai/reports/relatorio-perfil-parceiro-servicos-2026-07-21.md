# Relatório — Perfil rico do parceiro de Serviços (Barbearia Ouro e Prata) + paridade admin

**Data:** 2026-07-21
**Missão conduzida via CEO-AI** (`.claude/skills/ceo-ai/SKILL.md`) — zona verde/amarela,
sem dinheiro envolvido. Executado ponta-a-ponta (Validation Gate: só dinheiro trava).

## Contexto confirmado (leitura, sem alterar schema)

Consultei `service_providers` e `staff_members` via MCP antes de codar:
- Ouro e Prata: `photo_url`/`hero_image_url` já preenchidos, `about_text` com 754
  caracteres, `gallery_urls = []` (vazio — Danilo vai popular via upload no admin),
  `social_instagram`/`social_facebook` = `null`.
- `staff_members`: 1 profissional ("Gilberto"), com `photo_url` próprio.

## 1. App cliente — `lib/screens/client/services/provider_detail_screen.dart`

- **Avatar da equipa maior**: `StaffAvatar` na secção "A nossa equipa" passou de
  `radius: 34` para `radius: 44` (card de 148→164px de largura, secção de
  200→220px de altura para caber).
- **Bug real encontrado e corrigido** em `lib/widgets/services/staff_avatar.dart`:
  quando `staff.photoUrl` existe mas a imagem falha a carregar (404/rede), o
  `CircleAvatar` não tinha fallback — ficava um círculo liso sem iniciais nem
  ícone (o mais próximo do "quadradinho em branco" que dava para reproduzir no
  código; `hero_image_url`/lista de prestadores já usavam `BoxFit.cover`
  corretamente). Corrigido: widget convertido para `StatefulWidget` com
  `onBackgroundImageError` → cai para o gradiente + iniciais.
- **Secção "Sobre"** (`_aboutSection`): mostra `about_text` respeitando quebras
  de linha; oculta-se silenciosamente se vazio/null.
- **Secção "Galeria"** (`_gallerySection`): carrossel horizontal 110×110,
  `BoxFit.cover`, cantos arredondados, tap → `GalleryViewerScreen` (novo
  ficheiro) com `PageView` + `InteractiveViewer` (swipe + pinch-zoom) + índice
  "n/N". Oculta-se se `gallery_urls` vazio.
- **Ícones sociais** (`_socialRow`): Instagram/Facebook, só aparecem se
  preenchidos; aceitam handle (`@nome`) ou URL completo; abrem externamente via
  `url_launcher` (padrão já usado no resto do app).
- `lib/models/service_provider_model.dart`: adicionados `aboutText`,
  `galleryUrls` (List<String>), `socialInstagram`, `socialFacebook` —
  `fromSupabase`/`toMap` cobrem as 4 colunas novas.

## 2. Painel admin — `lib/screens/admin/admin_service_provider_detail_screen.dart`

Estendida a aba "Dados" (sem criar aba nova) com 3 cards novos, válidos para
**qualquer** parceiro de Serviços:
- **"Sobre"**: textarea (8 linhas) + botão guardar → `about_text`.
- **"Galeria"**: grid com miniaturas 100×100, botão "Adicionar foto" (mesmo
  fluxo de `SafeImagePicker` + Edge Function `upload-restaurant-asset`, já
  usado para logo/capa — reutilizada com `kind: 'gallery/photo'`, o que produz
  o caminho `{providerId}/gallery/photo-{timestamp}.ext` no bucket
  `restaurant-assets`, exatamente a pasta pedida). Cada miniatura tem botão "×"
  (remove do array, sem apagar o ficheiro do storage — mesmo comportamento já
  existente para logo/capa neste ficheiro) e setas ←/→ para reordenar
  (persistido logo a seguir; reverte se a gravação falhar).
- **"Redes sociais"**: campos Instagram/Facebook + botão guardar →
  `social_instagram`/`social_facebook`.
- Logo/capa (`photo_url`/`hero_image_url`) já tinham upload/remoção — não
  mexido, só confirmado que continua a funcionar.

Nenhuma alteração ao schema, à Edge Function nem à RLS foi necessária — a
função `upload-restaurant-asset` já era genérica (usa `kind` como parte livre
do nome do ficheiro) e a policy de UPDATE do admin já não é restrita por
coluna.

## Verificação

`flutter analyze` (projeto inteiro, `--no-fatal-infos`): **223 issues, 0 erros**
— nenhum dos ficheiros tocados/criados nesta missão aparece na lista (nenhum
warning/info novo introduzido). Baseline anterior registada em memória: 217
issues/0 erros — a diferença (+6) não pertence a nenhum ficheiro desta tarefa.

Não corri o app num emulador/dispositivo real (sem device disponível nesta
sessão) — a verificação visual final (avatar maior, galeria a abrir em ecrã
cheio, ícones sociais) fica pendente de um `flutter run` real do Danilo ou
`/run` numa próxima sessão.

## Bugs encontrados fora do escopo (a reportar, não corrigidos aqui)

1. **`StaffAvatar` sem fallback em erro de imagem** (já corrigido acima —
   listado aqui só porque não era o pedido original, era descoberta lateral).
2. **`register_partner_screen.dart`**: 4 warnings do `flutter analyze` —
   imports não usados (`partner_product_store.dart`, `restaurant_store.dart`,
   `bora_primary_button.dart`, `partner_login_screen.dart`) e campo
   `_formKey` nunca lido. Não tocado (fora do escopo desta missão).
3. **`register_partner_screen.dart:33`**: warning "field `_formKey` isn't
   used" sugere um `Form` sem `key` ligado — pode ser bug de validação
   silenciosa (formulário não valida ao submeter). Vale investigar noutra
   sessão.
4. **`refund_choice_dialog.dart:65`**: campo `_tokenValueCentsX100` nunca
   lido — zona 🔴 (tokens/refund), fora do escopo desta missão (não tocado,
   só reportado).

## Próximo passo (Danilo)

1. Popular a galeria da Ouro e Prata via **Admin → Serviços → Ouro e Prata →
   aba Dados → card "Galeria" → Adicionar foto**.
2. Preencher Instagram/Facebook se quiser (opcional).
3. `flutter run` num device para confirmar visualmente o resultado antes do
   próximo build de release.
