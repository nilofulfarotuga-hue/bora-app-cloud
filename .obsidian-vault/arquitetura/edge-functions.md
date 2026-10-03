# Edge Functions Supabase — Bora App

> Inventário completo das 9 Edge Functions, para que servem e estado actual.

---

## Mapa de Edge Functions

| Nome | Método | Trigger | Estado |
|------|--------|---------|--------|
| `create-payment-intent` | POST | Cliente faz checkout com Stripe | ✅ Implementada |
| `stripe-webhook` | POST | Stripe envia confirmação de pagamento | ✅ Implementada |
| `confirm-mbway-payment` | POST | Cliente paga com MBWay | ⚠️ Incompleta |
| `dispatch-engine` | POST | Pedido entra em `callingDriver` | ✅ Implementada |
| `notify-driver` | POST | Sistema quer notificar um driver | ✅ Implementada |
| `charge-extra` | POST | Compra real > estimativa | ✅ Implementada (não testada) |
| `refund` | POST | Compra real < estimativa | ✅ Implementada (não testada) |
| `client-cancel-order` | POST | Cliente cancela pedido | ⚠️ UI não implementado |
| `delete-account` | POST | Cliente pede eliminação de conta (GDPR) | ⚠️ GDPR incompleto |
| `update-products` | POST | Actualização de produtos em lote | ✅ Implementada |

---

## Detalhes de cada Edge Function

### `create-payment-intent`
**Propósito:** Cria um PaymentIntent no Stripe com o valor do pedido  
**Input:** `{ amount, currency, orderId, customerId }`  
**Output:** `{ clientSecret }` → enviado para o app Flutter para confirmar no cliente  
**Depende de:** Stripe Secret Key (env var no Supabase)  
**Chamado por:** `payment_service.dart`

### `stripe-webhook`
**Propósito:** Recebe eventos do Stripe (pagamento confirmado, falhou, reembolso)  
**Trigger:** Stripe envia POST automaticamente após eventos  
**Acções:** Actualiza `payment_status` na tabela `orders`  
**Segurança:** Deve validar `Stripe-Signature` header

### `confirm-mbway-payment` ⚠️
**Propósito:** Confirmar pagamento via MBWay/SIBS  
**Estado actual:** Endpoint existe mas a integração real com MBWay não está feita  
**O que falta:** Integração com API SIBS/EuPago/Ifthenpay  

### `dispatch-engine`
**Propósito:** Algoritmo central de atribuição de pedidos a drivers  
**Lógica:**  
1. Lista drivers disponíveis e dentro do raio de entrega  
2. Ordena por (distância + capacidade + score)  
3. Tenta atribuir ao melhor candidato  
4. Retry logic se driver recusa/não responde  
**Paralelo com:** `lib/dispatch/dispatch_engine.dart` (versão Flutter local)  
**Nota:** Existe duplicação da lógica entre o Flutter e a Edge Function — a Edge Function deve ser a fonte de verdade

### `notify-driver`
**Propósito:** Enviar push notification Firebase/FCM ao driver seleccionado  
**Input:** `{ driverId, orderId, message }`  
**Depende de:** Firebase Service Account (ficheiro no backend)

### `charge-extra`
**Propósito:** Cobrar ao cliente a diferença quando a compra real > estimativa  
**Input:** `{ orderId, extraAmount }`  
**Acções:** Captura valor adicional no PaymentIntent original  
**Estado:** Implementada mas não testada em produção  

### `refund`
**Propósito:** Reembolsar ao cliente a diferença quando compra real < estimativa  
**Input:** `{ orderId, refundAmount }`  
**Acções:** Cria Refund no Stripe  
**Estado:** Implementada mas não testada em produção  

### `client-cancel-order`
**Propósito:** Processar cancelamento de pedido pelo cliente (com ou sem reembolso)  
**Estado:** Edge Function existe, UI no app não implementado  
**Regras pendentes:** Definir políticas de cancelamento (gratuito antes de preparar, taxa após)

### `delete-account`
**Propósito:** Eliminar conta do utilizador (requisito GDPR)  
**Estado:** Existe mas GDPR não está completamente implementado  
**O que falta:** Confirmar que apaga todos os dados pessoais de todas as tabelas

### `update-products`
**Propósito:** Actualizar catálogo de produtos do parceiro em lote  
**Chamado por:** `partner_products_screen.dart`  

---

## Ficheiros Partilhados (supabase/functions/_shared/)

### `business_rules.ts`
Regras de negócio centralizadas: raio de entrega, taxas, buffers de pagamento  
**Importante:** Deve estar em sincronia com `lib/config/business_rules.dart` no Flutter

### `cors.ts`
Headers CORS para permitir chamadas do app Flutter  
**Nota:** Em produção, restringir origins para o domínio da app

---

## Variáveis de Ambiente Necessárias (Supabase Dashboard)

| Variável | Usado por |
|----------|-----------|
| `STRIPE_SECRET_KEY` | create-payment-intent, charge-extra, refund |
| `STRIPE_WEBHOOK_SECRET` | stripe-webhook |
| `FIREBASE_SERVICE_ACCOUNT` | notify-driver |
| `SUPABASE_SERVICE_ROLE_KEY` | Todas (para bypass de RLS) |
