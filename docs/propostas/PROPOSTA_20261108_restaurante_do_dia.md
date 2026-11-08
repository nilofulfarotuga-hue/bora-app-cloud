# Proposta — "Restaurante do dia" (08/11/2026)

Missão `m6-crescimento-hermes-2026-11-08`, bloco 3. Ordem do Danilo: "Notificação diária com um restaurante por dia."
Zona verde: não mexe em preços, comissões, carteiras, tokens nem pedidos.

## O que já está no ramo `ai/2026-11-08-m6-crescimento`

- `docs/propostas/PROPOSTA_20261108_restaurante_do_dia.sql`: interruptor, hora (17:30) e público no `platform_settings`;
  registo da rotação; escolha do restaurante e do prato; envio diário pelo relógio (`cron`, de 10 em 10 min, só
  envia uma vez por dia, entre a hora do painel e 2 h depois); as duas funções do painel; prova em rollback no fim.
- `supabase/functions/push-clientes-alvo/index.ts`: aceita `extra` (ex.: `restaurant_id`) no `data` do FCM, sem
  deixar trocar `type` nem `origem`. Provado com Deno (check e corrida do bloco sobre 4 entradas).
- App: `kTipoRestauranteDoDia`, gancho `NotificationService.abrirLoja` no `main.dart` (abre a loja pelo
  `abrirLojaPorId`, o mesmo caminho das listas), tratado no toque com a app fechada, em fundo e aberta.
- Painel (PT-BR): Clientes › "Restaurante do dia" (`admin_restaurante_do_dia_screen.dart`): ligar/desligar, hora,
  só opt-in, próximo da rotação, fila da rotação e últimos 14 dias de envios. Sem o servidor, diz o que falta.

## Regras da escolha

- Cada cliente com notificações ligadas recebe UM aviso por dia.
- Quem abriu produtos de restaurantes abertos nesse dia nos últimos 30 dias (`product_view_daily`) recebe o
  restaurante que mais abriu ("a que o cliente mais abriu"); os outros recebem o da rotação.
- Rotação: o restaurante que há mais tempo não foi "o do dia"; parceiros primeiro no empate.
- Só restaurantes ativos (coming_soon=false, is_active_admin, aprovados), sem "demo", abertos ao jantar nesse dia
  (`business_hours`), com pelo menos um prato com foto. Nunca bebida alcoólica, bebida, molho ou extra no aviso.
- Texto humano, sem emoji: "O restaurante do dia: Boom! Burger — Hoje sugerimos Boom! Clássico. Pedes na app e
  nós vamos buscar e levamos-to a casa."

## Prova feita a 08/11 (só leitura, produção)

Para segunda 09/11: 9 restaurantes abertos ao jantar entram (Boom! Burger, Goola, Keli, Burger King, Fuku, Jyosmi,
KFC, McDonald's, Pôr do Sol); Sabores de Casa, Leonidas e Tiago's ficam de fora (fechados à noite). A rotação começa
pela Boom! Burger com o "Boom! Clássico". 236 clientes, 152 com notificações ligadas, 36 deles com lojas abertas
nos últimos 30 dias (recebem a sua). Pratos corrigidos depois da prova: KFC já não sai com o molho "DIP Caesar"
(sai "Menu Durum Kebab") e o Fuku já não sai com o código "T7".

## Para a Claude.ai aplicar

1. Aplicar o `.sql` (sem o bloco PROVA) e correr a PROVA do fim (DO + RAISE: desfaz tudo, o pg_net não envia).
2. Publicar a Edge `push-clientes-alvo` do ramo (sem ela o aviso chega, mas o toque só abre a app).
3. Publicar a app nas 3 (o toque abre a loja e o painel ganha o ecrã).
4. Copiar o `.sql` para `supabase/migrations/<versão>_restaurante_do_dia.sql`.
