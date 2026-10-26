---
id: memoria-claude-ai-paridade-rea-2026-10-26
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-26
zona: verde
confianca: alta
estado: atual
---

# Paridade REA 26/10 — Glovo, Uber Eats, iFood e Bora vistos de fora (resumo)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `paridade-rea-2026-10-26`, origem `claude-code`, atualizada em 2026-10-26T06:40:07.513245+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: paridade rea 2026 10 26 · memoria claude.ai · claude_ai_memoria

Missão paridade-rea-2026-10-26, feita a 26/10/2026 entre as 05:26 e as 07:40, no Claude Code do PC. Pedido do Danilo, por voz, às 05:26, depois do vídeo do Klebson Queiroz sobre o REA: "não quero clonar igual o iFood, quero melhorar". O plano está na página paridade-rea-2026-10-26-plano e espera a revisão da Claude.ai antes de se mexer em código.

COMO SE FEZ
- REA: rea-agents 6.8.0, da fonte oficial (npm, morluto/rea, licença MIT).
  - O README pede Node 24.22.1 ou superior. Instalei um Node portátil em C:\Users\danil\.rea-node, com o SHA256 conferido.
  - Ficou registado para o Claude Code em .claude.json e a skill reverse-engineer-anything foi instalada.
  - O rea doctor diz que o node e o host estão bem. Ghidra, JADX e IDA não estão instalados, e não eram precisos.
- Chrome à parte, com perfil novo e porta 9222. O Playwright clicou e o REA observou de forma passiva: árvore de acessibilidade, com os valores redigidos e sem código.
- Morada: Praça Luís de Camões, na Guarda.
- 66 prints em Desktop\Bora\paridade-rea-2026-10-26, mais a pasta rea\.
- Relatórios no ramo paridade-rea-2026-10-26 do repo, em .claude/.ai/reports/paridade-rea-2026-10-26/: RELATORIO, PLANO, glovo, ubereats, ifood e bora.
- Glovo e Uber Eats vistas até ao login, onde parei. O iFood mostrou a verificação da Cloudflare na primeira página: parei pela regra e fiquei só com notícias públicas.

O QUE SE VIU
- Glovo:
  - Um carrinho por loja, por isso não há aviso ao trocar.
  - Loja fechada: abre uma janela com "lojas abertas parecidas" e "agendar".
  - "Dados do estabelecimento", com a morada e o horário.
  - Faixas Promoções, Mais vendidos e Novidades.
  - Filtros e 4 formas de ordenar. Ao gravar a morada, pergunta o tipo de local e mostra um pino no mapa.
  - Prime a 4,99 € por mês.
  - Ao parceiro: 30% com entrega e 15% na recolha.
- Uber Eats:
  - Botão Entrega/Recolha no topo e 6 chips de filtro.
  - Agendar até 7 dias, em janelas de 30 minutos.
  - "Os mais apreciados", com a percentagem de gostos por artigo.
  - Nota do pedido no carrinho.
  - Uber One a 4,99 € por mês ou 49,99 € por ano.
  - Ao comerciante: 30%, 20% ou 15%, mais 3,49 € por semana.
- Bora:
  - "Sou Cliente" pede login logo. Só a ligação /#/loja/<id> abre sem conta.
  - Sem conta, "Finalizar pedido" não faz nada.
  - A loja fechada aparece como aberta.
  - Não tem ficha da loja, nem destaques, nem filtros na lista.
  - Os cartões da página inicial só têm foto e nome.
  - A morada não aparece no checkout.
  - É melhor na pesquisa (encontra produtos), nas reservas de mesa, nos Favores, no assistente que monta o carrinho a partir de uma foto, nas taxas explicadas linha a linha, na gorjeta e no custo para o parceiro.
- No banco, últimos 30 dias: 36 pedidos e 17 entregues. Recolha 0, agendados 0 e assistente 41 propostas.

O PLANO, 15 itens
- 1 a 11, para o cliente e sem dinheiro: finalizar sem conta leva ao login; explorar sem conta, reparando o convidado; loja fechada clara; ficha da loja; mais vendidos e novidades; cartões completos; filtros e ordenação; morada e nota antes de pagar; editar uma linha do carrinho; botão Entrega/Recolha; "leve também".
- 12 a 14, loja e painel: alergénios no admin; modo ocupado e mudar a hora de pronto (toca no despacho e precisa de revisão); o parceiro responde às avaliações.
- 15, PRECISA DO AUTORIZO DO DANILO: cupão no checkout, assinatura mensal, promoções com preço riscado e a nota legal dos 30 dias, e agendar entregas normais (despacho).

ERROS REPORTADOS, que não corrigi (e2e_log 04-bora-erros)
- O convidado continua partido desde 08/09 (400/422).
- A loja fechada mostra "5-20 min".
- No ecrã de 1440 px, a foto do produto tapa tudo.
- Os preços aparecem como "€9.65" em vez de 9,65 €.
- Os extras do BK dizem "SIN", em espanhol.
- No painel, o interruptor das gorjetas não grava, porque platform_settings não tem política de escrita. O valor real é true.
- home_banners não tem migração no repo.
- create_order, só relato:
  - procura a loja pelo nome;
  - não verifica is_available;
  - nos pedidos em dinheiro não há idempotência no servidor;
  - os mín/máx dos extras só são verificados na app.
- Parceiro:
  - os extras são apagados e reinseridos sem transação;
  - /partner/ratings não tem caminho;
  - o esgotado_ate não é limpo;
  - recusar o pedido não pede confirmação.
- A confirmar: taxa de serviço de 5% (0,48 €) num não-parceiro, no carrinho do visitante.

BLOQUEIOS
- iFood: Cloudflare.
- Apagar o perfil C:\Users\danil\_rea_perfil_paridade: recusado pela bora-tranca. A pasta ficou, sem conta.
- O observe-web-session do REA só regista navegação.
