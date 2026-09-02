# Vigia do WhatsApp da loja (porta: WhatsApp Web deste PC)

Corre **dentro da sessão do WhatsApp Web que já está associada** neste Chrome. Não precisa de
QR novo, não cria dispositivo novo, não mexe no telemóvel. Enquanto o Chrome estiver aberto com
o separador do WhatsApp Web, a vigia verifica sozinha de ~2 em 2,5 min e:

- **Responde sozinho** (sem aprovação): saudações, "o que é o Bora", como ser **parceiro**,
  como funciona uma vertical, e outras perguntas gerais. Interessados em ser **estafeta** →
  resposta de lista de espera + guarda o número + avisa o Danilo.
- **Não responde sozinho** (avisa o Danilo por Telegram e deixa para ele): **pedido específico**,
  **dinheiro/preços/reembolsos/descontos**, **reclamações**, **estafeta/parceiro em falta**.
- **Grupos: nunca.** A vigia só abre conversas cujo título é um **número** (clientes). Grupos
  têm nome → nunca são abertos nem lidos nem respondidos.
- No **primeiro arranque** não responde ao histórico (faz "baseline"): só trata mensagens
  **novas** a partir daí. Nunca responde duas vezes à mesma mensagem.

## Precisa de duas coisas a correr (ambas neste PC)
1. **Servidor-cérebro** (`servidor_cerebro.py`, porta 127.0.0.1:8790) — já fica a arrancar
   sozinho pela tarefa agendada `CerebroWhatsAppBora` (ao ligar o PC e de 2 em 2 min se cair).
2. **A extensão carregada no Chrome** (passo único abaixo).

## Ativar a extensão (passo único — ~20 segundos, só o Danilo pode)
1. No Chrome, abrir `chrome://extensions`.
2. Ligar o **Modo de programador** (canto superior direito).
3. Clicar **Carregar sem compactação** ("Load unpacked").
4. Escolher esta pasta:
   `C:\BoraLocal\Desktop-PC-antigo\ferramentas\whatsapp-loja\vigia-whatsapp-bora`
5. Abrir/recarregar `https://web.whatsapp.com`. Pronto — a vigia arranca em ~8s.

Para confirmar: F12 → Consola → aparece `[VigiaBora] vigia ativa...`.

## Provar que responde sozinho
Manda uma mensagem nova (ex.: "oi") de outro número para a loja. Em ~2 min a **vigia**
responde sozinha (sem o Danilo e sem o Claude tocarem em nada).

## Corrigir uma resposta (o manual cresce)
Se o Danilo quiser corrigir algo, grava a correção no manual (secção 12):
```
curl -X POST http://127.0.0.1:8790/correcao -H "Content-Type: application/json" -d "{\"texto\":\"a correcao aqui\"}"
```

## Quando o bloqueio da VPS passar
Migra-se para a VPS (Baileys, sem navegador, funciona com o PC desligado). O cérebro e o
manual são os mesmos — não se perde nada. A vigia do Chrome pode então desligar-se.

## Registo/auditoria
Tudo o que a vigia decide fica em `atendimento-log.jsonl` (nesta pasta acima).
