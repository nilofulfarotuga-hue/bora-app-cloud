# Relatório — Vigia do WhatsApp da loja pela porta WhatsApp Web (deste PC)
Data: 2026-08-31 · Porta interina enquanto o Baileys da VPS está bloqueado.

## O que ficou FEITO e PROVADO
- **Respondeu sozinho a 2 mensagens reais do Danilo** (nº +351 931 992 662), o cérebro a decidir:
  - "oi" → "Olá, tudo bem? Aqui é o Bora, o senhor precisa de alguma coisa?" (12:14, enviada).
  - "Gostaria de ser um parceiro… restaurante" → contacto correto +351 937 501 673 /
    boraappbora@gmail.com / formulário na app (12:27, enviada).
- **Cérebro local** (`servidor_cerebro.py`, `127.0.0.1:8790`): `/saude` a devolver 200; encaminhamento
  verificado — saudação/parceiro/estafeta = responde sozinho; ack = ignora; pedido/dinheiro =
  rascunho + Telegram ao Danilo; grupo = ignora. UTF-8 correto. Aquecedor mantém o qwen quente
  (resposta geral ~11 s em vez de 40-60 s a frio).
- **Permanência**: tarefa agendada `CerebroWhatsAppBora` (State=Running), reinicia de 2/2 min,
  sem parar na bateria, sem limite de tempo.
- **Alertas Telegram** do PC via VPS/hermes: entregues ("Sent to telegram home channel").
- **Extensão** `vigia-whatsapp-bora\` (manifest+content+background): seletores validados no DOM ao
  vivo — linhas `[role="row"]`, portão anti-grupo por título-número (grupos "Marketing…"/"WhatsApp"
  corretamente ignorados; única candidata era o nº individual), botão `button[aria-label="Enviar"]`,
  inserção por `execCommand`/paste, fetch ao cérebro pelo background (contorna o CSP da página).

## FALTA (só o Danilo — é como ler um QR)
Carregar a extensão UMA vez: `chrome://extensions` → Modo de programador → **Carregar sem
compactação** → pasta `...\whatsapp-loja\vigia-whatsapp-bora`. A partir daí responde sozinho de
~2,5 em 2,5 min, com o Chrome aberto no WhatsApp Web. Guia: `vigia-whatsapp-bora\COMO-ATIVAR.md`.

## Regras respeitadas
Grupos nunca (só conversas de número). Dinheiro/pedidos/reclamações nunca sozinho — vão para o
Danilo por Telegram. Identificação por número + última mensagem literal (não repetir o erro do
Junior). Correções do Danilo entram no manual (secção 12).

## A seguir
Migrar para a VPS (Baileys, sem navegador, funciona com o PC desligado) quando o bloqueio passar —
mesmo cérebro e manual, sem perder nada. Notificador de QR da VPS já avisa no Telegram.
