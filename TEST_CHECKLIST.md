# BORA APP — Checklist de Teste Fim-a-Fim

## Pré-requisitos

- [ ] Conta Stripe em **test mode** com API keys configuradas no Supabase
- [ ] Edge Functions deployed: `dispatch-engine`, `create-payment-intent`, `stripe-webhook`, `confirm-mbway-payment`, `notify-driver`
- [ ] Migration `fcm_token` aplicada (`supabase db push`)
- [ ] `google-services.json` instalado em `android/app/` (para push notifications)
- [ ] 2 dispositivos físicos ou emuladores: **Dispositivo A** (cliente) + **Dispositivo B** (driver)
- [ ] Supabase Realtime activo (verificar no Dashboard → Realtime)

---

## Teste 1 — Criar conta e login

### Cliente (Dispositivo A)
- [ ] Abrir app → seleccionar role "Cliente"
- [ ] Login com demo: `cliente@bora.app` / `123456`
- [ ] Logout → login novamente → sessão persiste? (não pede login)
- [ ] Ou: Criar conta nova com email real

### Driver (Dispositivo B)
- [ ] Abrir app → seleccionar role "Driver"
- [ ] Login com demo: telefone `910000000` / `123456`
- [ ] Logout → login novamente → sessão persiste?
- [ ] Driver aparece como **online** no mapa cliente?

**Critério de sucesso:** ambos os perfis autenticados e sessão persiste após fechar/reabrir app.

---

## Teste 2 — Fazer pedido (Cliente — Dispositivo A)

- [ ] Seleccionar restaurante/loja na lista
- [ ] Adicionar 1-3 itens ao carrinho
- [ ] Clicar "Ver carrinho" → confirmar preço e itens
- [ ] Inserir morada de entrega
- [ ] Ir para checkout

### Pagamento Cartão Stripe
- [ ] Seleccionar "Cartão"
- [ ] Usar cartão de teste: `4242 4242 4242 4242` / exp: qualquer data futura / CVV: `123`
- [ ] Pagamento aceite? (sem erro)
- [ ] Pedido criado com status `preparing`?

### Pagamento Cash
- [ ] Criar novo pedido → seleccionar "Cash"
- [ ] Pedido criado? (sem necessidade de Stripe)
- [ ] Status `preparing`?

### Pagamento MBWay
- [ ] Criar novo pedido → seleccionar "MBWay"
- [ ] Inserir número de telefone
- [ ] Simulação confirma? Status `preparing`?

**Critério de sucesso:** pelo menos um método de pagamento cria pedido com status `preparing`.

---

## Teste 3 — Dispatch automático (server-side)

*Com pedido em `preparing` ou `callingDriver`:*

- [ ] Status avança automaticamente para `callingDriver`? (max ~10s para non-partner)
- [ ] No Supabase Dashboard → `orders` table: `current_driver_offer_id` tem o ID do driver?
- [ ] `driver_offer_expires_at` está preenchido?

**No Dispositivo B (Driver):**
- [ ] Oferta de pedido aparece no ecrã do driver?
- [ ] Timer de contagem decrescente visível (~40s)?
- [ ] **Push notification recebida?** (se Firebase configurado — app em background)

**Critério de sucesso:** oferta aparece no driver em <60s após pedido criado.

---

## Teste 4 — Driver aceita e entrega (Dispositivo B)

- [ ] Driver clica **"Aceitar"**
- [ ] Status muda para `driverAccepted`?
- [ ] **Dispositivo A (Cliente) vê o status actualizado?** (via Realtime)
- [ ] Nome/foto do driver aparece no ecrã do cliente?

- [ ] Driver chega ao local → clica **"Cheguei / Recolhi"**
- [ ] Status muda para `pickedUp`?
- [ ] Cliente vê mudança?

- [ ] Driver em movimento → clica **"A caminho"**
- [ ] Status muda para `onTheWay`?
- [ ] **Cliente vê mapa com localização do driver em tempo real?**

