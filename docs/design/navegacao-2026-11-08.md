# Navegação da app - como está e como deve ficar (08/11/2026)

Só desenho. Nenhum código foi alterado. A implementação fica para a missão M8 (09/11).

## Resumo para o Danilo

- Cliente: hoje tem barra de baixo com Início, Entrega, Reservas, Perfil. O separador "Entrega" abre um ecrã chamado "Pedidos": o nome da barra e o nome do ecrã não batem. Proposta: Início, Pedidos, Mensagens, Perfil.
- Estafeta: hoje não tem barra. Tem quatro botões redondos soltos no topo do mapa (Perfil, Ganhos, Trabalhar noutra coisa, Mudar modo), só com ícone. Proposta: barra com Mapa, Pedidos, Ganhos, Conta, e a mira de centrar o mapa do lado direito, um pouco abaixo do meio.
- Parceiro: hoje é uma página única comprida, com dois ícones no topo e uma fila de botões. Proposta: Pedidos, Menu, Horários, Dinheiro, Conta.
- Regra de desenho: o que se usa todos os dias fica a 1 toque, e nada fica escondido atrás de um ícone sem texto.
- Maquete visual: `navegacao-2026-11-08-mockup.html` (abrir no navegador).

## Como está HOJE (confirmado no código)

### Cliente
- Quatro separadores, dentro de um `IndexedStack`: Início, Entrega, Reservas, Perfil. Os rótulos estão em `lib/widgets/bora/bora_bottom_nav_v2.dart:54` (Início), `:60` (Entrega), `:66` (Reservas), `:72` (Perfil). O enum dos separadores está em `:12`.
- O anfitrião dos separadores é `lib/screens/client_main_screen.dart:152-179` (corpo em `:155-162`, barra em `:170-177`).
- "Entrega" abre `OrdersScreen`, cujo título é "Pedidos" (`lib/screens/orders_screen.dart:156`).
- As categorias já estão na home: `_buildCategoryGrid` em `lib/screens/client_home_screen.dart:486`. São 9 mosaicos: Restaurantes (`:490`), Supermercados (`:501`), Lojas (`:529`), Favores (`:575`), Beleza (`:607`), Limpeza (`:616`), Casa (`:636`), Festas (`:685`), Sobremesas (`:702`).
- A barra do pedido em curso ("BarraPedidoAtivo") já existe e é global: `lib/widgets/barra_pedido_ativo.dart:376` (Host), ligada em `lib/main.dart:1027`. Quando não há Host, o separador desenha-a por cima da barra (`client_main_screen.dart:171`).
- Não existe separador de mensagens. Os chats existem por pedido (por exemplo `order_tracking_screen.dart:1033` "Falar com o Estafeta") e o assistente tem a rota `/assistente` (`lib/main.dart:1138`). Não encontrei nenhum ponto da home que abra o assistente com um botão visível (a confirmar na M8).

### Estafeta (entrega)
- Sem barra de baixo. Ecrã `DriverHomeScreen` (`lib/screens/driver_home_screen.dart`), `Scaffold` com mapa a ecrã inteiro em `:1342-1352`.
- Quatro botões redondos só com ícone no topo, `_FloatingIconButton` (`:3089`): Perfil `:1421`, Ganhos `:1432`, Trabalhar noutra coisa `:1452`, Mudar modo `:1459`. O texto só aparece como dica ao premir muito tempo (tooltip), que num telemóvel quase ninguém vê.
- Cartão "Ganhos de hoje" no topo (`:1472`) e cartão de estado em baixo (`:1497`).
- Mapa: `GoogleMap` com `myLocationButtonEnabled: true` (`:1352-1358`), ou seja, usa o botão de centrar da Google, que fica no canto de cima à direita e tapa-se com os botões do topo.
- Quando há pedidos há um segundo desenho, com `AppBar` e ícones (`:1017-1220`: Mudar modo, Ganhos, Trabalhar noutra coisa, Terminar sessão). São dois desenhos para manter.
- A entrada para o papel está em `lib/main.dart:1432-1438` (`TvdeDriverHomeScreen` ou `DriverHomeScreen`).
- Nota: o motorista TVDE já tem o seu próprio ecrã (`lib/screens/driver/tvde/tvde_driver_home_screen.dart`). Este documento fala só do estafeta de entregas.

