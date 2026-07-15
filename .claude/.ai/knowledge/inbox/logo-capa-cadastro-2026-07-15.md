---
tarefa: adicionar upload de LOGO e CAPA no wizard de cadastro de parceiro
data: 2026-07-15
estado: atual
---

# Logo & capa no wizard de cadastro de parceiro

## O que existia
- O passo "Logo & Confirmação" já tinha um seletor de LOGO (upload via
  `upload-restaurant-asset`, kind='logo') — não estava "só a marca do Bora"
  como o pedido descrevia, mas faltava mesmo a CAPA.
- `restaurants.cover_url` (TEXT, nullable) não estava em nenhuma migration
  do repo nem em `schema.sql` — assumido já aplicado em prod conforme
  contexto da tarefa; adicionei a migration em falta (idempotente) para o
  repo não ficar dessincronizado da BD real.

## O que foi feito
1. **`lib/screens/register_partner_screen.dart`** — passo "Logo & Confirmação":
   - Logo agora num placeholder quadrado (120×120) rotulado "Logo (quadrada)".
   - Novo seletor de CAPA, placeholder retangular (110×full-width) rotulado
     "Capa (retangular)", com câmara/galeria via `SafeImagePicker` — mesmo
     padrão do logo (`_pickCover` / `_showCoverOptions`).
   - Upload da capa antes do submit final via `upload-restaurant-asset`
     (bucket público `restaurant-assets`, `kind: 'cover'`) — mesmo padrão
     do logo. Ambos opcionais; nenhum bloqueia o submit.
   - `_recoverLostImage` (Android low-memory kill do image picker) estendido
     para incluir a capa como 4º fallback, mesma lógica já existente.
2. **`lib/auth/auth_store.dart`** — `photoUrl`/`coverUrl` passados por
   `registerPartnerWithDocumentsAsync` → `resumePartnerRegistrationAsync` →
   `_submitRestaurantEdgeFunction` → body do invoke de `register-partner`.
3. **`supabase/functions/register-partner/index.ts`** — aceita `photoUrl` e
   `coverUrl` no body; `restaurantPayload` agora inclui
   `photo_url: body.photoUrl || ""` (mantém default da coluna NOT NULL) e
   `cover_url: body.coverUrl || null` (coluna nullable). Só afeta o ramo
   `restaurants` (não o ramo `beauty`/`service_providers`, que não tem
   `cover_url`).
4. **`supabase/migrations/20260715130000_restaurants_cover_url.sql`** +
   `supabase/schema.sql` — `ADD COLUMN IF NOT EXISTS cover_url TEXT`
   (aditivo, não-destrutivo).

## O que NÃO mudou
- A atualização pós-criação de `photo_url` via `.update()` direto na tabela
  (linha ~530 do wizard) ficou intacta — agora é redundante para o caso de
  criação nova (o `photo_url` já vem no insert), mas continua necessária
  como está para não arriscar quebrar o fluxo já validado.
- Não toquei em `RestaurantModel`/exibição da capa na página do
  restaurante — fora do escopo pedido (só o wizard).

## Verificação
- `flutter` não está instalado neste ambiente (`flutter: command not found`)
  — não foi possível correr `flutter analyze`. Revisão manual: parênteses/
  chaves/colchetes balanceados (contagem automática), assinaturas dos 3
  métodos do `auth_store.dart` conferidas ponta-a-ponta, variáveis
  `logoUrl`/`coverUrl` no escopo correto em `_submit()`.
- Fluxo COM imagens: upload logo → upload capa → submit com
  `photoUrl`/`coverUrl` preenchidos → Edge Function grava ambos no insert.
- Fluxo SEM imagens: `_logoFile`/`_coverFile` ficam `null` → nenhum upload
  ocorre → `photoUrl`/`coverUrl` chegam `null` ao Edge Function →
  `photo_url` fica `""` (default), `cover_url` fica `null` — cadastro segue
  normalmente (só email+telefone continuam obrigatórios).

## Pendente (ação humana)
- Confirmar que `cover_url` existe mesmo em prod (a tarefa afirmou que sim)
  e fazer deploy da Edge Function `register-partner` atualizada — a
  pipeline de CI não aplica migrations nem faz deploy de Edge Functions
  (gap já registado em memória anterior sobre este mesmo wizard).

## Re-verificações (mesmo dia, 2026-07-15)
- A mesma tarefa chegou repetida pelo menos duas vezes pelo loop autónomo
  (esta é a 2ª nota). Confirmado de novo via `git log` que `7e2c63f` cobre
  os 5 pontos pedidos, `flutter` continua indisponível neste ambiente
  (`flutter: command not found`, mesmo erro de antes), e o commit continua
  em `origin/autonomous-night-2026-04-29` sem nada pendente de push.
  Nenhuma alteração de código em nenhuma das duas repetições — só notas.
  Se a tarefa voltar uma 3ª vez, ver [[cadastro-parceiro-register-partner-idempotencia]]
  e o memo `feedback_logo_capa_cadastro_ja_resolvido.md` antes de investigar de novo.