- [ ] Driver chega à entrega → insere **código de 4 dígitos** (código que o cliente vê)
- [ ] Status muda para `delivered`?
- [ ] **Ambos os dispositivos mostram "Entregue"?**

**Critério de sucesso:** fluxo completo sem necessidade de refresh manual em nenhum dispositivo.

---

## Teste 5 — Pós-entrega (verificar no Supabase)

Após `delivered`, verificar no Supabase Dashboard → SQL Editor:

```sql
-- Verificar tokens do driver
SELECT * FROM bora_tokens WHERE role = 'driver' ORDER BY created_at DESC LIMIT 5;
-- Deve ter uma linha com amount = 40

-- Verificar tokens do cliente
SELECT * FROM bora_tokens WHERE role = 'client' ORDER BY created_at DESC LIMIT 5;
-- Deve ter uma linha com amount = ROUND(price * 0.03)

-- Para pedido cash: verificar saldo do driver
SELECT * FROM driver_balances WHERE driver_id = '<driver_id>';
-- Deve estar actualizado
```

- [ ] Tokens atribuídos ao driver (40 tokens)?
- [ ] Tokens atribuídos ao cliente (3% do preço)?
- [ ] Se cash: `driver_balances` actualizado?

---

## Teste 6 — Edge cases

### Driver rejeita
- [ ] Driver clica **"Rejeitar"**
- [ ] Pedido avança para o próximo driver disponível? (max ~40s)
- [ ] Driver rejeitado não volta a receber a mesma oferta imediatamente?

### Timeout sem resposta
- [ ] Driver não faz nada durante 40s
- [ ] Sistema avança automaticamente para o próximo driver?
- [ ] Chain de redispatch funciona?

### Sem drivers online
- [ ] Desligar todos os drivers (is_online = false no Supabase)
- [ ] Pedido fica em `callingDriver` sem crashar?
- [ ] Quando driver fica online → oferta é enviada automaticamente?

### App fechada e reaberta
- [ ] Fechar app do cliente com pedido em curso
- [ ] Reabrir app → mostra estado actual do pedido?
- [ ] Fechar app do driver com entrega em curso
- [ ] Reabrir app → mostra estado actual?

---

## Teste 7 — Admin Dashboard

- [ ] Aceder ao dashboard (role admin)
- [ ] Métricas financeiras carregam?
- [ ] Transacção do teste 1-5 aparece?

---

## Resultado Final

| Teste | Resultado | Notas |
|---|---|---|
| 1 — Login e sessão | ⬜ Pass / ⬜ Fail | |
| 2 — Criar pedido | ⬜ Pass / ⬜ Fail | |
| 3 — Dispatch | ⬜ Pass / ⬜ Fail | |
| 4 — Driver flow completo | ⬜ Pass / ⬜ Fail | |
| 5 — Tokens + saldo | ⬜ Pass / ⬜ Fail | |
| 6 — Edge cases | ⬜ Pass / ⬜ Fail | |
| 7 — Admin Dashboard | ⬜ Pass / ⬜ Fail | |

**Se todos os testes passam → PRONTO PARA LANÇAMENTO**

**Se algum falha → reportar qual teste, qual passo, e o erro observado.**

---

## Notas de debugging rápido

| Sintoma | Onde verificar |
|---|---|
| Pedido fica em `preparing` para sempre | Supabase Logs → `dispatch-engine` |
| Driver não recebe oferta | `orders.current_driver_offer_id` no Dashboard |
| Stripe payment_intent falha | Supabase Logs → `create-payment-intent` |
| Realtime não actualiza | Supabase → Realtime → Inspect |
| Push não chega | Supabase Logs → `notify-driver`; verificar `drivers.fcm_token` |
| Tokens não atribuídos | Supabase → SQL → verificar trigger `fn_award_tokens_on_delivery` |