### Parceiro
- Uma página única, `PartnerDashboardScreen` (`lib/screens/partner_dashboard_screen.dart:53`), com `AppBar` e `ListView`/`SafeArea` (`:1063`).
- No topo: botão ONLINE/OFFLINE (`:1040`), "Mudar modo" (`:1047`, só ícone), "A minha conta" (`:1056`, só ícone).
- Os restantes acessos são botões dentro da página: Reservas Pro (`~:1090`), Ver detalhe de ganhos (`~:1138`), Receber pagamentos, Extrato, Dados fiscais, Horários de funcionamento (`~:1202`), Gerir produtos (`:1344`).
- Entrada: `lib/screens/partner_entry_screen.dart:36`. Existe também `restaurant_dashboard_screen.dart` (825 linhas, lista de pedidos), a confirmar se ainda é usado.

## Como fazem os outros (só o que o utilizador vê)

Fonte: conhecimento geral das apps, sem captura de ecrã verificada hoje. Os nomes exatos dos separadores podem variar por país e versão. A confirmar com a app instalada antes de copiar qualquer coisa.

- Glovo: barra de baixo com poucos separadores (início, pesquisa, pedidos/conta). A home tem as categorias (restaurantes, supermercado, farmácia...) em cima e o estado do pedido num cartão por cima da barra.
- Uber Eats: barra de baixo com 4 a 5 separadores (início, pesquisar, carrinhos/pedidos, conta). Pedido ativo em faixa fixa por cima da barra.
- Bolt Food: vive dentro da app Bolt; a troca entre serviços (viagem, comida, compras) é feita no topo da home, não por barra de baixo.
- iFood: barra de baixo (início, busca, pedidos, perfil) e categorias na home.
- Padrão comum: 4 ou 5 separadores com texto por baixo do ícone, pedido ativo sempre visível, categorias na home e "Pedidos" como separador próprio (nunca "Entrega").
- Apps de estafeta (Uber Driver, Glovo Courier, Bolt Driver): em geral um mapa com barra de baixo ou menu com Ganhos, Conta e Ajuda a um toque. Conhecimento geral, não verificado.

## Proposta

### Cliente - 4 separadores

| Separador | O que abre | Mudança face a hoje |
|---|---|---|
| Início | Home com as 9 categorias, pesquisa e "os meus habituais" | igual |
| Pedidos | Pedidos em curso, histórico e um sub-separador "Reservas" | "Entrega" passa a "Pedidos"; Reservas entra aqui |
| Mensagens | Conversas dos pedidos ativos e entrada para o "Amigo" (assistente) | NOVO |
| Perfil | Conta, moradas, cartões, ajuda | igual |

- Versão mínima do separador Mensagens (se faltar tempo): abre direto o assistente `AssistantChatScreen`, com o nome "Amigo". A lista de conversas dos pedidos fica para depois.
- A faixa do pedido ativo mantém-se por cima da barra.
- Reservas deixam de ter separador próprio mas ficam a 1 toque, dentro de Pedidos. Os atalhos que usam `BoraNavTab.reservation` (`client_main_screen.dart:35-39`) passam a abrir Pedidos já no sub-separador certo.

### Estafeta - barra de baixo

| Separador | O que abre |
|---|---|
| Mapa | O ecrã de hoje (mapa, online/offline, cartão de estado) |
| Pedidos | Pedidos disponíveis e em curso (hoje é o segundo desenho com AppBar) |
| Ganhos | `GanhosScreen` |
| Conta | `ProfileScreen`; "Trabalhar noutra coisa" e "Mudar de papel" passam para aqui, com texto |

