# Regras de Negócio Encontradas no Código

> Regras que estão implícitas no código Flutter/Edge Functions. Devem ser conhecidas e documentadas.

---

## Pagamentos

### Buffer de Reconciliação (nonPartnerPurchase)
- **Buffer:** +15% sobre o valor estimado pré-autorizado
- **Ficheiro:** `lib/config/business_rules.dart` + `supabase/functions/_shared/business_rules.ts`
- **Regra:** Se valor_real > valor_estimado × 1.15 → cobrança extra automática
- **Regra:** Se valor_real < valor_estimado → reembolso automático da diferença

### Métodos de Pagamento Disponíveis
- **Stripe Card:** Totalmente funcional (modo teste ainda activo — BUG-014)
- **MBWay:** UI presente mas sem integração real (BUG-013)
- **Dinheiro:** Sem processamento online; driver confirma recepção

### Comissão da Plataforma
- Definida em `business_rules.dart` (valor exacto a verificar no ficheiro)
- Aplicada sobre cada pedido de restaurante parceiro

---

## Delivery / Despacho

### Algoritmo de Atribuição de Driver
- Critérios (por ordem de prioridade): distância < capacidade < rating/score
- Raio máximo de procura definido em `business_rules.dart`
- **Máximo de tentativas:** 3 drivers antes de alerta ao admin
- **Timeout por driver:** se não responde em X segundos → próximo candidato

### Tipos de Veículo / Capacidade
- `driver_capacity_service.dart` gere a capacidade por tipo de pedido
- Drivers têm tipos de veículo que limitam os pedidos que podem aceitar
- (Ex: bicicleta não aceita pedidos de supermercado pesados)

### Batching de Pedidos
- Definido nas regras de negócio: um driver pode ter X pedidos simultâneos
- Documentado em `negocios/precos-e-taxas.md` (já existente)

---

## Reservas de Mesa

### Estados das Reservas
```
pending → confirmed → seated → completed
                   ↘ cancelled
```
- Parceiro confirma/recusa quando recebe
- Sistema não tem confirmação automática (manual pelo parceiro)
- Ver detalhes em `negocios/reservas-de-mesa.md`

### Regras de Capacidade
- Configurável por parceiro (número de mesas, capacidade por mesa)
- Sem validação automática de conflitos de horário (a verificar)

---

## Tokens / Loyalty

- Sistema completo documentado em `negocios/tokens-e-loyalty.md`
- `ConsentStore` gere o GDPR antes de qualquer token ser atribuído
- Tokens têm data de expiração

---

## Aprovação de Drivers

### Fluxo de aprovação
1. Driver regista-se + envia documentos
2. Status inicial: `pending`
3. Admin revê em `admin_driver_approval_screen.dart`
4. Admin aprova → status: `approved` → driver pode começar a trabalhar
5. Admin rejeita → status: `rejected` → driver vê `driver_rejected_screen.dart`

### Documentos necessários
- (A verificar no `driver_signup_screen.dart` — campos exactos)

---

## GDPR e Consentimento

- **ConsentBanner** envolve toda a app (definido em `main.dart`)
- `consent_store.dart` persiste o consentimento via SharedPreferences
- Edge Function `delete-account` existe mas fluxo completo não implementado
- Tokens só devem ser atribuídos após consentimento explícito

---

## Tipos de Utilizador e Permissões

| Tipo | Pode fazer | Não pode fazer |
|------|-----------|----------------|
| Cliente | Pedir, cancelar*, avaliar, reservar | Gerir produtos, ver outros clientes |
| Driver | Aceitar/recusar pedidos, actualizar localização | Gerir produtos, ver dados de outros drivers |
| Parceiro | Gerir produtos, confirmar pedidos, ver reservas | Ver dados de outros parceiros, gerir drivers |
| Admin | Tudo | — |

*cancelamento pelo cliente ainda não implementado (BUG-017)

---

## Regras de Preços (resumo)

- Taxa de entrega: calculada por distância em `pricing_service.dart`
- Preço mínimo de pedido: a verificar em `business_rules.dart`
- Gorjeta: não implementada (feature futura identificada)
- Comissão do parceiro: deduzida automaticamente nos pagamentos

---

## Dados do Backend Node.js (server.js / payment_server.js)

- Servidor Node.js hospedado no Render.com (ver `render.yaml`)
- `payment_server.js` → complementa as Edge Functions para casos específicos
- `.env` contém chaves Stripe e Firebase (nunca commitar)
- `firebase-service-account.json.json` presente no backend (dupla extensão — possível erro de naming)
