# Limpeza — Upload do documento da candidatura (HTTP 400) — RESOLVIDO

**Data:** 2026-07-06 · **Commit:** `6b0cda3` · **Branch:** `autonomous-night-2026-04-29`
**Migration aplicada em prod:** `20260706224707_cleaner_docs_admin_policy_jwt`

---

## Causa raiz REAL (provada por reprodução, não por hipótese)

O erro real que o Storage devolvia (capturado com `curl`, JWT válido, request
idêntico ao do app com `x-upsert: true`):

```
HTTP 400 → {"statusCode":"403","error":"Unauthorized","message":"permission denied for table users"}
```

**Não era MIME** (commit anterior `cca53c3` mirou no lugar errado), **não era o
JWT em falta**, **não era o path**. Era a policy de SELECT do próprio bucket:

- `admin_read_all_cleaner_docs` fazia `EXISTS (SELECT 1 FROM auth.users WHERE ... raw_app_meta_data->>'role' = 'admin')`.
- O role `authenticated` **não tem privilégio de SELECT em `auth.users`**.
- Como o app enviava `upsert: true`, o Postgres avaliava também as policies de
  SELECT/UPDATE do bucket (INSERT … ON CONFLICT). Ao tocar na subquery de
  `auth.users` → `permission denied for table users` → o storage-api embrulha
  em HTTP 400. Falhava 100% das vezes, para qualquer utilizador.
- Bónus descoberto: o **painel admin também ia rebentar** ao criar signed URLs
  dos documentos (mesma policy avaliada no SELECT). Ficou corrigido pelo mesmo fix.

## Porque é que o avatar "funcionava"

Diff avatar-vs-documento (a pergunta do briefing):

| | `avatars` | `cleaner-documents` |
|---|---|---|
| Cliente Supabase | `Supabase.instance.client` (o mesmo) | o mesmo |
| Método | `uploadBinary` + bytes de `XFile.readAsBytes()` | igual |
| Path | `$uid/avatar.jpg` (uid = `auth.currentUser.id`) | `$uid/id_doc_<ts>.jpg` (igual) |
| ContentType | `image/jpeg` | `image/jpeg`/`png`/`webp` (válidos) |
| **Policy INSERT** | **`avatars_anon_insert` — roles `{authenticated, anon}`, sem check de pasta** | `{authenticated}` + pasta = `auth.uid()` |
| **Policy SELECT com subquery a `auth.users`** | **não tem** | tinha (`admin_read_all_cleaner_docs`) |

Ou seja: o código Flutter dos dois uploads era **igual e correto**. O avatar
funcionava porque o bucket `avatars` aceita escrita até anónima e não tem
nenhuma policy que toque `auth.users`. Nota: no fluxo multi-papel
(estafeta→limpeza) o upload do avatar nem sequer corre (foto pré-preenchida) —
"o avatar funciona" nunca tinha provado autenticação nenhuma.

Provas por curl:
- anon → `avatars`: **200** (!)
- anon → `cleaner-documents`: 400 `new row violates row-level security policy`
- JWT válido + `x-upsert` → `cleaner-documents`: 400 `permission denied for table users` ← **o erro do app**
- JWT válido sem `x-upsert`: **200** (confirma o mecanismo do upsert)
- **Pós-fix**, JWT válido + `x-upsert` (request idêntico ao app): **200** ✅
- **Pós-fix**, signed URL do documento: **200** ✅

## O que foi mudado

1. **Servidor (raiz)** — migration `20260706224707_cleaner_docs_admin_policy_jwt`
   (aplicada em prod + versionada no repo): a policy `admin_read_all_cleaner_docs`
   passou a ler `auth.jwt() -> 'app_metadata' ->> 'role' = 'admin'` (claim do
   JWT, semanticamente igual a `raw_app_meta_data`, sem tocar `auth.users`).
   Confirmei que os admins têm mesmo `role=admin` no `raw_app_meta_data`
   (nilofulfarotuga@gmail.com + e2e_admin), portanto a policy continua a servir.
   **➜ A build já instalada no telemóvel fica corrigida SEM novo APK.**
2. **`lib/services/cleaner_upload_service.dart`** — removido o `upsert: true`
   do upload do documento (path tem timestamp, nunca há conflito; era o gatilho
   da avaliação das policies SELECT/UPDATE). Comentário do falso diagnóstico
   MIME substituído pela causa real.
3. **`lib/screens/cleaner/cleaner_apply_screen.dart`** — o toast de falha de
   upload passa a incluir `[statusCode: mensagem]` reais do `StorageException`
   (nunca mais debugar às cegas).

## Validação

- `flutter analyze` nos 2 ficheiros tocados: **No issues found**.
- `anti_trapaca.py --base HEAD`: chão limpo (0 testes tocados).
- Reprodução end-to-end pós-fix (request idêntico ao do app): **HTTP 200**.
- Limpeza: user de teste + 2 objetos de prova apagados; probe do bucket
  avatars apagado. Zero lixo deixado em prod.

## ⚠️ Achado de segurança (não corrigido — fora do âmbito, decisão tua)

As policies do bucket `avatars` (`avatars_anon_insert/update/delete/select`,
roles `{authenticated, anon}`, check apenas `bucket_id='avatars'`) permitem que
**qualquer pessoa com a anon key faça upload, substitua ou apague qualquer
avatar de qualquer utilizador** (verifiquei na prática: upload e delete anónimos
deram 200). Recomendo restringir à pasta do próprio (`foldername[1] = auth.uid()`)
num próximo lote — não mexi porque alterava um fluxo que hoje funciona e não
fazia parte desta tarefa.
