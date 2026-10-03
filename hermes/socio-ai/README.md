# Sócio-AI — Email + WhatsApp autónomos (Hermes VPS)

Artefactos **versionados** aqui; **implantados** no container `hermes-agent-fvnc-hermes-agent-1`
em `/opt/data/hermes/socio-ai/`. Nada disto envia mensagens sozinho até o Danilo (1) injetar os
segredos e (2) validar em dry-run e ligar o interruptor mestre.

## Estado ao fim da noite (2026-07-07)
- ✅ Código + config no repo e no container.
- ✅ himalaya v1.2.0 já instalado no container; `config.toml` colocado.
- ✅ Pasta `/opt/data/.secrets/` (700) + ficheiros de segredo VAZIOS (600) criados.
- ⛔ **Bloqueado (precisa do Danilo):** app passwords Gmail (2FA), todo o setup Meta/WhatsApp.
- 🛡️ Defaults SEGUROS: `EMAIL_AUTORESPONDER_ENABLED=false`, `EMAIL_DRY_RUN=true`,
  `WA_ENABLED=false`, `WA_DRY_RUN=true`. Nada sai sem o Danilo mudar isto.

---

## PARTE 1 — Email (ativação, quando o Danilo estiver disponível)

**🖐️ Passo 1 — gerar as 2 app passwords** (precisa do 2FA do telemóvel dele):
- `https://myaccount.google.com/apppasswords` logado como `boraappbora@gmail.com` → gerar "Hermes VPS".
- Repetir logado como `nilofulfarotuga@gmail.com`.

**🖐️ Passo 2 — injetar cada uma no container (nunca no chat):**
```bash
# a partir do PC, o valor viaja pela pipe (não pelo argv/histórico):
echo -n 'APP_PASSWORD_16_CHARS' | ssh -i ~/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud \
  'docker exec -i -u hermes hermes-agent-fvnc-hermes-agent-1 /opt/data/hermes/socio-ai/inject-app-password.sh gmail_boraapp'
# idem para gmail_cloudflare
```

**Passo 3 — validar leitura (sem enviar):**
```bash
docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 himalaya envelope list -a boraapp
docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 python3 /opt/data/hermes/socio-ai/email_autoresponder.py --selftest
```
> Se `envelope list` der erro de config, trocar `auth.cmd`→`auth.command` no config.toml (nota de versão lá dentro).

**Passo 4 — dry-run (gera rascunhos, NÃO envia) e inspecionar o log:**
```bash
# ligar o mestre mas manter dry-run:
#   no /opt/data/.env:  EMAIL_AUTORESPONDER_ENABLED=true   (EMAIL_DRY_RUN fica true)
docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 python3 /opt/data/hermes/socio-ai/email_autoresponder.py
docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 tail /opt/data/email-autolog.jsonl
```

**Passo 5 — ir a sério (auto-envio total, como o Danilo pediu):**
- No `/opt/data/.env`: `EMAIL_DRY_RUN=false` (mantém `EMAIL_AUTORESPONDER_ENABLED=true`).
- Arrancar o loop (o container não tem cron):
```bash
docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 \
  bash -lc 'nohup /opt/data/hermes/socio-ai/run-loop.sh >> /opt/data/logs/email-loop.log 2>&1 &'
```
- **Safety hold opcional:** `EMAIL_AUTO_SEND_SAFETY_HOLD=true` segura emails com gatilhos
  jurídico/financeiro/contrato/Play policy para revisão (default `false`, conforme pedido).

---

## PARTE 2 — WhatsApp (Meta Cloud API) — bloqueado em vários pontos externos

Ordem (a maioria é 🖐️ Danilo + revisão da Meta, que demora dias):
1. 🖐️ `developers.facebook.com` → Meta App → produto WhatsApp.
2. 🖐️ **Verificação de empresa** (business.facebook.com) — upload de docs. Meta revê (dias).
3. 🖐️ Adicionar **número novo** + confirmar SMS.
4. 🖐️ Adicionar **cartão** na conta WhatsApp (decisão financeira — só o Danilo).
5. Criar **System User** + **token permanente** (`whatsapp_business_messaging` + `_management`).
6. Injetar `WA_ACCESS_TOKEN`, `WA_PHONE_NUMBER_ID`, `WA_VERIFY_TOKEN` no `.env` do container.
7. Arrancar o receiver + expor por HTTPS (traefik já corre no VPS):
```bash
docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 \
  bash -lc 'nohup python3 /opt/data/hermes/socio-ai/whatsapp_webhook.py >> /opt/data/logs/wa-webhook.log 2>&1 &'
```
8. 🖐️ Colar a URL pública em WhatsApp → Configuration e clicar "Verify and save".

O receiver **arranca e valida o challenge mesmo sem token** — só não envia (loga `no_token`).

---

## Logs auditáveis
- Email: `/opt/data/email-autolog.jsonl`
- WhatsApp: `/opt/data/whatsapp-autolog.jsonl`
- Loops: `/opt/data/logs/email-loop.log`, `/opt/data/logs/wa-webhook.log`

## Painel admin (paridade — pendente, ver relatório)
Os logs vivem no VPS, não no Supabase; o container **não tem** `SUPABASE_SERVICE_KEY`.
Para o admin Flutter os ver: ou (a) adicionar a chave e o engine escreve também na tabela
`comms_autolog`, ou (b) um endpoint read-only. Detalhe e decisão no relatório final.
