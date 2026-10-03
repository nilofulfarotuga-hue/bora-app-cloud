# Diagnóstico — erro 400 no upload do documento (candidatura de limpeza)

**Data:** 2026-07-06 · `lib/services/cleaner_upload_service.dart` (`uploadDocument`) · bucket `cleaner-documents`

## TL;DR
**Causa raiz: content-type inválido.** O upload do documento declarava `contentType: 'image/$safeExt'`,
que resultava quase sempre em **`image/jpg`** — e `image/jpg` **NÃO é um MIME válido** (o correto é
`image/jpeg`). O Supabase Storage compara o content-type declarado com os bytes reais (JPEG) → mismatch
→ **HTTP 400**. O upload do **avatar funciona (200)** precisamente porque envia `image/jpeg` fixo.

## Evidência (a do MCP + a do código)
- Logs Storage (fornecidos): `POST /storage/v1/object/cleaner-documents/<uid>/id_doc_*.jpg` → **400**;
  `POST .../avatars/...` → **200** na mesma sessão. Logo não é rede, nem RLS, nem bucket.
- Comparação no código — a **única** diferença de construção entre os dois uploads era o content-type:

| | Avatar (200 ✅) | Documento (400 ❌) |
|---|---|---|
| método | `uploadBinary(Uint8List)` | `uploadBinary(Uint8List)` |
| upsert | `true` | `true` |
| nome | `avatar.jpg` (fixo) | `id_doc_<ts>.jpg` (único) |
| **contentType** | **`'image/jpeg'`** (válido) | **`'image/$safeExt'` → `'image/jpg'`** (inválido) |

`safeExt` era `'jpg'` para jpg/jpeg/desconhecido → `'image/jpg'`. As hipóteses #1 (upsert/duplicado) e
#3 (bytes vazios) já estavam cobertas/eram improváveis (upsert=true + nome único). A causa era a #2.

## Correção (`cleaner_upload_service.dart` — só cliente; **NÃO** toquei bucket/RLS)
1. **MIME válido:** a extensão passa a mapear para um MIME correto —
   `png→image/png`, `webp→image/webp`, **jpg/jpeg/desconhecido→`image/jpeg`** (o padrão do avatar).
2. **Bytes > 0:** se a imagem vier vazia/ilegível, lança `empty_file` → mensagem clara em vez de 400 opaco.
3. **Erro real do Storage:** o `catch (StorageException)` imprime `status/error/message` reais
   (em vez do 400 opaco) — para diagnóstico futuro.

### Mensagens de erro (`cleaner_apply_screen.dart`)
- `empty_file` → *"Não foi possível ler a imagem do documento. Tira ou escolhe a foto de novo."*
- Duplicado → *"Este documento já tinha sido enviado. Tenta com outra foto."*
- Storage genérico → *"Falha ao enviar a foto do documento. Tenta escolher ou tirar a foto de novo."*
  (deixou de dizer "verifica a ligação à internet").

## Validação
- `dart analyze lib/services/cleaner_upload_service.dart lib/screens/cleaner/cleaner_apply_screen.dart`
  → **No issues found!**
- Chão anti-trapaça do Juiz → **CLEAN**.

## Teste no dispositivo (a fazer pelo Danilo com o próximo build)
1. Refazer a candidatura: foto de perfil + **documento** + zona base ("Rua do Torreão 14, Guarda") → Enviar.
2. Confirmar que o documento sobe (**200**) e que se cria linha em `cleaners` com `approval_status='pending'`.
3. Confirmar no admin (PT-BR) que a candidatura aparece com o documento visível (signed URL).

> Se ainda falhar, o novo log `[CleanerUploadService] doc upload 4xx status=… error=… msg=…`
> mostra a mensagem exata do Storage — manda-ma que aponto a causa em segundos.

## Regras respeitadas
Bucket e RLS **intocados** (estavam corretos). Sem zonas protegidas. `dart analyze` por ficheiro (máquina 4GB).
