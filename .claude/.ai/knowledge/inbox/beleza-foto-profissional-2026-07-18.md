---
id: beleza-foto-profissional-2026-07-18
---

# Upload real de foto do profissional (parceiro-serviços)

## O que foi feito
O campo "URL da foto (opcional)" no formulário de adicionar/editar profissional
(membro da equipa) foi substituído por um seletor de foto real: tocar no avatar
abre um bottom-sheet "Tirar foto" / "Escolher da galeria", faz upload para o
Supabase Storage e guarda a `public_url` resultante no mesmo campo `photo_url`
que já existia (aparece ao cliente onde o profissional é mostrado).

**Nota:** ao investigar encontrei este trabalho já implementado no working tree
(não commitado) — mesma tarefa, mesmo ficheiro, diff idêntico ao que a tarefa
pedia. Validei a implementação (flutter analyze limpo, compatibilidade com
store/model) e fiz o commit + push que faltava.

## De onde foi copiado o componente de upload
Reaproveitado o padrão de `register_partner_screen.dart` (upload do logo/capa
do parceiro): mesma Edge Function `upload-restaurant-asset`, mesmo
`SafeImagePicker` (`lib/utils/safe_image_picker.dart` — wrapper que evita o
erro `already_active` do `image_picker` em toques repetidos), mesma
compressão (`maxWidth: 1200, imageQuality: 85`), mesma validação de
`contentType` (`image/jpeg` etc.) e o mesmo tratamento de erro (SnackBar com
mensagem em PT-PT).

## Bucket / pasta usado
Bucket **`restaurant-assets`** (público) — a Edge Function `upload-restaurant-asset`
só envia para o bucket privado `restaurant-documents` quando `kind` é
`owner_doc` ou `activity_doc`; qualquer outro `kind` (incluindo o novo
`staff_photo`) vai para `restaurant-assets`. Caminho gerado:
`{restaurantId}/staff_photo-{timestamp}.{ext}`. Não foi preciso alterar a
Edge Function — `kind` já era um campo livre.

## Ficheiro(s) tocado(s)
- `lib/screens/partner/services/partner_manage_staff_screen.dart` — campo URL
  removido; adicionado `_chooseImageSource`, `_pickAndUploadPhoto`, avatar
  clicável com ícone de câmara e estado de loading durante o upload.

`PartnerAppointmentsStore.createStaff` / `updateStaff` e `StaffMemberModel` já
aceitavam `photoUrl` como `String?` — nenhuma alteração necessária aí.

## Validação
- `flutter analyze lib/screens/partner/services/partner_manage_staff_screen.dart`
  → **No issues found!**
- Fluxo de dados (avatar → Storage → `photo_url` → tile da lista) confirmado
  por leitura de código, ponta-a-ponta.

## Commit
Ver `git log -1` colado abaixo (preenchido após o commit real).
