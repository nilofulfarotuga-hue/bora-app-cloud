---
name: lancar-missao-claude-code
description: Procedimento certo para lançar uma missão grande no Claude Code do navegador para o Danilo — e como chegar ao PC dele por Controlo Remoto quando uma sessão morre (o PC está quase sempre ligado; ecrã preto não é PC desligado).
---

# Lançar missão no Claude Code (caminho certo)

1. Escrever o prompt completo (regras do Danilo: MODO PROTECÇÃO TOTAL, CEO-AI, motor no topo, /ctx doctor e /ctx stats no fim).
2. Pôr o prompt como ficheiro PROMPT_<nome>_<data>.md na raiz do repo:
   - bora-app-cloud, ramo autonomous-night-2026-04-29 (push pela VPS ou GitHub web);
   - em-dia-app, ramo main: SÓ pelo GitHub web no Chrome (a chave da VPS só lê).
3. Abrir claude.ai/code no Chrome, escolher repo + ramo; nuvem (Default) salvo se precisar do PC (aí Controle Remoto, claude rc).
4. Escrever na caixa com type uma frase curta: "Lê PROMPT_<nome>.md na raiz e executa bloco a bloco". Colar texto grande por JS é bloqueado.
5. O Enter é bloqueado: pôr o separador à frente e dizer ao Danilo só "carrega Enter".
6. Vigiar pelo e2e_log (run_id da missão) e aplicar por MCP o que vier bloqueado.
7. NUNCA mandar missão grande pelo cortex_nova_ordem (loop).

## Chegar ao PC do Danilo

> Escrito 2026-09-28 por ordem do Danilo: "grava esse caminho para não falar mais que o
> computador está desligado". Cicatriz do mesmo dia: a sessão "PC do Danilo" morreu com
> "OAuth session expired", o controlo de computador mostrava ecrã preto e o e2e_log ficou
> com "PC bloqueado/monitor desligado" (fluxo jai-mes2-28-09, passo pc-sessao, id 2565).
> O PC estava ligado (14 GB, 1,3 GB livres, Chrome com 22 processos): uma sessão nova por
> Controlo Remoto entrou à primeira e fez os blocos B a E da missão.

- **O PC do Danilo está quase sempre LIGADO.** Presume-se ligado até prova em contrário
  (uma sessão nova que não arranca, não uma sessão velha que morreu).
- **Ecrã preto no controlo de computador = filtro que esconde janelas não autorizadas.**
  NÃO é PC bloqueado nem desligado. **Nunca dizer ao Danilo "desbloqueia o Windows"** nem
  "liga o computador".
- **Sessão "PC do Danilo" que diz "não é possível conectar ao seu computador", "OAuth
  session expired" ou "janela de contexto cheia": essa SESSÃO morreu, o PC está vivo.**
  Não se insiste nela nem se espera por ela — abre-se sessão nova:
  1. claude.ai/code no Chrome, **perfil pessoal** (nilofulfarotuga, deviceId
     `5b260cdd-9d4f-49d6-842b-ebfbfea69c75`);
  2. **Novo** → botão do ambiente → **"Controlo Remoto"** → **"bora-app-cloud · Danilo"**;
  3. colar o prompt → **Enter**.
- **Publicar site ou tocar em segredos exige "autorizo publicar" escrito pelo Danilo nessa
  conversa.** Cita-se a frase e a hora no topo do prompt (ex.: 28/09/2026 18:51, "eu autorizo
  publicar no site do Jai. E fazer tudo o que tem que fazer"). Sem a frase, prepara-se tudo
  e não se publica.
- **O que a sessão por Controlo Remoto tem e não tem** (medido 28/09/2026): tem o disco do
  PC, PowerShell/Bash, Python com Playwright + Chrome headless, SSH à VPS
  (`ssh -i ~/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud`), wrangler, MCP Supabase e
  os conectores claude.ai. **Não tem a extensão do Chrome** (sem select_browser/navigate):
  tudo o que exige site com sessão iniciada (Search Console, Bing Webmaster, Google Ads,
  Meta, Apple) fica para a Claude.ai com a extensão, e regista-se no e2e_log como
  `bloqueado` com esta razão, sem parar o resto da missão.
