---
name: falar-com-o-danilo
description: Usa SEMPRE que fores mandar alguma coisa ao Danilo pelo Telegram (BoraHermesbot) — fim de missão, pedido de clique/autorizo, alerta, relatório — a partir de uma sessão do Claude Code, do Dipsy, de um script ou de uma rotina da VPS. Desde 31/10/2026 há UMA só porta para o chat dele: o PORTEIRO na VPS, que faz a triagem (URGENTE / RESULTADO / INFO), tira os repetidos e manda sempre texto + voz. Proibido chamar a API do bot diretamente (curl api.telegram.org, hermes send, sendMediaGroup por curl).
---

# Falar com o Danilo (o porteiro do Telegram)

Ordem do Danilo, 31/10/2026 10:07: chegavam-lhe mensagens sem voz, repetidas e ruído que não era para ele.
Ele quer SÓ duas coisas no chat, sempre escritas em português simples E em voz:

- **URGENTE** — precisa dele agora: um clique, dinheiro, uma decisão, um cliente em apuros, alertas da base
  (pedido novo, cadastro, marcação, TVDE). Começa por "Precisas de ti:" e diz o passo numa linha.
- **RESULTADO** — uma missão/rotina acabou: "feito isto, falta isto", **3 linhas no máximo** (o resto vai sozinho
  para os bastidores).
- **INFO** — estados, ids, "Facebook: ok", ok/erro de rotinas, propostas, radar: **NÃO vai ao chat dele**. Fica no
  `e2e_log` (fluxo `porteiro-telegram`), no grupo "Bora Bastidores" (quando existir) e entra no resumo das 06:45 e
  das 21:00 (5 linhas com voz).

## Como se manda

Sessão do PC (Claude Code, Dipsy, scripts do Windows) — pelo ssh, o porteiro só ouve na VPS:

```bash
bash orquestracao/telegram-danilo.sh RESULTADO --origem claude-code:<missao> "Feito: X. Falta: Y (porquê)."
bash orquestracao/telegram-danilo.sh URGENTE   --origem claude-code:<missao> "Abre a sessão X e carrega em Permitir."
bash orquestracao/telegram-danilo.sh INFO      --origem claude-code:<missao> "estado técnico"   # não vai ao chat
bash orquestracao/telegram-danilo.sh RESULTADO --ensaio "texto"   # decide e regista, NÃO envia (provas)
```

PowerShell: `"texto" | ssh -i $HOME\.ssh\id_ed25519_vps root@srv1786862.hstgr.cloud "python3 /opt/data/voz/porteiro_cli.py danilo RESULTADO --origem claude-code -"`
(o texto vai pelo stdin em UTF-8; os acentos chegam inteiros).

Na VPS ou dentro do contentor do Hermes:

```bash
python3 /opt/data/voz/porteiro_cli.py danilo URGENTE|RESULTADO|INFO --origem <nome> "texto"   # ou -f ficheiro, ou -
python3 /opt/data/voz/porteiro_cli.py send -t telegram -f msg.txt --json    # em vez de `hermes send -t telegram`
# imagens/álbum: --foto caminho (várias vezes) ou linhas MEDIA:<caminho> no texto do send — a legenda leva voz
```

Python na VPS: `from porteiro import telegram_danilo; telegram_danilo(texto, "RESULTADO", "minha-rotina")`
(`voz.falar(...)` e `comum.dizer(...)` já passam pelo porteiro sozinhos).
Scripts antigos que usavam `https://api.telegram.org/bot...` passaram a `http://172.16.1.1:8796/o/<origem>/bot...`
(espelho da API: só o chat do Danilo é triado; outros chats e outros bots seguem iguais).
Base de dados: a Edge `notify-admin-urgent` escreve em `public.porteiro_entrada` (só service_role).

## Regras

1. Nunca `curl https://api.telegram.org/...` para o chat do Danilo, nunca `hermes send -t telegram` cru, nunca
   `audio-add.sh` (desligado: a voz é do porteiro). Se o porteiro falhar, NÃO há caminho de recurso para a API:
   regista no e2e_log e avisa a sessão-mãe.
2. Escolhe o nível com honestidade: na dúvida entre RESULTADO e INFO, é INFO. URGENTE só se ele tiver de fazer
   alguma coisa agora.
3. Escreve para ser ouvido: frases curtas, sem jargão, sem ids, sem links crus no meio da frase, sem tabelas.
4. Não repitas o que outro robô já disse: o porteiro descarta o mesmo texto (sem horas/ids) durante 30 min.
5. Prova = a resposta JSON (`ids_texto` = message_id do Telegram; `destino` = chat | bastidores | registo |
   descartado) e, no servidor, `tail /opt/data/voz/porteiro/porteiro.log.jsonl` e `voz.log.jsonl` (voz enviada).

## Onde vive

VPS: `/opt/data/voz/porteiro.py` (serviço `porteiro`, portas 127.0.0.1/172.16.1.1:8796), `porteiro_cli.py`,
`porteiro.env` (segredo e `PORTEIRO_BASTIDORES_CHAT`), registos em `/opt/data/voz/porteiro/`.
Cópia no repo: `ferramentas/vps/porteiro-telegram/`. O Dipsy tem bot próprio (@dipsy_bora_bot): esta regra é só
para o chat do Danilo no BoraHermesbot.
