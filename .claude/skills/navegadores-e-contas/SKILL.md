---
name: navegadores-e-contas
description: Escolher o perfil certo do Chrome (sempre pelo deviceId, nunca pelo nome "Browser 1/2") antes de abrir qualquer site, painel ou login. Usa-se em toda a missão que toque em Apple, Meta/Instagram, Play Console, Cloudflare, Supabase, Resend, Search Console, GitHub, Gemini ou ChatGPT.
---

# Navegadores e contas — qual perfil, para que site

> Escrito 2026-09-24 (missão `fecho-total-2026-09-24`). Substitui o hábito de "abrir o
> Chrome e ver no que dá". Manda sobre qualquer instrução antiga que diga "Browser 1".

## A regra de uma linha

**O nome "Browser 1" / "Browser 2" TROCA entre sessões. O `deviceId` não.** Escolhe-se
sempre pelo `deviceId`; escolher pelo nome é como escolher uma chave pela cor.

## Os dois perfis

| Perfil | `deviceId` | Pasta do Chrome | Conta |
|---|---|---|---|
| **Bora** | `d9e862e0-a5ea-486f-b054-f333ef51b46a` | `Profile 1` | boraappbora@gmail.com |
| **Pessoal (Danilo)** | `5b260cdd-9d4f-49d6-842b-ebfbfea69c75` | `Default` | nilofulfarotuga@gmail.com |

### O que vive no perfil **Bora**

Apple (App Store Connect e portal), Meta e Instagram, Google Play Console, Cloudflare,
painel do Supabase, Resend, Google Search Console do Em Dia, Gemini AI Plus, Flow/Veo,
AI Studio, WhatsApp da loja, Bing Webmaster, Wikidata, Drive da equipa, Hostinger.

### O que vive no perfil **Pessoal**

claude.ai e claude.ai/code, ChatGPT (a conta **Plus** é `nilofulfaro@gmail.com` e vive no
**aplicativo ChatGPT do Windows**, que é o que o Codex usa — a do Chrome é Free), GitHub,
Gemini pessoal, Firebase `boraapp-d2bea`, Google Cloud da app, Gmail
nilofulfarotuga/nilofulfaro, Search Console e Google Ads de jaiagarwala.com.

## Antes de abrir seja o que for

1. `~/.claude/contas/abrir-site.ps1 <site>` — o mapa está em
   `~/.claude/contas/MAPA-CONTAS.json`. Não escolher perfil a olho.
2. **Confirmar no ecrã** a conta e o plano antes de trabalhar. Um `Plus` que afinal é
   `Free` só se descobre no ecrã, e já custou uma missão inteira.
3. **Nunca sair de uma conta iniciada.** Sair é fácil; voltar a entrar precisa do Danilo.

## Login: último recurso, nunca o primeiro

Regra do Danilo (13/09/2026, com adenda da mesma noite): quando falta sessão, **procura
primeiro a que já existe** — o outro perfil do Chrome, o Edge, o aplicativo instalado,
`codex login status`, um MCP, uma CLI, o `ssh`. Só depois de esgotar isso é que se abre a
página de login no perfil certo, se avisa o Danilo por Telegram **numa linha** ("abri o
login do X, entra tu") e se continua quando a sessão existir. Uma vez por site, nunca mais.

Nunca se tentam senhas. Nunca se pede um token a ninguém por chat.

## Armadilhas medidas (não são teoria)

- **O separador nasce em segundo plano.** As apps da Google não desenham nada e a captura
  sai com largura 0. Espera e traz a janela para a frente (`foreground` + `ctrl+9`) antes
  de fotografar.
- **JavaScript bloqueado** em Google Ads, Meta e App Store Connect: usa `find` / `read_page`
  em vez de injetar código.
- **O Enter chega com `keyCode 0`** nas apps da Google — usa o clique no botão.
- **Fechar a janela pelo título mata a extensão.** Texto entra por `insertText` + `click()`.
- **O Chrome do Bora navega como a página errada**: aparece "Aderir ao grupo" em todo o
  lado. Confirma sempre o autor na caixa "Criar publicação" antes de publicar.
- **A extensão liga um perfil de cada vez**: `select_browser` com o `deviceId` alterna.

## Quando NÃO há navegador nenhum

Nem toda a sessão tem o conector do Chrome ligado (aconteceu a 24/09: só Supabase, Córtex,
Gmail e Canva). Nesse caso **não se finge**: regista-se o passo como `bloqueado` no
`e2e_log`, deixa-se tudo o resto pronto para um clique, e diz-se ao Danilo numa linha.
