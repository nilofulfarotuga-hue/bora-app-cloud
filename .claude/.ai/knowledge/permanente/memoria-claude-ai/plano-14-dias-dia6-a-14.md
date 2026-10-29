---
id: memoria-claude-ai-plano-14-dias-dia6-a-14
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Plano de 14 dias — do dia 6 ao dia 14 (29/10 a 06/11/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `plano-14-dias-dia6-a-14`, origem `claude-code`, atualizada em 2026-10-29T15:05:29.373061+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: plano 14 dias dia6 a 14 · memoria claude.ai · claude_ai_memoria

# Plano de 14 dias — do dia 6 ao dia 14 (29/10 a 06/11/2026)

Missão `final-app-2026-10-29`, Bloco 5.a. Feito a 29/10/2026 pelo Claude Code.
O plano começou no sábado 24/10 (dia 1) e acaba na sexta 06/11 (dia 14). Hoje é o dia 6.
Fontes lidas: `digest-2026-10-26-plano-14-dias-dia3`, `digest-2026-10-27-plano-14-dias-dia4`,
`digest-2026-10-26-guarda-primeiro` e o `crontab -l` da VPS (29/10 14:13).
Horas de Lisboa. Desde 25/10 Lisboa e UTC são a mesma hora, por isso as horas do cron são as horas reais.

AUTOMÁTICO = já corre sozinho na VPS (cron do root), sem o Danilo fazer nada.
PRECISA DO DANILO = só ele pode (rua, decidir, aprovar, pagar, dar o "autorizo").

## Resumo dia a dia

| Dia | Data | Automático | Precisa do Danilo |
|---|---|---|---|
| 6 | qui 29/10 | 9 | 2 |
| 7 | sex 30/10 | 9 | 1 |
| 8 | sáb 31/10 | 8 | 2 |
| 9 | dom 01/11 | 6 | 3 |
| 10 | seg 02/11 | 8 | 4 |
| 11 | ter 03/11 | 8 | 2 |
| 12 | qua 04/11 | 8 | 1 |
| 13 | qui 05/11 | 8 | 1 |
| 14 | sex 06/11 | 8 | 1 |

Total: 72 itens automáticos, 17 que precisam do Danilo.

## O que corre sozinho (crontab da VPS)

Todos os dias: story das 10:00 (`social-story.sh` com `SOCIAL_SLOT=manha`), story das 19:30,
resumo dos grupos às 18:30, resumo do dia às 21:30 e, novo, o lembrete diário das 09:30.
Só nos dias certos: cobrador 09:30 de segunda a sexta; loja do dia 12:00 de terça a sábado
(o script publica a próxima linha "por publicar" da rotação e só com lojas abertas);
reel 18:00 segunda, quarta e sexta; carrossel 18:00 terça, quinta e sábado;
grelha da semana domingo 11:00; relatório curto de segunda 09:00.
Anúncio da Meta (25 € no total, 5 € por dia, botão para `boraguarda.com/entregas`, link do download no texto da publicação):
corre na Meta de 26/10 a 31/10 (campanha publicada a 26/10 20:18, registo e2e_log 4849).
Corrigido a 29/10: o ficheiro `campanha-pago-fastfood.json` da VPS ainda dizia `a_espera_de_fundos` e `campanha_id` vazio,
por isso o resumo das 21:30 contava que a campanha "não arrancou". Passou a `ativa`, id 52679193515474, 26/10 a 31/10
(cópia do antigo: `.bak-20261029`). Limite: gasto e cliques só se leem com `META_ADS_TOKEN`, que não existe (ver abaixo).

## Dia a dia

**Dia 6, quinta 29/10.** Plano: angariadores na rua; cada loja que fecha fica montada com cartaz, código e treino.
- Automático (9): lembrete 09:30, cobrador 09:30, story 10:00, loja do dia 12:00, carrossel 18:00,
  resumo dos grupos 18:30, story 19:30, resumo do dia 21:30, anúncio da Meta.
- Precisa do Danilo (2): angariadores na rua; aprovar os cartazes da Boom (a Claude.ai desenha-os).
  O "autorizo" aos 4 itens de dinheiro já foi dado hoje às 14:22, por isso saiu da lista (o lembrete das 14:31 ainda o levava).

**Dia 7, sexta 30/10.** Plano: contador "A Guarda tem tudo" nas redes.
- Automático (9): lembrete, cobrador, o contador no story das 10:00 (NOVO, ver abaixo; substitui a pergunta desse dia),
  loja do dia, reel 18:00, resumo dos grupos, story 19:30, resumo do dia, anúncio da Meta.
- Precisa do Danilo (1): angariadores na rua.

**Dia 8, sábado 31/10.** Plano: angariadores; cada parceiro novo vira post e prémio no check-in.
- Automático (8): lembrete, story 10:00, loja do dia, carrossel, resumo dos grupos, story 19:30, resumo do dia,
  último dia do anúncio da Meta. O post do parceiro novo sai pela loja do dia, mas só depois de a loja estar aberta.
- Precisa do Danilo (2): angariadores na rua; se fechou parceiro novo, dar o ok do prémio no check-in.

**Dia 9, domingo 01/11.**
- Automático (6): lembrete, story 10:00, grelha da semana 11:00, resumo dos grupos, story 19:30, resumo do dia.
- Precisa do Danilo (3): angariadores na rua; prémio do check-in se houver parceiro novo;
  pagar o anúncio novo da Meta (o de 25 € acabou a 31/10).

**Dia 10, segunda 02/11.** Último dia de angariadores na rua.
- Automático (8): lembrete, cobrador, relatório de segunda 09:00, story 10:00, reel 18:00, resumo dos grupos,
  story 19:30, resumo do dia.
- Precisa do Danilo (4): angariadores na rua; prémio do check-in se houver parceiro novo;
  ir à Boom (segunda ou terça) testar o robô com o dono; mudar o login da loja Boom para o email do dono dela
  (a conta de login só muda quando ele entra, por isso fica para segunda).

**Dia 11, terça 03/11.**
- Automático (8): lembrete, cobrador, story 10:00, loja do dia, carrossel, resumo dos grupos, story 19:30, resumo do dia.
- Precisa do Danilo (2): ir à Boom se ainda não foi na segunda; prémio do check-in se houver parceiro novo.

**Dia 12, quarta 04/11.**
- Automático (8): lembrete, cobrador, story 10:00, loja do dia, reel 18:00, resumo dos grupos, story 19:30, resumo do dia.
- Precisa do Danilo (1): prémio do check-in se houver parceiro novo.

**Dia 13, quinta 05/11.**
- Automático (8): lembrete, cobrador, story 10:00, loja do dia, carrossel, resumo dos grupos, story 19:30, resumo do dia.
- Precisa do Danilo (1): prémio do check-in se houver parceiro novo.

**Dia 14, sexta 06/11.** Plano: balanço de categorias com parceiro.
- Automático (8): lembrete, cobrador, story 10:00, loja do dia, reel 18:00, resumo dos grupos, story 19:30, resumo do dia.
- Precisa do Danilo (1): balanço de categorias com parceiro e decidir onde falta parceiro.
  Os números saem sozinhos: `contador_guarda.py --numeros` na VPS (hoje 22 lojas abertas em 5 categorias).

## O que passou a automático hoje (29/10)

1. Contador "A Guarda tem tudo" do dia 7 (30/10). O story das 10:00 desse dia usa uma frase calculada na hora
   com a base: lojas aprovadas, abertas, ativas e fora da lista de exclusão, e o número de categorias.
   Hoje daria "A Guarda tem tudo: 22 lojas em 5 categorias. O que pedes hoje?" (22 e 5 conferem com um SELECT à base).
   Prova (ensaio a seco do `social-story.sh`, nada publicado): com a data 30/10 escolhe a frase do contador; com 31/10
   volta à pergunta normal. Passa pelos mesmos portões do story normal (regra das lojas permitidas, portão do parceiro).
   Se a base não responder, sai a pergunta normal e nunca um número inventado.
   O fiscal de arte deu 78/100 a uma peça só de texto como esta (feitura 42/60); o story diário normal
   não passa pelo fiscal, por isso não trava a publicação.
2. Os 3 números do anúncio da Meta no resumo das 21:30: sem token; precisa do Danilo/Claude.ai. Não existe
   `META_ADS_TOKEN` no `.env` da VPS (só `META_PAGE_TOKEN`, que não lê anúncios). Falta um token com permissão de ler
   anúncios (Business Manager no Chrome). Enquanto isso o resumo diz isso mesmo, e dá as visitas ao link e os
   primeiros pedidos da base (hoje: "dia 4 de 6", 4 visitas pelo link, 0 primeiros pedidos, 16 contas novas).
3. Lembretes diários ao Danilo pelo WhatsApp da Bora, às 09:30 de Lisboa, com os itens do dia que só ele pode fazer.
   Rotina `lembretes_danilo.py` (cron root, urgentes de 10 em 10 minutos); itens na tabela `lembretes_danilo`
   e no ecrã "Lembretes" do painel admin. Se a máquina falhar às 09:30, os itens dos 7 dias anteriores que ficaram
   por enviar saem no dia seguinte, com "(do dia dd/mm)". Primeiro envio provado a 29/10 14:31 (entregue).

