# README — force-driver-logout

Força logout de um estafeta (emergência) via Edge Fn `admin-force-driver-logout`.

## Instalação / ambiente
`.env`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (leitura do
driver) + **JWT de admin** (`BORA_ADMIN_JWT` ou `BORA_ADMIN_EMAIL`+`BORA_ADMIN_PASSWORD`).
A Edge Fn exige `app_metadata.role='admin'` no JWT — **não** aceita service_role.

```bash
python -m venv .venv && .venv\Scripts\activate && pip install -r requirements.txt
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S2 (Ctx/log/get_admin_jwt) |
| `logout.py` | preview (default) / executa com `--confirm`; `--force-anyway` ignora pedido em curso |

## Notas
- Toda a escrita (sessões, fcm, is_online, `last_forced_logout_*`, auditoria) é feita
  **pela Edge Fn**. Esta skill apenas valida, chama e verifica `is_online=false`.
- `--driver-id` tem de ser UUID válido.
