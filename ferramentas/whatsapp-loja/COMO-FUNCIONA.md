# WhatsApp da loja — modo rascunho (grátis, local)

## O caminho (tudo grátis, nada sai do PC)
1. Leitura: WhatsApp Web (web.whatsapp.com) neste PC, conduzido pela extensão Claude no Chrome.
   Lê só conversas de quem escreveu primeiro. O número fica no telemóvel do Danilo, como sempre.
2. Áudio: se a mensagem for de voz, guarda-se em `audios/` e transcreve-se LOCAL com
   `transcrever.py` (faster-whisper, português). Nada vai para fora.
3. Rascunho: a resposta é escrita e guardada em `rascunhos/<contacto>-<hora>.md` — NÃO é enviada.
4. Aprovação: o Danilo lê o rascunho e diz "solta" (ou corrige). Só então se envia ESSA mensagem.
5. Registo: cada envio move-se para `enviados/` com data/hora — fica prova do que foi dito.

## Regras de segurança (sempre)
- Só responde a quem escreveu primeiro; nunca inicia conversa em frio.
- Uma resposta de cada vez, com atraso humano; muitas mensagens = avisa o Danilo, não despeja.
- Rascunho obrigatório até ordem de soltar. Mesmo depois, tudo o que toca dinheiro (preço,
  MB Way, link de pagamento, reembolso) volta a rascunho e espera o Danilo.
- "pausa whatsapp" para tudo na hora.

## Ligar (passo do Danilo, uma vez)
Abrir o WhatsApp Web no Chrome e ler o QR com o telemóvel. Só depois disto é que há leitura.
Antes de ligar, ler os 5 riscos em `Bora/relatorios/RELATORIO_FASE4_WHATSAPP_2026-08-31.md`.

## Transcrever um áudio à mão
`python transcrever.py audios/<ficheiro>.ogg`  (português por defeito)

## Cérebro do rascunho (Ollama local)
O rascunho de cada resposta é escrito pelo `whatsapp_rascunho.py` (em ../ollama-pontos),
motor local grátis. Filtra dinheiro (qualquer pergunta de preço/pagamento vai para o Danilo,
nunca responde valores) e não inventa factos (horário/prazo desconhecido -> "vou confirmar").
Áudio -> `transcrever.py` -> `whatsapp_rascunho.py`. Nada sai do PC.

## REGRA PERMANENTE — GRUPOS NUNCA (fixada pelo Danilo, 2026-08-31)
NUNCA responder em grupos: nem rascunho, nem leitura para responder, nem nada. Só conversas
INDIVIDUAIS de cliente. Grupos são ignorados por completo, mesmo que mencionem o Danilo ou
façam pergunta direta. Antes de preparar qualquer rascunho, confirmar que a conversa é 1-para-1
(um contacto, não um grupo). Na dúvida se é grupo, tratar como grupo e ignorar.
