---
id: teste-vps-cloudflare-2026-07-14
tipo: relatorio
zona: verde (infra/diagnostico; nada de dinheiro tocado, auth NAO completada de propósito)
criada: 2026-07-14
autor: claude.ai (missão "Teste Passo 1 — VPS Hostinger consegue autenticar Claude Code?")
---

# Teste Passo 1 — VPS Hostinger (srv1786862.hstgr.cloud) consegue autenticar o Claude Code?

## Objetivo
Descobrir se a Cloudflare bloqueia o IP de datacenter da VPS Hostinger (`187.124.1.156`)
no fluxo de autenticação do Claude Code (problema conhecido com IPs de datacenter,
Issue #21678 do GitHub), **sem** migrar nada nem completar a autenticação.

## 1) Node.js e Claude Code CLI instalados?
Não estavam no host da VPS (só existia um shim `claude` dentro do container
`hermes-agent-fvnc-hermes-agent-1`, propositadamente redirecionado para a ponte PC —
comentário no próprio script diz "NAO esta logado", ou seja, já tinha sido decidido antes
não autenticar ali).

**Instalado agora no host da VPS** (Ubuntu 24.04.4 LTS):
- Node.js **v22.23.1** via NodeSource (`setup_22.x`)
- `@anthropic-ai/claude-code` **v2.1.209** via `npm install -g`

## 2) Teste de conectividade (o teste CHAVE)
Curl a partir do IP público da VPS (`187.124.1.156`) a vários endpoints Anthropic:

| Endpoint | HTTP | Cloudflare? |
|---|---|---|
| `platform.claude.com` | 200 | limpo |
| `claude.ai` | **403** | **BLOQUEADO — `cf-mitigated: challenge`, body "Just a moment..." (managed challenge JS)** |
| `console.anthropic.com` | 301 (redirect normal) | limpo |
| `api.anthropic.com` | 404 (normal, raiz sem rota) | limpo |
| `claude.com` (apex) | 200 | limpo |
| `claude.com/cai/oauth/authorize?...` | 307 → redireciona para `claude.ai/oauth/authorize?...` | o destino final É o domínio bloqueado |
| `platform.claude.com/oauth/code/callback` (destino do `redirect_uri` do OAuth) | 200 | limpo |

**Confirmado:** a Cloudflare bloqueia `claude.ai` a partir do IP da VPS com um challenge
JS interativo ("Just a moment..."), exatamente o padrão do Issue #21678 (IPs de
datacenter/hosting). Isto bate certo com o `claude.com/cai/oauth/authorize` redirecionar
para `claude.ai/oauth/authorize` — ou seja, o ecrã de login em si vive num domínio
bloqueado para este IP.

## 3) `claude setup-token` — gerou URL ou falhou logo?
**GEROU A URL COMPLETA**, sem qualquer erro de rede. Corrida via SSH com pty (`script` +
`timeout 20s`, sem completar):
```
Opening browser to sign in…
Browser didn't open? Use the url below to sign in (c to copy)
https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-...
  &response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback
  &scope=user%3Ainference&code_challenge=...&code_challenge_method=S256&state=...

Paste code here if prompted >
```
O comando ficou à espera do código colado (killed pelo `timeout`, exit 124 — **de propósito,
sem colar nada**). Nenhuma credencial parcial ficou gravada: `~/.claude/.credentials.json`
não existe, `~/.claude.json` só tem metadata local (sem token/oauth), sem processo residual.

**Porquê não bloqueou aqui:** a geração da URL (PKCE `code_challenge` + montagem do link) é
**100% local**, zero chamada de rede — por isso não esbarra na Cloudflare nesta etapa.

## 4) O que isto significa na prática (a parte nuançada)
O fluxo do `setup-token` tem 2 pernas de rede distintas:
1. **Abrir a URL e autorizar** — feito no **browser do Danilo** (telemóvel/PC dele), com o
   IP **dele**, não o da VPS. O bloqueio da Cloudflare a `claude.ai` **não entra aqui**,
   porque quem visita `claude.ai/oauth/authorize` é o browser do Danilo, não a VPS.
2. **Colar o código de volta na VPS** — a VPS faz então uma chamada de rede para trocar o
   código por um token (exchange). Não cheguei a essa chamada (parei antes, como pedido),
   mas os sinais indiretos são bons: o `redirect_uri` (`platform.claude.com/oauth/code/callback`)
   e o domínio `platform.claude.com` em geral respondem **limpos (200, sem challenge)** a
   partir do IP da VPS — sugerindo que a troca de código por token (que passa por
   `platform.claude.com`, não por `claude.ai`) provavelmente **não** esbarra na Cloudflare.

## Conclusão

**VPS HOSTINGER AUTENTICAÇÃO: viável (gerou URL completa, chegou ao prompt de colar código;
o único domínio bloqueado — `claude.ai` — só é visitado pelo browser do Danilo, não pela VPS).**

**Próximo passo recomendado:** completar o Passo 2 — o Danilo abre a URL gerada
(válida por tempo limitado, por isso precisa de ser gerada de novo nessa altura) no
telemóvel dele, autoriza, copia o código de `platform.claude.com/oauth/code/callback?code=...`
e cola-o de volta no `claude setup-token` a correr na VPS via SSH. Se essa troca de código
por token também passar (o que os sinais de rede sugerem), a VPS fica autenticada e o
caminho Hostinger-VPS como executor alternativo/redundante ao PC fica confirmado como viável.
