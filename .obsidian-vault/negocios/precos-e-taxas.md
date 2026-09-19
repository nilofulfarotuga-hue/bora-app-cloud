# Bora App — Preços e Taxas

## Taxa de Entrega (cliente paga)
- Até 4 km: **€2,50**
- Acima de 4 km: **€2,50 + €0,50/km adicional**
- Apartamento: **+€1,50** (€1,00 estafeta / €0,50 Bora)

## Comissões

| Tipo | Regra |
|---|---|
| Parceiro | 20% total = **10%** visível ao parceiro + **5%** markup oculto no preço + **5%** taxa de serviço ao cliente |
| Não-Parceiro | **15%** markup invisível (lucro Bora) + taxa de serviço **€2,50** |

### Detalhes comissão parceiro (decisão 2026-04-25)
- `platform_commission` = 10% × subtotal → parceiro paga no settlement
- `partner_markup_hidden` = 5% × subtotal → embutido no preço do produto (cliente não vê)
- `service_fee` = 5% × subtotal → linha visível no recibo do cliente
- Colunas DB: `partner_commission_visible`, `partner_markup_hidden`, `partner_service_fee_client`

## Pagamento ao Estafeta

| Serviço | Valor |
|---|---|
| Base por entrega | €3,80 |
| Por km | €0,20/km |
| Bónus shopping (storeShopping, carryGroceries, sendPackage) | **€0,80** |
| Bónus 2º pedido stacked parceiro | **+€3,00** |
| Base logística (carry/send) | €4,00 |
| Logística por km | €0,50/km |
| Partilha lucro Bora (não-parceiro) | **+30%** do lucro líquido Bora |
| Payout semanal (2ª, 3h) | mínimo €10 para processar |

### Nota: bónus €0,80
- ✅ storeShopping (não-parceiro e parceiro)
- ✅ carryGroceries
- ✅ sendPackage
- ❌ restaurant (estafeta não vai às compras)

## Sacos de Transporte
- Restaurante parceiro: 1 saco fixo **€0,30**
- Mercado (storeShopping): **€0,10/saco** (mín 0, máx 20)

## Limites
- Dinheiro: máximo **€40,00** por pedido
- Stripe buffer non-partner: **+15%** pré-autorizado (libertado após compra real)
- Desconto máximo tokens: **50%** do total

## Batching (Capacidade do Driver)

| Tipo de Serviço | Regra |
|---|---|
| carryGroceries / sendPackage | Sem batching — driver deve estar livre |
| Pedidos parceiro | Máx. 2; 2º deve ser mesmo vendor OU ≤ 800m |
| Pedidos não-parceiro | Máx. 3; todos do mesmo vendor |
