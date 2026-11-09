# zerar-2026-11-02 — o que ficou por correr (B1, chaves antigas)

Os scripts desta pasta trocam a chave do servidor nos `.env` da VPS **sem nunca a mostrar**.
O classificador recusou a escrita remota a 02/11 (ver `docs/TRANCAS.md`); correr de uma sessão com a
VPS liberada, a partir da raiz do repo no PC:

```bash
set -a; . /c/BoraLocal/projetosflutter/bora_app/.supabase-token.env; set +a
scp -i ~/.ssh/id_ed25519_vps docs/propostas/zerar-2026-11-02/trocar_env.py root@srv1786862.hstgr.cloud:/root/trocar_env_20261102.py
node docs/propostas/zerar-2026-11-02/chave_secreta_stdout.mjs \
  | ssh -i ~/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud \
    'python3 /root/trocar_env_20261102.py /opt/whatsapp-bora/.env /opt/assistente-negocio/.env && rm -f /root/trocar_env_20261102.py && systemctl restart whatsapp-cerebro assistente-negocio'
```

- `chave_secreta_stdout.mjs` lê a secreta nova `default` pela Management API e escreve-a só para o pipe.
- `trocar_env.py` (VPS) / `trocar_env.mjs` (PC) trocam o valor de `SUPABASE_SERVICE_ROLE_KEY`, guardam
  `<ficheiro>.bak-legada-20261102` e imprimem só os prefixos.
- Provado a 02/11 a partir do banco: o REST aceita a `sb_secret` em `apikey` + `Authorization: Bearer`, que é
  como os dois serviços a mandam (`cerebro/supa.py`, `assistente-negocio/db.py`).

Depois: segredo do GitHub `SUPABASE_SERVICE_ROLE_KEY`, o passo (b) quando a Apple aprovar e o (c) — tudo em
`docs/SEGURANCA-CHAVES.md`, secção "Troca do servidor — 02/11/2026".
