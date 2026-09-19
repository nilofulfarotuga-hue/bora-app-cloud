# Postiz no PC — guia do Danilo

## Porquê no PC e não na VPS
Regra da missão: só instalar na VPS com **≥2.5 GB RAM livre e ≥10 GB disco**.
Medido em 2026-07-10: RAM disponível **2.3 GiB** (total 3.8 Gi) — reprovado; disco 35 G OK.
Instalar ao lado do Hermes arriscava o bot. Fica pronto para o PC (ou para quando a VPS
tiver upgrade de RAM — o mesmo compose serve, mudando MAIN_URL para o domínio + proxy HTTPS).

## Arranque (10 min, uma vez)
1. Instala Docker Desktop: `winget install Docker.DockerDesktop` → abre e espera "running".
2. Nesta pasta: cria `.env` com:
   ```
   JWT_SECRET=<cola aqui 40+ caracteres aleatórios>
   POSTGRES_PASSWORD=<password local qualquer>
   ```
   (o `.env` está no .gitignore — nunca vai para o git)
3. `docker compose up -d` → abre http://localhost:5000 e cria a conta admin local.

## 🧑‍💼 PASSO HUMANO — ligar as contas do Bora (5 min)
> Automação NUNCA cria contas nem faz login por ti. Isto és tu, uma vez, via OAuth oficial.
1. No Postiz: **Settings → Channels → Add Channel**.
2. **Instagram Business**: escolhe Instagram → login Facebook → seleciona a Página de
   Facebook do Bora + a conta Instagram Business ligada a ela → autoriza.
   (Requisito: o Instagram do Bora tem de estar em modo Business e ligado à Página FB —
   faz-se na app do Instagram em Definições → Conta → Mudar para conta profissional.)
3. **Facebook Page**: escolhe Facebook → autoriza → seleciona a Página do Bora.
4. (Opcional) TikTok: igual, via OAuth TikTok.
5. Diz ao Claude/Hermes "contas ligadas" → a skill `social-publisher` sai de dry-run.

## API para os agentes
- Postiz expõe API REST (Settings → API Key) e tem MCP server próprio.
- Guarda a API key em `infra/postiz-pc/.env` como `POSTIZ_API_KEY=...` — a skill
  `social-publisher` lê daí. Nunca no git.

## Estado atual
- [x] compose pronto e validado sintaticamente
- [ ] Docker Desktop instalado no PC (PENDENTE-HUMANO — instalador pede interação)
- [ ] contas OAuth ligadas (PENDENTE-HUMANO)
- Até lá: `social-publisher` corre em **dry-run** → payloads em `marketing/fila-publicacao/`