- Os quatro botões redondos desaparecem. O estado Online/Offline e o saldo de tokens ficam no topo do mapa.
- Mira de centrar: botão redondo próprio, do lado direito, a cerca de 60% da altura do ecrã (um pouco abaixo do meio), como pediu o Danilo a 07/11. Deixa-se de usar o botão da Google (`myLocationButtonEnabled: false`) e a mira chama `animateCamera` para a posição atual. Fica acima do cartão de estado de baixo, que é empurrado para cima da barra.
- Com a barra, o cartão de baixo (`driver_home_screen.dart:1497`) tem de subir a altura da barra (hoje usa `viewPadding.bottom + 16`).

### Parceiro - 5 separadores

| Separador | O que abre | Vem de |
|---|---|---|
| Pedidos | Lista dos pedidos de agora e botão Loja aberta/fechada | corpo atual da página |
| Menu | Produtos, opções, stock | botão "Gerir produtos" (`:1344`) |
| Horários | Horário de funcionamento e pausa da loja | `PartnerHoursScreen` |
| Dinheiro | Ganhos, extrato, receber pagamentos, dados fiscais | botões dos ganhos |
| Conta | Perfil, Reservas Pro (se tiver), mudar de papel | ícones do topo |

- Reservas Pro só aparece como linha dentro de Conta (ou como 6.º separador só para parceiros de serviços). A decidir na M8.

### Critério de aceitação (para o revisor da M8)
1. Tudo o que se usa todos os dias fica a 1 toque da barra.
2. Nenhum botão só com ícone, sem texto visível.
3. No máximo 1 elemento laranja por ecrã.
4. Textos em português de Portugal.
5. A faixa do pedido ativo continua visível por cima da barra do cliente.
6. Ecrã pequeno (360 x 640) sem texto cortado e com a letra grande do sistema.

## Para o programador (M8)

Ficheiros a mudar, por ordem de risco.

| Ficheiro | Mudança | Risco |
|---|---|---|
| `lib/widgets/bora/bora_bottom_nav_v2.dart` | rótulos (`:54-72`), enum `BoraNavTab` (`:12`), ícone de Mensagens | Baixo. Renomear `reservation` mexe em vários ficheiros: manter o nome interno e mudar só o texto |
| `lib/screens/client_main_screen.dart` | 4.º filho do `IndexedStack`, `abrirSeparador` (`:35-39`) | Médio: a navegação por estado (`_RootNavigator`) e a faixa do pedido dependem deste ecrã |
| `lib/screens/orders_screen.dart` | sub-separador Reservas (reaproveitar `ClientReservationsScreen`) | Médio |
| `lib/screens/client/assistant/assistant_chat_screen.dart` (+ novo ecrã de Mensagens) | entrada Amigo | Médio. O assistente fica fora de zona proibida, mas confirmar com a missão do assistente |
| NOVO `lib/widgets/bora/bora_bottom_nav_generica.dart` | barra reutilizável para estafeta e parceiro, mesmo desenho | Baixo |
| `lib/screens/driver_home_screen.dart` | barra, mira, tirar `_FloatingIconButton` | ALTO. Ficheiro de 4 mil linhas, dois desenhos (com e sem pedidos) e outra sessão a editá-lo hoje. Fazer só na M8, depois dessa sessão fechar |
| `lib/screens/partner_dashboard_screen.dart` | dividir a página em separadores | Médio-alto: 3300 linhas, muitos estados. Fazer por extração, sem reescrever |
| `lib/screens/partner_entry_screen.dart` | monta o novo anfitrião do parceiro | Baixo |
| `lib/main.dart:1432-1438` | só se o anfitrião do estafeta mudar de nome | Baixo |
| `test/` | testes que procuram o texto 'Entrega' no separador (rever `recolha_nome_da_loja_test.dart:39,53`, que parece falar de outra coisa) | Baixo |

Cuidados:
- Frases novas com `.tr` precisam de entrada em `lib/l10n/strings_en.dart` (o CI falha sem ela).
- Não tocar em dispatch, preços nem dinheiro: esta missão é só de interface.
- O `BarraPedidoAtivoHost` (`main.dart:1027`) já reserva espaço em baixo; testar que não duplica com a nova barra.
- Prova: capturas das 3 apps em 360 x 640 e 412 x 915, e `flutter analyze` + `flutter test` (só na M8, com o portão de RAM).
