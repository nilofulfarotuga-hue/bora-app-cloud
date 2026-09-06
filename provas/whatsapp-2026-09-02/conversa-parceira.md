# Conversa real com a parceira — lida no WhatsApp Web em 02/09/2026 (Bloco 0, só estudo)
> Número mascarado: **+351 9** *** 120**. No Supabase (`restaurants`, `is_partner=true`) é
> **"Sabores do Brasil - Keli Barbosa"**. Nada foi enviado nesta leitura (envio desligado e provado).
> A senha que o Danilo lhe escreveu à mão está mascarada como «senha da loja».

## O que aconteceu, hora a hora (31/08/2026, segunda-feira)

| hora | quem | o quê |
|---|---|---|
| 22:50 | Keli | "Boa noite danilo" |
| 22:50 | Keli | **áudio de 0:23** — a pergunta dela estava aqui |
| 22:50 | **bot** | "Boa noite, **o senhor**. Como posso ajudar hoje?" |
| 23:05 | Keli | áudio 0:04 |
| 23:07 | Keli | uma imagem + áudio 0:02 |
| 23:07 | Danilo (à mão) | "!" |
| 23:08 | (áudios 0:04, 0:08, 0:09 — troca à mão entre os dois) | |
| 23:09 | Keli | "Desculpa" · "Kk" · "Agora vi" · "Ja tento" |
| 23:10 | Danilo (à mão) | «senha da loja» |
| 23:10 | áudio 0:05 | |
| 23:11 | Keli | "Ja entrei" · "Obrigado" |
| 23:12 | áudio 0:09 | |
| 23:12 | Keli | "Ta bem" |

Contexto anterior (27/08): ela pediu-lhe boleia até à estação ("Preciso ir la em baixo na
estaçao, esta disponivel") e o Danilo respondeu à mão ("Sim", "Agora?", "Ok estou a caminho").
Antes disso (24/08) o Danilo enviou-lhe o link do Instagram da loja — é uma parceira com loja
montada, não um prospect.

## O que o bot fez, e o que devia ter feito

1. **Chamou-lhe "o senhor"** (Falha B). O cérebro tinha como saber quem era: o número está em
   `restaurants.phone` com o nome "Keli Barbosa". Não olhou — não há ficha nem cruzamento.
2. **Nunca ouviu o áudio de 23 segundos** (Falha D). A vigia lê só `innerText`; um áudio não tem
   texto, é saltado com "última msg não é do cliente, salto". A pergunta dela ficou **sem
   resposta nenhuma** até o Danilo entrar à mão, 15 minutos depois, às 23:05.
3. O que se seguiu (ela não conseguia entrar na loja; o Danilo deu-lhe a senha) mostra que era
   um **assunto de conta/acesso de parceira** — que o bot devia (a) reconhecer que fala com uma
   parceira, (b) transcrever o áudio, (c) resolver o que pode (explicar como recuperar o acesso)
   e (d) escalar ao Danilo **acusando recepção**, nunca em silêncio.

## Qual teria sido a resposta certa (sem a enviar)

Com o cérebro novo (ficha + transcrição + ferramentas), o caminho seria:
- transcrever o áudio de 0:23 → perceber o pedido (acesso à loja de parceira);
- `supabase.quem_e(+351 9** *** 120)` → parceira "Sabores do Brasil", nome Keli → tratamento
  pelo nome, uma vez;
- resposta em ~10 s, por exemplo: *"Boa noite, Keli! Ouvi o áudio. Vou já ver o acesso da sua
  loja — dou-lhe resposta em 2 minutos."* **com tarefa criada com prazo de 3 min**; e, como é
  assunto de conta, aviso ao Danilo no Telegram com o resumo;
- ao fim do prazo, ou sai a resposta com o resultado, ou sai *"ainda estou a tratar, o Danilo
  já vem"* — nunca silêncio.

## O "vou verificar" que nunca volta — provado no log do número de teste (31/08)

| # | hora | cliente (número de teste do Danilo) | bot |
|---|---|---|---|
| 56 | 15:42 | "Recarreguei" | "Deixe-me confirmar isso e já lhe digo, o senhor." |
| 59 | 15:50 | "Beleza vou mandar as foto" | "Deixe-me confirmar isso e já lhe digo, o senhor." |
| 83 | 16:28 | "Vou te mandar as foto tá" | "Deixe-me confirmar isso e já lhe digo, o senhor." |
| 86 | 16:51 | **"Você disse que vai confirmar e não confirma nada meu"** | **"Deixe-me confirmar isso e já lhe digo, o senhor."** |

Nenhuma destas "confirmações" existiu: o bot não tem ferramenta nenhuma, e a frase vem literalmente
do prompt (`tom_base()` em `atendimento.py`). Ver `diagnostico.md`.
