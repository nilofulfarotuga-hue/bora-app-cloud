# BORA — BUSINESS RULES (FONTE DE VERDADE ABSOLUTA)

> Este documento contém TODAS as regras operacionais do sistema Bora.
> Estas regras têm prioridade sobre qualquer outra lógica, decisão,
> implementação ou análise.

REGRAS:

* NÃO modificar
* NÃO reinterpretar
* NÃO simplificar
* NÃO otimizar sem autorização

---

## 🧠 CONTEXTO

Sistema híbrido:

* delivery
* logística
* personal shopper
* economia (tokens)

Objetivo:

* eficiência
* lucro
* batching inteligente

---

## 🚚 DISPATCH (CRÍTICO)

### Modelo

* sequencial (NÃO broadcast)
* 1 driver por vez

---

### Capacidade

* padrão: 1 pedido
* fallback: até 3

---

## 🔁 REGIME DE DISPATCH (CRÍTICO)

### Regime A — FIFO geográfico

* aplicado quando driver ≤ 200m do pickup
* ordenação: timestamp (FIFO)
* distância NÃO interfere

---

### Regime B — distância

* aplicado quando driver > 200m
* ordenação: distância crescente

---

### Transição

* ao entrar no raio → passa para FIFO imediatamente
* ao sair → volta para distância

---

## 🔥 PRIORIDADE GLOBAL (ORDEM OBRIGATÓRIA)

1. SLA crítico
2. Não parceiro (mesmo estabelecimento)
3. FIFO geográfico (≤200m)
4. Distância
5. Batching

⚠️ Esta ordem NÃO pode ser alterada

---

## 📦 BATCHING

* raio: 15km
* janela: 3 min

### Formação

* primeiro pedido inicia janela
* outros entram se:

  * dentro do raio
  * regra válida

Critério obrigatório:

combined < individual * 1.20

---

### Fechamento

* ao atingir 3 min OU
* ao atingir limite de pedidos

---

## ⏱️ SLA

* 10 min base

Check 7 min:

* ≤500m OU ≤2min ETA

Extensão:

* automática
* máx +5 min

---

### Integração SLA

Pedidos próximos de violar SLA:

* prioridade máxima
* podem ignorar FIFO

---

## 💰 PAGAMENTO

### Cliente

* paga antes
* desconto até 1€

---

### Driver (parceiro)

* pedido adicional:

  * +3€
  * +50 tokens

---

## 🛒 NÃO PARCEIRO

### Preço

* +15% embutido (invisível)

---

### Taxas

* entrega
* serviço

---

### Driver

* 3,80€
* +0,20€/km
* +0,80€
* +40 tokens

---

### Bônus lucro

* 30% lucro plataforma

---

## 👥 DRIVER HELP

* custo: 4€
* interno
* 1 ajudante

---

## 💼 PARCEIROS (MODELO HÍBRIDO)

* 10% parceiro
* +5% produto
* +5% taxa serviço

---

## 🚚 ENTREGA

* 2,50€ até 4km
* +0,50€/km

---

## 📍 LOCALIZAÇÃO ERRADA

* 2€ (1/1)

---

## 📞 CLIENTE AUSENTE

* sem reembolso

---

## ⚠️ CANCELAMENTO

* antes: 1,50€
* depois: 50%
* compra: 100%

---

## 🪙 TOKENS

### Driver

* +40 tokens ao finalizar (delivered)

### Cliente

* ~3% após pagamento confirmado

### Regras

* expira: 60 dias
* 100 = 0,50€
* máximo 50% uso

---

## 🔄 ESTADOS

created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered

---

## 🚫 REGRAS CRÍTICAS

* NÃO broadcast
* NÃO quebrar FIFO
* NÃO duplicar cobrança
* NÃO violar estados
* NÃO alterar ordem de prioridade global

---

## 📐 CONSTANTES

* PARTNER_COMMISSION = 0.10
* NON_PARTNER_MARKUP = 0.15
* TOKEN_VALUE = 0.005
* DRIVER_HELP = 4

---

**FIM — FONTE DE VERDADE ABSOLUTA**
