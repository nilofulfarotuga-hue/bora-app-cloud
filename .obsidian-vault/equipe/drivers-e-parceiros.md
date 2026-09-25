# Drivers e Parceiros — Regras Operacionais

## Aprovação de Drivers

- Driver regista-se → status: `pending`
- Admin aprova → status: `approved`
- Admin rejeita → status: `rejected`
- Apenas drivers `approved` recebem ofertas de pedidos
- Dashboard admin tem ecrã `driver_approval`

## Tipos de Veículo

| Veículo | Serviços que suporta |
|---|---|
| Mota | restaurant, storeShopping, carryGroceries (sem carro) |
| Carro | Todos os serviços, incluindo sendPackage com `requiresCar=true` |

## Capacidade (Batching)

| Tipo de pedido | Regra de batching |
|---|---|
| carryGroceries / sendPackage | Sem batching — driver deve estar livre |
| Parceiro | Máx. 2 simultâneos; 2º mesmo vendor ou ≤ 800m do pickup |
| Não-Parceiro | Máx. 3 simultâneos; todos do mesmo vendor |

## Oferta de Pedido

- Driver tem **10 segundos** para aceitar uma oferta
- Se não aceitar → pedido passa ao próximo driver disponível
- Timeout total dispatch: 42s + retry automático
- Oferta persistida em Supabase (`current_driver_offer_id` + `driver_offer_expires_at`)

## Ganhos do Driver

| Item | Valor |
|---|---|
| Base por entrega | €3,80 |
| Por km adicional | €0,20 |
| Bónus shopping | €0,80 (storeShopping) |
| Surcharge apartamento | €1,00 (dos €1,50 totais) |
| Logística base | €4,00 |
| Logística por km | €0,50 |

## Payout

- Automático toda segunda-feira às 3h
- Mínimo €10 para processar (abaixo acumula)
- Cash orders: `driver_balances` atualizado imediatamente via trigger

---

## Parceiros

- Parceiro tem acordo comercial com a Bora
- Comissão: 20% do subtotal cobrada ao parceiro
- Partner order flow: `restaurantAcceptOrder → restaurantMarkReady → callingDriver`
- Non-partner flow: `preparing → callingDriver` (com delay simulado)
- Painel parceiro: gestão de produtos (via `PartnerProductStore`)
- **Pendente:** edição de disponibilidade de menu por horário, gestão de reservas
