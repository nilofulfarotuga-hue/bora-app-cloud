# Imagens de documentos no admin (Aprovação de parceiros) — já corrigido

**Pedido (2026-07-15):** owner_doc_url / activity_doc_url não aparecem (ícone quebrado)
no ecrã `Aprovação de parceiros` porque o bucket `restaurant-documents` é privado e a BD
só guarda o path, não um URL público — sugestão: gerar signed URL antes de mostrar.

## Diagnóstico

Este fix **já existe no código, commitado, no HEAD atual da branch**. Não é regressão nova.

- `lib/screens/admin/admin_partners_pending_screen.dart` (título `'Aprovação de parceiros'`,
  linha 330) já usa `PrivateBucketImage(urlOrPath: r['owner_doc_url'] ...)` e o mesmo para
  `activity_doc_url` (linhas 228–253), com comentário explícito `RGPD 2026-06-02: bucket
  privado restaurant-documents. PrivateBucketImage gera signed URL on-demand`.
- `lib/widgets/private_bucket_image.dart` já implementa exatamente o padrão pedido: detecta
  se o path pertence a um bucket privado (inclui `restaurant-documents`), chama
  `Supabase.instance.client.storage.from(bucket).createSignedUrl(path, 3600)` e só depois
  renderiza `Image.network` — com loading (`CircularProgressIndicator`) e erro
  (`Icons.broken_image`) tratados.
- `admin_partner_detail_screen.dart` (ecrã de detalhe, pós-aprovação) tem o mesmo padrão
  desde a mesma correção.

Histórico: `relatorios/CORRECAO_FOTOS_ADMIN_2026-06-02.md` documenta a correção original
(commit `49a544e`, 2026-06-02) — migrou os docs do bucket público `restaurant-assets` para
o privado `restaurant-documents` e trocou `Image.network(path_cru)` por `PrivateBucketImage`
em `admin_partners_pending_screen.dart` (Passo 5b) e `admin_partner_detail_screen.dart`
(Passo 4). Confirmado via `git log` que ambos os ficheiros seguem intactos nesse estado —
`git status` não mostra diferenças.

## Verificação feita agora

- `git status --short` nos 3 ficheiros: sem alterações pendentes (código já é o do commit
  `49a544e`).
- `flutter analyze` nos 3 ficheiros: **0 erros** — 14 infos pré-existentes (mesmas do
  relatório de 2026-06-02: `use_build_context_synchronously`, `curly_braces_in_flow_control`,
  `activeColor` deprecated, nomes de classe privada), nenhuma delas nos blocos de imagem.

## Se o Danilo ainda vê ícone quebrado no dispositivo

Não é bug de código — provável causa é **APK desatualizado** (ver
`[[project_autocomplete_guarda_stale_apk]]`, o mesmo padrão já visto noutro bug: código
correto no repo, app instalada é build anterior). Recomendação: build+install novo APK para
confirmar visualmente.

## Ficheiros tocados

Nenhum ficheiro de código alterado (nada para corrigir). Só este relatório.
