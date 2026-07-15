---
data: 2026-07-15
tarefa: "Corrigir imagens de Documento Proprietário/Documento Atividade quebradas em admin 'Aprovação de parceiros'"
resultado: "JÁ RESOLVIDO — nenhuma mudança de código necessária"
---

# Fix imagem documentos admin — verificação 2026-07-15

## Pedido
Ícone quebrado ao mostrar `owner_doc_url` e `activity_doc_url` no ecrã admin
"Aprovação de parceiros", porque esses campos guardam apenas o **path** dentro
do bucket privado `restaurant-documents` (não um URL público) — pedido para
gerar signed URL via `PrivateBucketImage` / `createSignedUrl` antes de exibir.

## Investigação
Revi os dois pontos onde `owner_doc_url`/`activity_doc_url` são exibidos:

1. `lib/screens/admin/admin_partners_pending_screen.dart` (linhas 225–253,
   dialog "Documentos — {nome}") — **já usa `PrivateBucketImage`** para os
   dois campos, com comentário explícito "RGPD 2026-06-02: bucket privado
   restaurant-documents. PrivateBucketImage gera signed URL on-demand".
2. `lib/screens/admin/admin_partner_detail_screen.dart` (secção "Documentos",
   linhas ~575–590 e o widget `_PartnerDocImage` em 1733–1769) — idem, usa
   `PrivateBucketImage` + `resolveSignedUrlIfPrivate` para o fullscreen.

`lib/widgets/private_bucket_image.dart` já implementa exatamente o padrão
pedido: extrai bucket+path do valor guardado (path cru ou URL antigo),
chama `Supabase.instance.client.storage.from(bucket).createSignedUrl(path, 3600)`,
com loading/erro tratados (spinner enquanto resolve, ícone "broken_image" em
falha). `restaurant-documents` está na lista `_privateBuckets` (linha 11).

RLS (`supabase/migrations/20260602100000_create_restaurant_documents_bucket.sql`)
confirma que admin tem policy de SELECT (`admin_read_all_restaurant_docs` +
`admin_sign_restaurant_docs`) sobre esse bucket — o `createSignedUrl` como
admin autenticado deve funcionar.

## Causa raiz do relato
O fix já foi aplicado no commit `49a544e` ("feat(admin): secção Documentos
no admin_partner_detail + PrivateBucketImage no partners_pending"), como
parte da correção RGPD de 2026-06-02 (commits `af3e27a`, `3d7a1af`,
`20260602100000_create_restaurant_documents_bucket.sql`). O bug reportado
já não existe no código atual — provavelmente relato desatualizado (ecrã
visto antes do deploy do fix, ou cache de build antiga no dispositivo).

## Ação
Nenhuma alteração de código. Sem commit (nada para commitar — `git diff`
vazio nestes ficheiros). `flutter analyze` não foi possível correr neste
ambiente (binário `flutter` não instalado no host), mas não houve edição
de código, logo não há risco de regressão.

## Recomendação
Se o ícone quebrado persistir em produção, a causa mais provável já não é
código Flutter, mas sim: (a) build antiga no dispositivo do Danilo sem este
commit, ou (b) sessão admin sem `raw_app_meta_data.role = 'admin'` (RLS
falha silenciosamente → `createSignedUrl` devolve erro → `PrivateBucketImage`
mostra broken_image). Vale confirmar a versão do app instalada e o
`role` do utilizador admin em `auth.users.raw_app_meta_data` antes de reabrir
este ticket.

imagens de documentos no admin agora usam signed URL, corrigido.
