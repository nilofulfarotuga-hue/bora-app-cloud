---
id: memoria-claude-ai-adendo-9-checkin-escada-premios-2026-10-29
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# ADENDO 9 (Danilo 22:20) - check-in diario: calendario de 30 dias e escada de premios "levanta ou continua" (um premio por sequencia)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `adendo-9-checkin-escada-premios-2026-10-29`, origem `claude.ai`, atualizada em 2026-10-29T22:22:19.651964+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: adendo 9 checkin escada premios 2026 10 29 · memoria claude.ai · claude_ai_memoria

Pedido do Danilo 29/10 22:20 (capturas do iPhone, ecra Check-in diario e Os premios do mes). Fazer depois do Bloco E da missao publica-2026-10-29 (ou em sessao nova na mesma pasta se o contexto acabar), publicar nas 3 lojas e provar no emulador. Mexe em: app cliente (cartao Check-in diario na home, ecra Os premios do mes, ecra Os meus premios), funcoes do check-in (daily_checkins, checkin_premios_vales, chaves checkin_marco_* em platform_settings) e painel admin (ecra do check-in). Reportar outros erros em vez de os corrigir calado.

1) CALENDARIO. Hoje o cartao so mostra Dia 1 a Dia 7. Passa a mostrar a faixa de 7 dias da semana corrente da sequencia (ex.: no dia 12 mostra 8-14) com os dias feitos marcados, e uma setinha "ver o mes" que abre em baixo (expande no proprio cartao, sem ecra novo) o calendario dos 30 dias do ciclo: dias feitos marcados, dia de hoje destacado, marcos 7/10/15/30 com icone do premio. Fecha com a mesma seta. Nada de cobrir o ecra todo.

2) ESCADA DE PREMIOS (regra de negocio NOVA, mandou o Danilo: "se ele escolher algum desses premios, volta do zero; nao vai acumular todos senao eu vou falir"). Os tokens diarios (5,5,10,10,15,15,40) continuam a acumular como hoje, nao sao premios. Os premios de produto/servico (dia 10 salgados, dia 15 acai, dia 30 limpeza/lavagem) passam a ser UMA ESCADA: em cada sequencia o cliente so leva UM premio, o mais alto a que chegou.
   - Ao chegar a um marco (10, 15, 30): festa no ecra (confetti/explosao, som curto, vibracao) e um cartao com DUAS escolhas claras: "Levantar agora: 2 salgados da Keli (a tua sequencia volta ao dia 1)" ou "Continuar: no dia 15 trocas por um acai do Goola" (no 15: continuar para o dia 30, limpeza ou lavagem). No 30 nao ha continuar: levanta e o ciclo recomeca no dia 1.
   - Enquanto nao levanta, o premio fica "guardado" (vale pendente unico, substituido pelo marco seguinte quando continua: ao chegar ao 15 o vale dos salgados e TROCADO pelo acai, nunca somado).
   - Levantar = cria o vale (como hoje, validade checkin_marco_validade_dias) E a sequencia volta ao dia 1 no proprio momento (o dia seguinte conta como Dia 1 de novo). Os tokens ja ganhos ficam.
   - Se falhar um dia a meio (ex.: dia 12): a sequencia volta ao dia 1 como hoje, MAS o premio mais alto que ja tinha garantido (os salgados do dia 10) fica guardado para levantar durante checkin_marco_validade_dias; nao perde o que ja ganhou (como os programas de "levanta ou arrisca": o patamar atingido e seguro). Nunca mais de um vale pendente por cliente.
   - Texto no ecra Os premios do mes, em PT-PT simples, a explicar: "Em cada sequencia levas UM premio: o mais alto a que chegares. Se levantares, a sequencia volta ao dia 1. Se continuares, trocas por um premio maior." Mesma explicacao no cartao da festa.
   - Tecto mensal (checkin_marco_tecto_mensal) e exigencia de pedido pago (checkin_marco_exige_pedido_pago) continuam a valer.
   - Clientes que ja tem mais de um vale por usar (ex.: o proprio Danilo tem salgados + acai): nao tirar nada, os vales ja criados ficam; a regra nova vale a partir de agora. Registar quantos clientes estao nessa situacao.
   - Painel admin: ecra do check-in mostra por cliente a sequencia, o marco atingido, o vale pendente e os levantados; permite ligar/desligar a escada (chave nova checkin_escada_ativa, nasce ligada), editar os textos e ver o custo dos premios levantados por mes.

3) COMO OS GRANDES FAZEM (referencia para o desenho, nao copiar nomes): Duolingo (faixa de 7 dias + calendario mensal escondido atras de um toque, festa ao atingir marcos); Shopee/Temu/Mercado Livre (check-in diario com moedas que acumulam e premios por sequencia); Starbucks Rewards (ao trocar as estrelas por um premio, as estrelas gastam-se: nao se acumula premio sobre premio); programas "levanta ou arrisca" (o patamar atingido fica seguro, continuar da acesso ao premio maior). Juntar os tres: calendario do Duolingo + tokens que acumulam + escada de premios onde levantar reinicia.

4) Provas: emulador Android (capturas do cartao fechado/aberto, festa no dia 10, escolha levantar vs continuar, vale trocado no 15, reinicio ao levantar), testes de unidade nas funcoes do servidor (um vale pendente no maximo; levantar reinicia; falhar guarda o patamar), e2e_log fluxo publica-2026-10-29 passo G-checkin-escada, publicacao nas 3 lojas. Terminar com /ctx doctor e /ctx stats.
