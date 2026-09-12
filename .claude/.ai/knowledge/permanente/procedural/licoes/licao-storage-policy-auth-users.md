---
tema: licao-storage-policy-auth-users · escopo: projeto · estado: atual · atualizado: 2026-07-06
id: licao-storage-policy-auth-users
tipo: licao
origem: [commit 6b0cda3, supabase/migrations/20260706224707_cleaner_docs_admin_policy_jwt.sql]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# Lição — policies de Storage NUNCA consultam `auth.users` (e "funciona no bucket X" não prova autenticação)

**Origem:** bug do upload de documento KYC da Limpeza (bucket `cleaner-documents`), 2026-07-06.
Falhava 100% com HTTP 400 opaco. Causa provada por reprodução curl.
**Evidência:** commits `6b0cda3` (fix) + `364ca94` (relatório `relatorios/limpeza-upload-doc-2026-07-06.md`),
migration `supabase/migrations/20260706224707_cleaner_docs_admin_policy_jwt.sql` (aplicada em prod —
consertou a build instalada sem novo APK). Branch `autonomous-night-2026-04-29`.

## Causa raiz
- A policy de SELECT `admin_read_all_cleaner_docs` fazia `EXISTS(SELECT 1 FROM auth.users ...)`.
- O role `authenticated` **NÃO tem SELECT em `auth.users`**.
- Como o app enviava `upsert: true`, o Postgres avaliava também as policies SELECT/UPDATE do bucket
  no INSERT (ON CONFLICT) → `permission denied for table users` → o storage-api embrulha em **HTTP 400**.

## Regras práticas
1. Em policies de `storage.objects`, **NUNCA** subquery a `auth.users`. Usar o claim do JWT:
   `auth.jwt() -> 'app_metadata' ->> 'role'` (= `raw_app_meta_data`).
2. `upsert: true` só quando o path pode colidir (ex.: avatar fixo `$uid/avatar.jpg`).
   Path com timestamp → **sem upsert** (evita avaliar policies SELECT/UPDATE desnecessariamente).
3. **Anti-padrão de diagnóstico:** "o bucket `avatars` funciona, logo a sessão está OK" era falso —
   `avatars` tem policies `{authenticated, anon}` sem check de pasta (aceita escrita ANÓNIMA).
   Comparar buckets exige comparar as **POLICIES**, não só o código Flutter.

## ⚠️ Achado de segurança em aberto (PROPOSE-ONLY — Danilo decide)
As policies de escrita do bucket `avatars` permitem a qualquer portador da **anon key** fazer
upload/update/delete de **QUALQUER** avatar. Registado como pendência em
`permanente/episodica/auditoria-360.md` (P0 #4). Não corrigir sem "vai" do Danilo.
`estado: atual`
