# Benchmarks — Reservas de mesa (OpenTable · TheFork · Resy)
> Biblioteca do Robot B v4. Toda sugestão de reservas cita um padrão daqui.

## Ciclo de vida
- Confirmação imediata ou resposta do restaurante com prazo curto; pendente >15 min = mau sinal.
- Lembretes automáticos 24h e 2h antes (TheFork); reduzem no-show ~30%.
- Slot de reserva expirada/abandonada é libertado rápido para outros clientes.

## No-show
- Taxa de no-show vigiada por restaurante; >5% = ação (depósito, confirmação extra).
- Política de depósito clara ANTES de reservar (valor, condições de devolução).
- No-show marcado automaticamente após janela de tolerância (não fica pendente).

## Operação do parceiro
- Painel do restaurante mostra reservas do dia em tempo real + chegadas marcadas à porta.
- Capacidade por horário (pacing) para não rebentar a cozinha (OpenTable).

## UX
- Cliente vê estado da reserva sempre atualizado (pedida → confirmada → sentado).
- Cancelamento self-service com política visível por escalão de antecedência.
