# CONTINUAR — noite-fecho-2026-09-24

> Marco de arranque escrito a 2026-09-25 (madrugada), sessão Claude Code no PC do Danilo,
> ramo `autonomous-night-2026-04-29`. Este ficheiro é actualizado à medida que os blocos
> fecham; o que ficar por fazer fica aqui escrito com o motivo real.

## Estado dos blocos

| Bloco | Estado |
|---|---|
| B0 arranque | feito |
| B1 bora-site `_headers` + `/verificar/<token>` | a começar |
| B2 Resend | a fazer |
| B3 espelhar Edge Functions | a fazer |
| B4 decisor Gemini + Hermes em sombra | a fazer |
| B5 radar dos vídeos | a fazer |
| B6 painel admin | a fazer |
| B7 fecho | a fazer |

## O que já se sabe antes de começar (não reinvestigar)

- `_headers` **já é copiado** pelo `deploy-cloudflare.sh` desde o commit `ee1056b`, aplicado
  e publicado hoje (24/09). Provado no ar: `GET /provas/` devolve
  `Cache-Control: no-cache, must-revalidate`. Falta a parte do `/verificar/<token>`.
- A chave da Resend **envia**. O 401 de 23/09 veio de um endpoint de **gestão**
  (`GET /domains`), não de envio: a chave está restrita a envio, que é o que se quer.
  Provado hoje com envio real para boraappbora@gmail.com (id `01a0d3e8-…`, chegou às 14:54).
  Falta ver se alguma chamada específica falha (ficha legal / recibo de viagem).
- **Não há navegador nesta sessão.** O conector do Chrome não está ligado, por isso tudo o
  que precise de sessão Google/Meta/painel fica bloqueado e escrito aqui.

## Para a Claude.ai (Chrome, perfil Bora)

_(preenchido à medida que aparecer)_
