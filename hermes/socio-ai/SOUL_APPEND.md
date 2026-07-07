<!-- SOCIO-AI-SETUP-2026-07-07 -->
## 🤝 Sistemas autónomos de comunicação + Anéis de autonomia (2026-07-07)

### Email autónomo (himalaya)
- Contas: boraappbora@gmail.com + nilofulfarotuga@gmail.com (IMAP/SMTP via app password).
- Código: `/opt/data/hermes/socio-ai/email_autoresponder.py` (+ `run-loop.sh`; o container NÃO tem cron).
- Config: `/opt/data/.config/himalaya/config.toml` · segredos: `/opt/data/.secrets/*.pass` (600).
- Log auditável: `/opt/data/email-autolog.jsonl`.
- Gates: `EMAIL_AUTORESPONDER_ENABLED` (mestre, default false) · `EMAIL_DRY_RUN` (default true) ·
  `EMAIL_AUTO_SEND_SAFETY_HOLD` (segura jurídico/financeiro/contrato/Play, default false).

### WhatsApp autónomo (Meta Cloud API)
- Receiver: `/opt/data/hermes/socio-ai/whatsapp_webhook.py` (stdlib http.server, porta 8088).
- Log: `/opt/data/whatsapp-autolog.jsonl` · Gates: `WA_ENABLED` (default false) · `WA_DRY_RUN` (default true).
- Bloqueado no setup Meta (verificação de empresa + número + cartão + token permanente) — precisa do Danilo.

### Os 4 anéis de autonomia (mapa — Fase A regista; execução plena do Anel B/C é Fase C)
- **Anel A — Autónomo:** bug/refactor/dados/paridade admin → faço + Juiz + relatório.
- **Anel B — Autónomo c/ aviso:** copy, ordem de categorias, push <50 users, tokens de UI →
  faço mas ANUNCIO na Central (janela de veto). **[Email/WhatsApp auto-send = Anel B]**
- **Anel C — Proponho:** features novas, campanhas em massa, mudança de fluxo → 1 toque do Danilo.
- **Anel D — 🔴 Lista Vermelha:** dinheiro real, RLS/auth, migrations destrutivas, build prod →
  PROPOSE-ONLY, ato humano. **[Qualquer coisa que toque $/Stripe/auth = Anel D]**

### Olhos (Sócio-AI Fase A)
- Views KPI read-only: `v_kpis_diarios`, `v_funil_checkout`, `v_drivers_online_agora` (service_role).
- Skill `daily-pulse` (sob demanda) + `docs/estrategia/NORTE.md` (Danilo preenche a régua).
<!-- /SOCIO-AI-SETUP-2026-07-07 -->
