# Bora contra Glovo, Uber Eats, Bolt Food e iFood (novembro 2026)

Só desenho. Nenhum código alterado.

Fonte do lado dos concorrentes: conhecimento geral do que o utilizador vê nas apps, mais as páginas do livro `plano-melhor-que-uber-glovo-2026-10-29` e `paridade-rea-2026-10-26-plano` (pesquisa web feita a 29/10). Não houve captura de ecrã das apps hoje: tudo o que diz "eles fazem" deve ser confirmado com a app instalada antes de se copiar. Do lado do Bora, cada linha tem prova no código.

## Tabela (15 temas)

| # | Tema | Onde somos melhores / onde estamos atrás | O que fazemos |
|---|---|---|---|
| 1 | Barra de baixo do cliente | Atrás: o separador "Entrega" abre um ecrã chamado "Pedidos" (`bora_bottom_nav_v2.dart:60`, `orders_screen.dart:156`). Eles dizem "Pedidos" | Melhoria 2 abaixo; reorganização na M8 (`navegacao-2026-11-08.md`) |
| 2 | Estafeta: navegação | Atrás: sem barra, quatro botões só com ícone (`driver_home_screen.dart:1421-1465`) | Barra Mapa, Pedidos, Ganhos, Conta na M8 |
| 3 | Parceiro: navegação | Atrás: página única comprida, ícones sem texto (`partner_dashboard_screen.dart:1047,1056`) | Cinco separadores com texto na M8 |
| 4 | Pedido em curso sempre visível | Igual: temos a faixa fixa em todos os ecrãs (`barra_pedido_ativo.dart:376`, `main.dart:1027`), como a Uber Eats | Manter |
| 5 | Estafeta no mapa a deslizar | Igual ou melhor: marcador interpolado que nunca anda para trás (`marcador_animado.dart`, `order_tracking_screen.dart:71`) | Manter; pílula do ETA em cima do mapa |
| 6 | Hora de chegada | Atrás: mostramos "Chega em ~X min" (`order_eta_service.dart:239`); eles mostram também a hora ("às 19:42") | Melhoria 3 |
| 7 | Mensagens de estado do estafeta | Atrás: frases fixas, sem nome nem tempo (`order_tracking_screen.dart:1661-1684`); o nosso TVDE já tem melhor (`tvde_ride_tracking_screen.dart:2054-2080`) | Paridade (b) no documento do motorista |
| 8 | Tratamento por "tu" | Atrás: mistura "tua casa" e "sua morada" no mesmo ecrã (`order_tracking_screen.dart:1664,1683`) | Melhoria 1 |
| 9 | Avaliar a entrega | Igual: abre sozinha, com saltar, e volta no máximo 2 vezes (`order_tracking_screen.dart:278`, `client_home_screen.dart:153`). Atrás no tom: "Saltar" soa a obrigação | Melhoria 4; estrelas no cartão na M8 |
| 10 | Categorias na home | Melhor: 9 categorias (restaurantes, mercados, lojas, favores, beleza, limpeza, casa, festas, sobremesas) numa só app (`client_home_screen.dart:486`). Eles têm menos serviços | Manter. Mostrar "novo" nas últimas categorias |
| 11 | Entrar sem conta e ver preços | Igual: já feito na missão final-app (livro 29/10) | Manter |
| 12 | Pagar | Melhor: MB Way com espera e consulta a cada 3 s (`payment_method_screen.dart:1616`), muito usado em Portugal; dinheiro até 40 EUR | Manter |
| 13 | Pesquisa universal | Melhor: uma lupa leva a lojas, motorista, limpeza e serviços (`151add10`, 05/10) | Manter |
| 14 | Estado ONLINE/OFFLINE do parceiro | Atrás: "ONLINE/OFFLINE" é linguagem de estafeta. Um dono de restaurante entende "Loja aberta/fechada" (`partner_dashboard_screen.dart:1040`) | Melhoria 5 |
| 15 | Assinatura de entregas grátis (Glovo Prime, Uber One) | Atrás: não temos. Envolve preços e dinheiro | Só o Danilo decide. Fica na lista de decisões do livro de 29/10; não se mexe sem "autorizo" |

Pontos em que ficamos claramente à frente: serviços locais numa só app, MB Way, pesquisa única, e o motorista TVDE com compensação e fila inteligente (ainda desligada).

## 5 melhorias pequenas, aplicáveis já

Nenhuma toca nos ficheiros proibidos (order_store, errand_*, favor_*, recibo*, driver_home_screen, minha_conta, client_assistant). Todas são só texto. Lembrete: cada frase com `.tr` tem de ter a entrada em `lib/l10n/strings_en.dart`, ou o CI falha.

### 1. Falar sempre por "tu" no seguimento do pedido
- Ficheiro: `lib/screens/order_tracking_screen.dart:1683`
- Hoje: `'Estafeta a caminho da sua morada'.tr`
- Novo: `'Estafeta a caminho da tua morada'.tr`
- Também: `lib/l10n/strings_en.dart:2677` (mudar a chave para a frase nova, mantendo a tradução). A frase de `:1664` já diz "tua casa".

### 2. O separador chama-se como o ecrã
- Ficheiro: `lib/widgets/bora/bora_bottom_nav_v2.dart:60`
- Hoje: `label: 'Entrega',`
- Novo: `label: 'Pedidos',`
- Cuidado: confirmar que nenhum teste procura o texto 'Entrega' neste widget (`test/recolha_nome_da_loja_test.dart:39,53` parece falar de outra coisa).

### 3. Mostrar a hora de chegada junto aos minutos
- Ficheiro: `lib/services/order_eta_service.dart:239`
- Hoje: `return 'Chega em ~$m min';`
- Novo:
  ```
  final chega = DateTime.now().add(Duration(minutes: m));
  final hh = chega.hour.toString().padLeft(2, '0');
  final mm = chega.minute.toString().padLeft(2, '0');
  return 'Chega às $hh:$mm (~$m min)';
  ```
- Texto que o cliente lê: "Chega às 19:42 (~15 min)". Os minutos já estão arredondados a 5, por isso a hora não promete mais do que o número atual.
- Cuidado: o `_EtaBadge` pode ter largura fixa; ver `order_tracking_screen.dart:~836`. Verificar testes do `OrderEtaService`.

### 4. "Agora não" em vez de "Saltar" na avaliação
- Ficheiro: `lib/screens/rating_screen.dart:311`
- Hoje: `child: Text('Saltar'.tr),`
- Novo: `child: Text('Agora não'.tr),`
- A tradução inglesa de 'Agora não' já existe (`strings_en.dart:1859`) e é o texto do TVDE (`tvde_rate_screen.dart:250`).

### 5. O parceiro abre e fecha a loja, não fica "online"
- Ficheiro: `lib/screens/partner_dashboard_screen.dart:1040`
- Hoje: `label: Text(currentRestaurant.isOnline ? 'ONLINE' : 'OFFLINE'),`
- Novo: `label: Text(currentRestaurant.isOnline ? 'Loja aberta' : 'Loja fechada'),` (com `.tr` e entrada em inglês).
- A confirmar: que o `isOnline` do parceiro é mesmo "a receber pedidos" e não uma pausa temporária; se for pausa, usar "A receber pedidos" / "Em pausa".

## Para a M8
Estas 5 mudanças são pequenas e independentes e podem ir antes da reorganização da navegação. A 2 e a 1 são as mais seguras. A 3 mexe num serviço usado por outros ecrãs: correr os testes do ETA.
