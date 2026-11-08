---
id: memoria-claude-ai-regras-checkin-v2-2026-10-30
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-08
zona: verde
confianca: alta
estado: atual
---

# Check-in v2 — regras decididas pelo Danilo a 30/10/2026 (escada grande única + escada pequena mensal, só com compra)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `regras-checkin-v2-2026-10-30`, origem `claude.ai`, atualizada em 2026-11-08T20:15:37.352298+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: regras checkin v2 2026 10 30 · memoria claude.ai · claude_ai_memoria

Decisão do Danilo (30/10 20:23 e 21:38), por voz, regras fechadas pela Claude.ai com o "vai" dele:
1) ESCADA GRANDE, uma vez por conta (nunca repete): 45 dias seguidos de check-in. Dias 1-7 só tokens (como hoje). Depois, prémios das lojas parceiras do mais barato para o mais caro, os mais vendidos de cada loja (tirar da base por vendas): dia 10 produto pequeno (ex. 2 salgados), dia 15 produto médio (ex. açaí), dia 25 produto de restaurante (ex. hambúrguer clássico da Boom sem bebida), dia 45 o prémio grande (2 h de limpeza ou lavagem do carro). O prémio grande só no fim; cada degrau só se abre se o cliente estiver ELEGÍVEL: pelo menos 1 pedido pago na app nos últimos 30 dias (checkin_marco_exige_pedido_pago já existe). Levantar um prémio não reinicia a escada grande (o Danilo quer que avance até ao fim); falhar um dia reinicia a sequência mas guarda o degrau já ganho.
2) ESCADA PEQUENA, mensal, repete sempre depois da grande: 30 dias; dia 15 um prémio de pouco valor (até ~3 €, ex. um café/pastel/sobremesa de um parceiro), dia 30 um prémio um pouco maior mas barato (até ~6-8 €, ex. açaí ou salgados), diferente do que ganhou na grande. Tokens diários continuam. Também só com compra nos últimos 30 dias.
3) Regras não podem ser difíceis de entender: um texto de 3 linhas no ecrã; o painel admin edita prémios, dias, limites e o tecto mensal (checkin_marco_tecto_mensal) sem código. Custo dos prémios pago pela Bora ao parceiro ao preço de custo acordado; registo do custo por mês no painel.
4) Clientes com vales antigos: ficam. Regra nova vale a partir da publicação.
ESTADO: regras gravadas; implementação entra na missão da semana seguinte (adendo à sessão da Bora depois da publicação de 30/10-01/11), publicar nas 3 lojas e provar no emulador.

SUPERADO em 04/11/2026 por digest-2026-11-04-checkin-escada-premios (verificado pela missão M7 a 08/11/2026): vale a escada de 30 dias a que o Danilo disse "vai" a 04/11 09:58 — os tokens diários 5,5,10,10,15,15,40 continuam, prémios do dia 8 ao 30 do mais barato ao mais caro (hambúrguer do mês da Boom ao dia 28, limpeza/lavagem ao dia 30), no máximo um prémio levantado a cada 30 dias e a sequência recomeça (platform_settings checkin_premio_intervalo_dias=30 e checkin_marco_texto de 04/11); a escada grande de 45 dias e a escada pequena mensal deixam de valer.
