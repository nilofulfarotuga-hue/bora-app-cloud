---
name: social-publisher
description: Agenda a publicação de uma campanha aprovada nas redes do Bora via Postiz (API/MCP). Use quando o Danilo aprovar uma campanha do diretor-criativo e pedir para agendar/publicar. Sem contas OAuth ligadas ou sem Postiz no ar, corre em dry-run (payloads JSON em marketing/fila-publicacao/). NUNCA cria contas; NUNCA publica sem aprovação explícita do Danilo.
metadata:
  type: marketing
  versao: 1
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: missao-noturna-2026-07-09
---

# Social Publisher — pipeline

## Pré-requisitos (verificar SEMPRE, por ordem)
1. **Aprovação explícita do Danilo** desta campanha ("vai", "aprovo", "agenda") — sem isso, PARA.
2. Postiz no ar? `GET http://localhost:5000/api/health` (ou URL em `infra/postiz-pc/.env`
   `POSTIZ_URL`). API key em `POSTIZ_API_KEY`.
3. Contas ligadas? `GET /api/public/v1/integrations` com a key → lista não vazia.
4. Falhou 2 ou 3 → **modo dry-run** (abaixo). Nunca inventar credenciais.

## Modo real (Postiz + contas OK)
1. Ler `marketing/campanhas/<slug>/calendario-sugerido.md` + `copy.md` + artes.
2. Para cada peça agendada: `POST /api/public/v1/posts` com imagem (upload prévio
   `POST /api/public/v1/upload`), copy do canal, data/hora **12h30 ou 19h30 Europe/Lisbon**,
   integração (IG/FB). Dias alternados por persona conforme o calendário.
3. Confirmar resposta 200 + guardar IDs dos posts em
   `marketing/campanhas/<slug>/publicacao-log.json`.
4. Resumo ao Danilo: N posts agendados, primeira e última data. NUNCA publicar "agora"
   sem o Danilo pedir explicitamente "publica já".

## Modo dry-run (default sem infra)
1. Gerar `marketing/fila-publicacao/<slug>-<data>.json`: array de
   `{canal, data_hora_lisboa, imagem_path, copy, persona, conceito}` — o payload EXATO
   que iria para o Postiz.
2. Dizer ao Danilo o que falta para sair de dry-run (Docker Desktop → compose up →
   OAuth 5 min — ver `infra/postiz-pc/README-POSTIZ.md`).

## Guardrails (lei)
- Publicação SÓ via API oficial do Postiz (que usa OAuth oficial das redes).
- NUNCA criar contas em redes sociais; NUNCA automação de browser para login.
- Conteúdo tem de vir de campanha que passou o gate do diretor-criativo (anti-slop + números).
- Peça alterada à mão depois do gate → volta ao diretor-criativo antes de agendar.

## Telemetria (fim de execução)
Incrementar frontmatter + linha em `.claude/.ai/knowledge/wiki/skills-metrics.md`.

## Admin Panel Needed?
Coberto pela proposta `AdminMarketingScreen` (inbox) — estados agendada/publicada vêm daqui.
