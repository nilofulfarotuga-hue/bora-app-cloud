---
data: 2026-07-15
tarefa: "Corrigir imagens de Documento Proprietário/Documento Atividade quebradas em admin 'Aprovação de parceiros'"
resultado: "BUG REAL ENCONTRADO E CORRIGIDO — correção anterior (mesmo dia) tinha concluído 'já resolvido' por engano"
---

# Fix imagem documentos admin — 2026-07-15 (correção real)

## Causa raiz confirmada
`PrivateBucketImage` já existia e já era usado nos dois pontos certos
(`admin_partners_pending_screen.dart` e `admin_partner_detail_screen.dart`),
mas o **path guardado na BD não tem o prefixo do bucket**:

- `supabase/functions/upload-restaurant-asset/index.ts` faz upload para o
  bucket privado `restaurant-documents` mas devolve `path: filename` **sem**
  o nome do bucket (ex.: `temp-1752600000000/owner_doc-1752600000000.jpg`).
- `register_partner_screen.dart` grava esse `path` cru em `ownerDocUrl` /
  `activityDocUrl`, que vai direto para as colunas `owner_doc_url` /
  `activity_doc_url`.
- `PrivateBucketImage._extract()` (`lib/widgets/private_bucket_image.dart`)
  só reconhece um path privado se ele **começar literalmente com
  `restaurant-documents/`**. Sem esse prefixo, `_extract` devolve `null` e o
  widget trata o path cru como se já fosse uma URL válida → `Image.network`
  falha silenciosamente → ícone quebrado.

Confirmado que registos **antigos** (antes do fix RGPD de 2026-06-02,
`20260602100000_create_restaurant_documents_bucket.sql`) guardavam URL
pública completa (`https://.../public/restaurant-assets/...`) — esses
continuam a funcionar (Image.network direto). O bug só afeta parceiros
registados **depois** do fix RGPD, que é exatamente quando o admin passou a
ver o ícone quebrado.

## Correção aplicada
1. `lib/widgets/private_bucket_image.dart` — nova função
   `withPrivateBucketPrefix(bucket, rawPathOrUrl)`: prefixa o path cru com
   `$bucket/` só quando ainda não é URL (`http`) nem já tem o prefixo.
2. `lib/screens/admin/admin_partners_pending_screen.dart` — os dois
   `PrivateBucketImage` (owner_doc_url/activity_doc_url) agora passam
   `withPrivateBucketPrefix('restaurant-documents', ...)`.
3. `lib/screens/admin/admin_partner_detail_screen.dart` — `_PartnerDocImage`
   ganhou getter `_prefixedPath` usado tanto no thumbnail quanto no
   fullscreen (`_openFullscreen`).

Nenhuma mudança em `upload-restaurant-asset` (Edge Function) nem em schema —
o fix é só na camada de leitura/exibição, sem tocar dados existentes.

## Validação
`flutter analyze` não pôde ser executado (binário `flutter` não instalado
neste host de execução) — revisão manual da lógica: guard clauses garantem
que `r['owner_doc_url']`/`activity_doc_url` só chegam ao cast `as String`
quando não-nulos/não-vazios; `withPrivateBucketPrefix` é pura e idempotente
(idempotente para paths já prefixados ou URLs completas — sem regressão em
dados antigos).

## Nota sobre o relatório anterior (mesmo ficheiro, mais cedo hoje)
Uma verificação anterior no mesmo dia concluiu "já resolvido — nenhuma
mudança necessária", baseada em confirmar que `PrivateBucketImage` estava
sendo chamado nos lugares certos. Essa verificação não testou o *formato*
real do path guardado pelo Edge Function vs. o que `_extract()` espera —
por isso não viu o bug. Memória (`feedback_admin_docs_signed_url_ja_resolvido.md`)
foi atualizada para refletir esta correção real.

imagens de documentos no admin agora usam signed URL, corrigido.
