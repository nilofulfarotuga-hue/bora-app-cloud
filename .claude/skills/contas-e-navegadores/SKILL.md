---
name: contas-e-navegadores
description: >
  OBRIGATÓRIA antes de abrir QUALQUER site, painel ou página web. Dispara sempre que a tarefa falar de site, painel, login, sessão, navegador, Chrome, Edge, "entra em", "abre o", perfil, conta, ChatGPT, Gemini, Veo, Flow, Nano Banana, AI Studio, Google Ads, Search Console, Play Console, Firebase, Google Cloud, Gmail, Drive, Stripe, painel do Supabase, Cloudflare, Hostinger, hPanel, GitHub, Codemagic, Meta, Facebook, Instagram, WhatsApp Web, Apple, App Store Connect, Bing Webmaster, Wikidata, Canva, Resend, Postiz, claude.ai ou qualquer URL. O Danilo tem DOIS perfis do Chrome (Danilo = nilofulfarotuga; Bora = boraappbora) com contas diferentes em cada um, e o executor já abriu sites no perfil errado três vezes (14/09, 17/09 x2). Esta skill é o mapa: usa-se SEMPRE o abrir-site.ps1 e nunca se escolhe perfil ao calhas. Também para o agente de clique (extensão Claude in Chrome): escolher o navegador pelo deviceId, nunca pelo nome "Browser 1/2". REFORCO 17/09 (vigia): confirmar a conta e o plano no ecrã mesmo que a memória diga que já sabes; timeouts de CDP/screenshot e "0 width" são esperados — esperar e usar find/read_page em vez de declarar falha. REFORCO 25/09: CONTAS E NAVEGADORES — cada site no seu perfil. OBRIGATÓRIA antes de abrir QUALQUER site, painel ou página web. REFORÇO 25/09: se a aba estiver em segundo plano, 'esperar' não chega — o JavaScript pode ficar congelado e o CDP (Runtime.evaluate) estoura em timeout de 45s com 'renderer frozen or unresponsive'. Gatilho: CDP timeout, aba sem resposta, clique em botão (ex.: Enviar do Gemini modo Vídeos REFORCO 08/10: CONTAS E NAVEGADORES — cada site no seu perfil. Usa SEMPRE antes de abrir qualquer site, painel ou login. Também quando a captura de ecrã do navegador expira (Page.captureScreenshot timed out, renderer congelado): não repetir a mesma captura às cegas.
metadata:
  versao: 1.0
  criada: 2026-09-17
  criada_por: missão uma-porta-2026-09-17 (Claude Code, Opus)
  origem_da_queixa: "O Claude Code não sabe entrar no navegador correto. Tenho dois perfis, o Nilo Fufaro Tuga e o Bora App; umas coisas estão num, outras no outro, e ele confunde-se. Isso já devia ter virado uma skill." — Danilo, 17/09/2026
  execucoes: 1
  sucessos: 1
  falhas: 0
---

# CONTAS E NAVEGADORES — cada site no seu perfil

## 1. O que fazes SEMPRE, por esta ordem

1. **Corre o script antes de abrir o site** (nunca abras uma URL "à mão" no navegador):
   ```powershell
   powershell -NoProfile -File "$env:USERPROFILE\.claude\contas\abrir-site.ps1" <site-ou-URL>
   ```
   Devolve uma linha JSON com `perfil`, `pasta_perfil`, `deviceId`, `conta`, `plano`, `reserva`, `proibido`, `nota`.
   `-SoDizer` só imprime o caminho sem abrir nada. Códigos: `0` aberto no principal · `2` site fora do mapa · `3` sem sessão em lado nenhum · `1` erro.
   Se a sandbox bloquear o script (aconteceu numa sessão `claude -p` a 17/09), lê `~/.claude/contas/MAPA-CONTAS.json` com `Read` e usa a entrada do site e o `deviceId` de lá — o resultado é o mesmo.
2. **No agente de clique (extensão Claude in Chrome)**: `list_connected_browsers` → `select_browser` com o **`deviceId`** que o script devolveu. O nome "Browser 1/2" muda de sessão para sessão; o `deviceId` não.
3. **Confirma no ecrã** a conta e o plano (email no avatar, no rodapé ou no menu da conta) **antes** de gerar, escrever ou clicar. Se não bater com o mapa, **muda de perfil** — nunca faças login nem logout no perfil errado.
4. Trabalhaste num site que ficou diferente do mapa? **Atualiza o mapa** (§4).

## 2. O mapa em 12 linhas (a versão completa está em `~/.claude/contas/MAPA-CONTAS.md`)

- **Perfil Danilo** = pasta `Default`, conta Google nilofulfarotuga@gmail.com, deviceId `5b260cdd-9d4f-49d6-842b-ebfbfea69c75`.
- **Perfil Bora** = pasta `Profile 1`, conta Google boraappbora@gmail.com, deviceId `d9e862e0-a5ea-486f-b054-f333ef51b46a`.
- **ChatGPT Plus** = perfil Danilo, conta **nilofulfaro@gmail.com** (o do perfil Bora é **Free: proibido**). Texto e código vão por `opencode run -m openai/…` ou `codex exec` (mesma conta Plus), nunca pelo navegador.
- **Gemini AI Plus, Flow/Veo, AI Studio, Play Console, Meta/Instagram, WhatsApp da loja, Bing Webmaster, Wikidata, Resend, Drive da equipa, Gmail boraappbora** = perfil **Bora**.
- **Search Console e Google Ads** (jaiagarwala.com, conta 144-763-8091) = perfil **Danilo** (abre direto); reserva = perfil Bora com `?authuser=1`.
- **Firebase (projeto boraapp-d2bea, o da app), Google Cloud da app, Supabase (painel), Cloudflare (conta dos sites), GitHub, Gmail nilofulfarotuga/nilofulfaro** = perfil **Danilo**.
- **Sem sessão em nenhum perfil (17/09)**: Stripe, Hostinger, Codemagic, Canva, opencode.ai, Apple (expirou). Para esses: primeiro o caminho sem navegador (MCP Supabase, MCP Canva, ssh à VPS, chaves já existentes); só em último recurso **LOGIN NO NAVEGADOR PRÓPRIO**.
- **Navegador embutido da app Claude**: sem sessão nenhuma — só páginas públicas.
- **Edge**: danilofulfaro@hotmail.com, sem automação.

## 3. LOGIN NO NAVEGADOR PRÓPRIO (regra do Danilo, 13/09) — último recurso, nunca o primeiro
Sem sessão em lado nenhum? Não tentes senhas nem peças tokens. O script (rc 3) abre a página de login **no perfil certo** desse site; tu avisas o Danilo pelo Telegram **numa linha** ("abri o login do X no perfil Bora, entra tu"), saltas para o item seguinte e voltas quando a sessão existir. Fica gravada para sempre. Uma vez por site. Antes disso procura sempre a sessão que já existe (outro perfil, app do ChatGPT no Windows, `~/.codex/auth.json`, Edge).

## 4. Como atualizar o mapa (é DADOS, não é nota)
- Sessão nova confirmada no ecrã → edita a entrada do site em `~/.claude/contas/MAPA-CONTAS.json` (`principal`, `conta`, `plano`, `confirmado` com a data) e a linha correspondente do `MAPA-CONTAS.md`.
- Site fora do mapa → `abrir-site.ps1 <site> -Resultado "<perfil> <conta> <plano>"` grava em `descobertas.jsonl`; depois passa-se para o JSON.
- Espelha na página `mapa-sessoes-contas` da tabela `public.claude_ai_memoria` (Supabase `ojykpzwqrtusfeakzrna`) para o ChatGPT/OpenCode/Claude.ai verem o mesmo.
- Nunca escrevas senhas, tokens ou chaves no mapa.

## 5. Armadilhas provadas (não voltar a descobrir)
- O separador que a extensão cria nasce numa janela em **segundo plano**: as apps da Google (GSC, Ads, Bing) não renderizam e a captura falha com "0 width" enquanto o Danilo usa outro separador. **Esperar, não roubar o foco.**
- Se o Danilo mexe nos separadores, o grupo da extensão desaparece → `tabs_context_mcp` com `createIfEmpty` e continuar.
- `javascript_tool` é bloqueado em ads.google.com, business.facebook.com, opencode.ai e App Store Connect → usar `find`, `read_page`, `get_page_text`, captura.
- Enter chega com keyCode 0 nas apps da Google: GSC → `KeyboardEvent` keyCode 13; Ads → clicar na sugestão.
- App Store Connect: a extensão não lê a página; a sessão Apple expira em dias; senha e 2FA são do Danilo.
- A conta ChatGPT Plus tem limite semanal (Codex/opencode): quando esgota, a cascata da skill `distribuir-trabalho` desce para o próximo motor.

## 📊 Telemetria (no fim de cada uso)
Incrementa `execucoes` e `sucessos`/`falhas` no frontmatter; uma linha em `.claude/.ai/knowledge/wiki/skills-metrics.md` quando estiveres num repo do Bora.


## Reforco 17/09/2026 (vigia-habilidades)
> O Danilo corrigiu isto outra vez: regras-do-danilo (28/08, repetiu chateado): AGENTE DE CLIQUE — ele NÃO faz nada à mão em painéis web. Tem agente de clique no PC e dá permissão total... Nunca dar caminho de menus. | 2026-09-17T08:27:59 (digest-2026-09-17-claude-ai-uma-porta): O QUE O DANILO DISSE (17/09, chateado): (1) o Claude Code não sabe entrar no navegador certo — há dois perfis do Chrome... isso já devia ser skill. | 2026-09-17T08:27:59 (sistema-motores-e-portas): REGRA DO DANILO (17/09, repetida e chateado): ele não quer comandar várias ferramentas nem copiar e colar entre elas.

## Reforço — rotas de conta e falhas técnicas de browser

### Contradições já corrigidas 3x (não repetir)
- ChatGPT Plus = nilofulfaro@gmail.com, no perfil Danilo do Chrome e no app do Windows/Codex — NÃO é nilofulfarotuga (isso era conta Google, não ChatGPT) e NÃO é o perfil Bora (esse é Free).
- Perfil Danilo (Default) = nilofulfarotuga@gmail.com. Perfil Bora (Profile 1) = boraappbora@gmail.com.
- Nunca confiar no nome "Browser 1/2" da extensão — esses nomes mudam de sessão para sessão; usar sempre o deviceId fixo do MAPA-CONTAS.json.
- Antes de abrir qualquer site: correr abrir-site.ps1 <site>, confirmar conta e plano no ecrã, e SÓ DEPOIS agir.

### Armadilhas técnicas repetidas (7 dias, centenas de ocorrências)
- CDP `Page.captureScreenshot`/`Runtime.evaluate` timeout (41x/18x): o separador da extensão nasce em segundo plano — esperar antes de agir, não repetir a chamada imediatamente.
- Screenshot com 0 width (10x): página ainda não renderizou (comum em apps Google) — esperar e tentar de novo, ou usar find/read_page em vez de screenshot.
- "Tab is not in Claude's tab group" (34x): reler tabs_context_mcp antes de qualquer ação, não assumir a tab da última vez.
- "Multiple Chrome browsers connected, none selected" (7x): chamar select_browser com o deviceId certo ANTES de qualquer ação — nunca perguntar ao Danilo qual é.


## Reforco 25/09/2026 (vigia-habilidades)
> O Danilo corrigiu isto outra vez: periodo 23-25/09/2026 (e2e/sessao): 6x em 2 sessoes/2 dias: Failed to execute JavaScript: CDP sendCommand "Runtime.evaluate" timed out after 45000ms on tab [TELEFONE]. The renderer may be frozen or unresponsive. | 2026-09-24 (digest-2026-09-24-banco-pecas): a aba do Gemini fica em segundo plano e congela o JavaScript; resolve-se trazendo a janela à frente; o clique por JS no botão Enviar do modo Vídeos não envia, só o clique real

## Reforço 25/09/2026 — aba em segundo plano trava o render

Visto 6x em 2 sessões/2 dias (25/09): `CDP sendCommand "Runtime.evaluate" timed out after 45000ms ... The renderer may be frozen or unresponsive`. Confirmado pela lição de 24/09 (banco-pecas): a aba do Gemini em segundo plano congela o JavaScript.

**Regra:** antes de qualquer ação na aba (ler, clicar, escrever), traz a janela do navegador para PRIMEIRO PLANO — não bastar esperar. Depois disso:

- Clique em botões de ação (ex.: "Enviar" no modo Vídeos do Gemini) tem de ser um **clique real** (mouse/click da ferramenta de automação), nunca um `click()` disparado só por JavaScript — o clique por JS pode não disparar o handler e o pedido nunca sai, sem erro visível.
- Se mesmo assim vier timeout de CDP/Runtime.evaluate, não repetir o mesmo comando às cegas: trazer a aba à frente de novo e confirmar visualmente antes de tentar outra vez.



## Reforco 08/10/2026 (vigia-habilidades)
> O Danilo corrigiu isto outra vez: 

## Reforço: captura de ecrã que expira (erro visto em 2 sessões/2 dias, até 08/10/2026)

Erro literal: `Error capturing screenshot: CDP sendCommand "Page.captureScreenshot" timed out after 30000ms on tab ... The renderer may be frozen or unresponsive.`

O que fazer:
1. Não repetir a mesma captura à espera que passe.
2. Ler a página por texto (`read_page` ou `find`), que não depende do renderizador.
3. Se o separador estiver congelado, abrir um separador novo no perfil certo com `~/.claude/contas/abrir-site.ps1 <site>` e esperar a página renderizar. O separador da extensão nasce em segundo plano e apps Google precisam de tempo.
4. O PC tem 4 GB. Antes de insistir, medir `(Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes`. Se estiver baixo, fechar separadores e MCPs que não servem (playwright, nano-banana).
5. Se continuar a falhar, regista-se o separador e o perfil, e segue-se com as outras tarefas. Não se muda de perfil ao calhas.
