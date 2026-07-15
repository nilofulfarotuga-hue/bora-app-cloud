# Logo + Capa no cadastro de parceiro (2026-07-15)

## Contexto
Passo "Logo & Confirmação" do wizard de cadastro de parceiro só mostrava a marca
do Bora como confirmação — não deixava o parceiro carregar imagens próprias.
Todo parceiro novo aparecia com ícone genérico. `restaurants.cover_url` já
existia no banco (text, nullable) mas não estava sendo usado pela app nem pela
Edge Function.

## O que foi feito
1. `lib/screens/register_partner_screen.dart` — passo 4 agora tem DOIS
   seletores de imagem lado a lado: Logo (quadrado, ícone/listas) e Capa
   (retangular, topo da página), ambos opcionais com placeholder explicando o
   formato esperado. Novo estado `_coverFile` + `_pickCover`/`_showCoverOptions`
   espelhando o padrão já existente do logo.
2. `_submit()` faz upload da capa via `upload-restaurant-asset`
   (kind='cover', bucket público `restaurant-assets`) antes do submit final,
   igual ao logo já fazia.
3. `lib/auth/auth_store.dart` — `registerPartnerWithDocumentsAsync`,
   `resumePartnerRegistrationAsync` e `_submitRestaurantEdgeFunction` agora
   aceitam `photoUrl`/`coverUrl` e incluem no payload enviado a `register-partner`.
4. `supabase/functions/register-partner/index.ts` — aceita `photoUrl`/`coverUrl`
   no body e grava `photo_url`/`cover_url` no insert de `restaurants` (antes
   `photo_url` ia sempre `""` fixo). Para `service_providers` (categoria
   beauty) também passou a gravar `photo_url` (coluna já existe; `cover_url`
   não existe nessa tabela, não foi tocado).
5. **Gotcha descoberto:** a versão deployed do `register-partner` (v6) já
   estava à frente do ficheiro no repo — tinha a regra "só email+telefone
   obrigatórios" (2026-07-15) que o ficheiro local não tinha (ainda validava
   NIF/IBAN/nome/morada). Sincronizei o ficheiro local com a versão deployed
   ANTES de acrescentar photo/cover, para não reintroduzir a validação antiga.
   Deploy feito via MCP Supabase → v7, `verify_jwt=false` preservado.

## Sem imagens
Se o parceiro não escolher logo nem capa, o cadastro segue normalmente —
`photo_url` cai para `""` (comportamento antigo) e `cover_url` fica `null`.
Continua só email+telefone obrigatórios.

## Testado
- `flutter analyze` nos 2 ficheiros Dart tocados: 0 erros (só 6 avisos
  pré-existentes, não relacionados — unused imports/field, 1 deprecated
  `value:` no Step 3, todos já existiam antes desta mudança).
- Sem emulador disponível neste ambiente headless — não foi possível correr o
  fluxo visual end-to-end. Revisão lógica: upload de logo/capa segue
  exatamente o padrão já usado e testado para owner_doc/activity_doc (mesma
  Edge Function `upload-restaurant-asset`, só muda `kind`).

## Pendências
- Nenhuma migration criada para `cover_url` (coluna já existia direto no
  banco, fora do repo — schema drift pré-existente, não desta tarefa).
- `_recoverLostImage()` (recuperação de imagem perdida no Android após
  picker) só tem 3 slots (ownerDoc→activityDoc→logo); não inclui `_coverFile`
  — caso extremo, não crítico, deixado como estava (fora do escopo pedido).
