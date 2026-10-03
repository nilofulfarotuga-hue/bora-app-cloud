# Benchmarks — Delivery (Glovo · Uber Eats · iFood)
> Biblioteca do Robot B v4. Toda sugestão de delivery cita um padrão daqui.
> Ordem de referência do Danilo: Glovo → Uber Eats → iFood. Curto por desenho.

## Catálogo
- Produto sem preço NUNCA aparece ao cliente (Glovo/Uber: validação antes de publicar).
- 100% dos produtos com foto + categoria; sem foto → placeholder de categoria, nunca vazio.
- Loja sem operação (sem stock, sem horário, problemática) fica escondida, não "avariada".
- Preços vigiados: outliers (>10× mediana da categoria) bloqueados para revisão.

## Dispatch & operação
- Reatribuição automática de estafeta com TTL curto; pedido nunca fica "a chamar" sem dono.
- Pedido preso é cancelado proativamente com aviso ao cliente (não silêncio).
- Cancelamentos monitorizados por motivo; um motivo dominante = alerta de produto/UX.
- Stacking limitado e por proximidade (Glovo: mesma loja ou raio curto).

## Notificações
- Push de mudança de estado em <5s; fallback in-app sempre.
- Token de push inválido é detetado e re-registado no próximo arranque da app.
- Estafeta online sem token de push = invisível para ofertas → corrigir imediatamente.

## UX / paridade
- Tracking com mapa ao vivo + ETA; estados em linguagem humana.
- Repetir último pedido em 2 toques (iFood); favoritos primeiro.
- Recibo detalhado: subtotal, entrega, taxa de serviço, descontos — nada escondido no total.
