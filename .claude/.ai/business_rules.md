# BORA APP — REGRAS DE NEGÓCIO v2

**Versão:** 2026-04-17
**Projeto:** Bora App — Plataforma de Entregas, Restauração e Serviços (Guarda, Portugal)
**Stack:** Flutter + Supabase
**Contacto:** +351 937 501 673 · boraappbora@gmail.com
**Logótipo:** "B" verde escuro (#1B5E20) + motociclista vermelho/laranja

---

## 1. ESTRUTURA GERAL DA PLATAFORMA

### 1.1 Tipos de Utilizador
- **Cliente** — faz pedidos/reservas, paga, recebe entregas ou serviços
- **Estafeta (Driver)** — aceita pedidos, faz recolha e entrega
- **Empregada de Limpeza** — presta serviços de limpeza (futuro)
- **Parceiro** — restaurante/loja com acordo comercial
- **Admin** — Danilo (único por agora)

### 1.2 Tipos de Serviço
- `restaurant` — restaurante parceiro (saco pronto para recolha)
- `storeShopping` — compra no mercado (estafeta compra por conta do cliente)
- `carryGroceries` — levar compras que o cliente já fez (requer carro)
- `sendPackage` — enviar encomenda de A para B
- `restaurantReservation` — reserva de mesa em restaurante parceiro (lançamento)
- `restaurantTakeaway` — cliente vai buscar ao restaurante (lançamento)
- `homeCleaning` — limpeza de casa (futuro, ver secção 18)
- `marketplace` — compra internacional (futuro, ver secção 17)

### 1.3 Progressão de Status do Pedido (Delivery)
`created` → `preparing` → `callingDriver` → `driverAccepted` → `pickedUp` → `onTheWay` → `delivered`

### 1.4 Progressão de Status da Reserva de Mesa
`reservation_requested` → `restaurant_responding` → (`accepted` | `suggested_alternative` | `rejected`) → `confirmed` → `customer_arrived` → `completed` ou `no_show`

---

## 2. TAXAS E PREÇOS (DELIVERY LOCAL)

### 2.1 Taxa de Entrega (cliente paga)
- Até 4 km: **€2,50**
- Acima de 4 km: **€2,50 + €0,50 por km adicional**

### 2.2 Taxa de Serviço
- Cobrada separadamente do valor dos produtos

### 2.3 Entrega no Apartamento
- Surcharge adicional de **+€1,50** quando cliente ativa
- Divisão: **€1,00 estafeta / €0,50 Bora**

### 2.4 Markup nos Produtos (Delivery Local)
**Parceiro** (total 20% em 3 camadas):
- 10% comissão cobrada ao parceiro
- +5% adicional no preço do produto (invisível, cliente não percebe)
- +5% taxa de serviço ao cliente

**Não-Parceiro:** 15% sobre o preço (invisível, lucro da Bora)

### 2.5 Sacos de Transporte
- **Restaurante parceiro:** 1 saco fixo, **€0,30** (automático)
- **Mercado (storeShopping):** **€0,10 por saco**, contados pelo estafeta (mín 0, máx 20)

---

## 3. PAGAMENTOS

### 3.1 Métodos Aceites
- Cartão de crédito/débito (Stripe)
- MBWay
- Dinheiro

### 3.2 Limite de Dinheiro
- **Máximo €40,00** por pedido
- Validação em duas camadas: Flutter + trigger DB

### 3.3 Buffer Stripe 15% (cartão em não-parceiros)
Pré-autorização de **+15% a mais** do valor estimado.

**Finalidade:** cobrir variações do preço final (produto em falta, troca por similar).

**Importante:** cliente não perde este dinheiro. É libertado automaticamente após a compra real.

**Aviso obrigatório ao cliente antes de pagar:**
> "Reservámos no teu cartão 15% a mais do valor estimado, por segurança. Se algum produto estiver em falta, o estafeta pode trocá-lo por outro de preço parecido. Pagas apenas o valor real — o extra é libertado do teu cartão."

**Trocas em caso de falta:**
- Estafeta pergunta ao cliente pelo chat primeiro
- Se cliente não responder, estafeta pode trocar sozinho por produto de preço parecido
- Estafeta usa os 15% de reserva para cobrir diferenças

### 3.4 Pagamento ao Estafeta
- Automático semanal, segunda-feira às 3h (`bora_weekly_auto_payout`)
- Valor mínimo para processar: **€10,00** (abaixo acumula para a semana seguinte)

---

## 4. SISTEMA DE TOKENS

### 4.1 Valor e Conversão
- **100 tokens = €0,50**
- Validade: **60 dias**
- Consumo: **FIFO** (primeiros a entrar, primeiros a sair)

### 4.2 Como se Ganham Tokens

| Quem | Quando | Quantidade |
|---|---|---|
| Estafeta | Por entrega | **+40 tokens** |
| Estafeta | Entrega adicional (stacking) | **+50 tokens** |
| Cliente | Por pedido | **3% do valor** em tokens |

### 4.3 Como se Usam Tokens
**Cliente:** desconto até **50% do valor do pedido**

**Estafeta (Prioridade no dispatch):**
- 5 min → 50 tokens
- 10 min → 90 tokens
- 15 min → 125 tokens
- 1 hora → 400 tokens

**Estafeta:** converter em € no pagamento semanal

### 4.4 Tabelas e Triggers
- Tabela: `bora_tokens`
- Trigger: `trg_award_tokens_on_delivery`
- **Constraint:** `amount INTEGER CHECK (amount > 0)` — saldo negativo virtual **não** suportado.
  Para reduzir saldo de um utilizador, usar `admin_revoke_token_grant(token_id, reason)` em
  grants específicos (audit trail mais limpo). Grants individualmente revogados ficam
  marcados `is_used=true` e deixam de contar para o balance.

### 4.5 Gorjetas (Tips)
- Cliente pode dar gorjeta na altura de pagar **ou** depois da entrega (ao avaliar)
- Valores sugeridos: **1€ · 2€ · 3€ · 5€** + campo livre
- Divisão: **80% estafeta, 20% Bora**

---

## 5. REMUNERAÇÃO DO ESTAFETA

### 5.1 Cálculo por Entrega
- Base: **€3,80**
- Distância: **+€0,20 por km**
- Taxa de entrega: **+€0,80**
- Parceiro: **+€3,00 adicional** por entrega parceira

### 5.2 Driver Help (ajudante)
**Quando:** só em mercados e restaurantes **não-parceiros**

**Quem pede:** o estafeta principal carrega no botão "Preciso de ajuda" na app

**Quem ajuda:** dispatch normal escolhe o estafeta mais próximo (40s para aceitar)

**Quanto ganha o ajudante:** **€4** fixos

**De onde sai:** do ganho do estafeta principal (não é custo extra para a Bora)

**Exemplo:** Compra de 150€ no mercado. Principal ia ganhar 12€ sozinho. Com ajuda: principal recebe 8€, ajudante recebe 4€.

### 5.3 Pagamento Semanal
- Processado segunda-feira às 3h
- Mínimo €10 para processar (abaixo acumula)
- Transferido para o IBAN cadastrado

---

## 6. DISPATCH (ATRIBUIÇÃO DE PEDIDOS)

### 6.1 Arquitetura Geral
- Motor: **Edge Function** `dispatch-engine` (v31)
- Accionado por pg_cron (cada minuto) E imediatamente quando:
  - Novo pedido entra em `callingDriver`
  - Estafeta liga online
  - Estafeta recusa ou o timeout expira

### 6.2 Algoritmo de Seleção (ordem)
1. **SLA Crítico primeiro** (pedido com ≥7 minutos em espera)
2. **Não-parceiro primeiro** (`is_partner_store = false` tem prioridade)
3. **FIFO geográfico:** se há drivers a ≤200m do pickup, o mais próximo ganha
4. **Distância:** se nenhum a ≤200m, escolhe o mais próximo em ≤10km
5. **Prioridade:** drivers com `priority_until` ativo são preferidos

### 6.3 Timeout de Oferta
- **40 segundos** para o estafeta aceitar ou recusar
- Se não responder → próximo driver
- Driver recusante entra em `tried_driver_ids`
- Se todos tentados → reset do ciclo

### 6.4 Stacking (Múltiplos Pedidos)
- **Máximo 3 pedidos** em simultâneo por estafeta
- Oferecidos **1 de cada vez** — nunca 2 diálogos simultâneos
- Critério para juntar pedidos (batching): distância ≤ **3 km** entre lojas

### 6.5 Guard Anti-Duplicação (v31)
- `findNextDriver()` exclui drivers com oferta ativa noutro pedido
- `assignDriver()` usa lock optimista (UPDATE com WHERE guards)

### 6.6 Rota Multi-Stop
- **Sequência obrigatória:** TODOS os pickups primeiro, depois TODOS os dropoffs
- Exemplo com 3 pedidos: Loja 1 → Loja 2 → Loja 3 → Cliente 1 → Cliente 2 → Cliente 3
- Quando um pickup é confirmado, os stops são recalculados automaticamente

---

## 7. FLUXO DO ESTAFETA

### 7.1 Oferta de Pedido
Quando há novo pedido próximo, a app do estafeta:
- Toca **som de alerta**
- Mostra **diálogo com timer de 40 segundos**:
  - Nome do estabelecimento
  - Valor do pedido
  - Ganhos estimados
  - Distância
  - Tokens a ganhar
- **Regra crítica:** apenas **1 diálogo de cada vez** — se chegar segundo pedido enquanto há diálogo ativo, é descartado (não se empilha)
- Som para quando o diálogo é fechado (aceitar/recusar/timeout)
- Se diálogo for descartado pelo guard, não toca som

### 7.2 Mapa do Estafeta
- Marcador do estafeta: **seta verde** (#1B5E20) com bearing (direção de movimento)
- Rota desenhada com polylines
- Nome + km de cada stop (ex: "McDonald's · 1,2 km")
- Botão "Navegar" → abre Google Maps externo
- Botão de centralizar → centra câmara no driver
- Câmara roda com bearing (tipo Uber)

### 7.3 Fluxo em Restaurante Parceiro
1. Driver chega ao restaurante
2. Clica "Confirmar recolha" (saco já pronto)
3. Status → `pickedUp`
4. App dirige para o cliente
5. Entrega → **código de 4 dígitos** (cliente mostra o código)
6. Status → `delivered`

### 7.4 Fluxo em Não-Parceiro (mercado/loja sem acordo)
1. Driver chega ao estabelecimento
2. Abre checklist ("Ver compras")
3. Marca cada item: "Comprado" ✅ ou "Não há" ❌
4. Pode adicionar produtos extra (com preço)
5. Define número de sacos (€0,10 cada)
6. Clica "Confirmar compra"
7. Diálogo "Valor da compra" → driver preenche valor real do caixa
8. Confirma → `isPurchaseFinalized = true`, `finalTotal` guardado
9. **Só agora** aparece "Confirmar recolha"
10. Driver confirma → `pickedUp`
11. App dirige para o cliente
12. Entrega → código 4 dígitos → `delivered`

### 7.5 Fluxo `sendPackage` (enviar encomenda)
- Cliente **tem obrigatoriamente** de tirar foto da encomenda antes de pedir
- Estafeta vê a foto antes de aceitar → evita surpresas de tamanho/peso
- Recolha no ponto A → entrega no ponto B → código 4 dígitos

### 7.6 Fluxo `carryGroceries` (levar compras)
- Cliente já fez as compras
- Cliente **tem obrigatoriamente** de tirar foto das compras antes de pedir
- Estafeta vê a foto antes de aceitar
- **Requer carro** — motas/bicicletas não recebem este tipo de pedido
- Recolha em casa do cliente → entrega no destino → código 4 dígitos

### 7.7 Cancelamento pelo Estafeta
- Pode cancelar em `driverAccepted` ou `pickedUp`
- Diálogo de confirmação: "Cancelar pedido? O pedido volta para o sistema."
- Se confirmar:
  - Status volta a `callingDriver`
  - `assigned_driver_id` → null
  - Driver entra em `tried_driver_ids`
  - Dispatch re-invocado automaticamente
- Implementação: função DB `driver_cancel_order()` com SECURITY DEFINER

---

## 8. FLUXO DO CLIENTE

### 8.1 Fazer Pedido
1. Seleciona categoria (Restaurantes, Supermercados, Farmácia, Enviar Encomenda, Levar Compras, Reservas)
2. Escolhe estabelecimento
3. Adiciona produtos ao carrinho
4. Seleciona método de pagamento
5. Confirma endereço de entrega
6. Opção "Entregar no apartamento" (+€1,50)
7. Pode aplicar desconto de tokens (até 50%)
8. Pode adicionar gorjeta (1€/2€/3€/5€ ou valor livre)
9. "Finalizar pedido"

### 8.2 Acompanhamento
Ecrã "Estafeta a caminho" mostra:
- Mapa com posição do estafeta
- Nome e rating do estafeta
- Código de entrega (4 dígitos)
- Moradas de recolha e entrega
- Total do pedido
- Lista de items (com status: comprado/indisponível)
- Chat com o estafeta

### 8.3 Cancelamento pelo Cliente

| Momento | Taxa |
|---|---|
| Antes do estafeta aceitar | **€1,00** |
| Estafeta a caminho do restaurante | **€2,50** (taxa de entrega) |
| Estafeta já tem a comida/compras | **100%** do pedido (sem devolução) |

### 8.4 Reembolso por Falha de Serviço
Quando o serviço falha (estafeta não chegou, comida errada, compras estragadas):
- Cliente contacta suporte Bora
- Bora analisa e decide caso a caso
- Pode ser reembolso parcial, total, ou em tokens

### 8.5 Histórico de Pedidos
- Tab "Pedidos" carrega imediatamente ao abrir (com spinner)
- Lista todos os pedidos por data
- Clicando → detalhes completos com items, preços e status

### 8.6 Perfil do Cliente
- Nome, email, telefone
- Foto de perfil (opcional, pode adicionar da galeria)
- Histórico de tokens
- Histórico de pedidos
- Histórico de reservas
- Suporte
- Apagar conta (ver secção 20)
- Terminar sessão

---

## 9. SLA (ACORDO DE NÍVEL DE SERVIÇO)

### 9.1 Tempo Base
- SLA base: **10 minutos** desde o pedido até dispatch confirmado
- SLA de alerta (crítico): **7 minutos** — pedido sobe na fila de prioridade

### 9.2 Alertas
- Aos 7 minutos sem driver: pedido marcado como crítico
- Dispatch continua tentando drivers até encontrar
- Admin recebe notificação no painel de pedidos críticos

---

## 10. CATEGORIAS DA APP

### 10.1 Restaurantes (Parceiros)
- Menu gerido pela Bora (parceiro edita no seu painel)
- Markup 10+5+5%
- Saco fixo €0,30
- Podem ter **reserva de mesa** e **takeaway** (ver secção 14)

### 10.2 Restaurantes (Não-Parceiros)
- Driver compra no local
- Markup 15% invisível
- Fluxo de checklist

### 10.3 Supermercados
- Fluxo de `storeShopping` (checklist completo)
- Driver compra os items listados pelo cliente
- Sacos a €0,10 cada

### 10.4 Farmácia
- Fluxo semelhante a supermercado
- Mesma lógica de checklist

### 10.5 Enviar Encomenda (sendPackage)
- Cliente prepara a encomenda
- **Foto obrigatória** antes de pedir
- Driver recolhe e entrega
- Requer veículo adequado ao tamanho

### 10.6 Levar Compras (carryGroceries)
- Cliente já fez as compras
- **Foto obrigatória** antes de pedir
- Serviço `carryGroceries`
- **Requer carro** (não aceita motas ou bicicletas)

### 10.7 Reservas de Mesa
- Nova funcionalidade do lançamento
- Ver secção 14 completa

---

## 11. CADASTRO E APROVAÇÃO DO ESTAFETA

### 11.1 Campos Obrigatórios
- Nome completo
- Email e password
- Telefone
- Tipo de veículo (mota, carro, bicicleta)
- Matrícula (obrigatória exceto bicicleta)
- IBAN português (PT50 + 21 dígitos = 25 caracteres)
- **Foto pessoal (selfie)**
- **Tipo de documento + Número do documento**
- **Foto do documento**
- **Foto do veículo** (obrigatória exceto bicicleta)
- **Aceitação obrigatória dos Termos e Política de Privacidade** (checkbox)

### 11.2 Fluxo de Aprovação
1. Estafeta submete candidatura
2. Status: `pending`
3. Admin revê fotos e documentos no painel
4. Se todos os campos obrigatórios preenchidos → pode aprovar
5. Se faltam campos → aprovação bloqueada com mensagem dos campos em falta
6. Aprovado: `approved` → estafeta pode trabalhar
7. Rejeitado: `rejected` com motivo

### 11.3 Tipos de Veículo e Capacidades

| Veículo | Pode fazer |
|---|---|
| **Mota** | Restaurantes parceiros e não-parceiros, pequenas compras, encomendas pequenas |
| **Carro** | Tudo, incluindo `carryGroceries` e encomendas grandes |
| **Bicicleta** | Entregas pequenas, sem matrícula obrigatória |

### 11.4 Armazenamento de Documentos
- Bucket: `driver-documents` (privado)
- Path: `{userId}/selfie.jpg`, `{userId}/document.jpg`, `{userId}/vehicle.jpg`

---

## 12. CANCELAMENTOS (RESUMO GERAL)

### 12.1 Pelo Cliente (Delivery)
Ver secção 8.3.

### 12.2 Pelo Estafeta (Delivery)
Ver secção 7.7.

### 12.3 Pelo Cliente (Reserva de Mesa)
- **Até 4 horas antes:** reembolso total do pré-pagamento €3
- **Menos de 4 horas antes:** perde os €3
- **No-show (não aparece):** perde os €3

### 12.4 Pelo Restaurante (Reserva)
- Restaurante pode **rejeitar** um pedido de reserva → cliente recebe reembolso total dos €3
- Ver fluxo completo em secção 14

### 12.5 Pelo Admin
- Admin pode cancelar qualquer pedido ou reserva manualmente pelo painel
- Motivo obrigatório no cancelamento (aparece ao cliente)
- Bora decide se há reembolso e quanto

> **Implementado em commit 11c7497 (Fase 4 BUG 3).**
> Gaps documentados: GAP-1 (full refund em pickedUp/onTheWay como decisão Q4 — Bora absorve), GAP-2 (cliente vê mensagem mapeada do reason_code, não o motivo literal), GAP-3 (refund parcial/tokens não suportados). Ver ADR `.claude/.ai/decisions/2026-04-29-fase4-bug3-refund-policy.md`.

---

## 13. AVALIAÇÕES (RATINGS)

### 13.1 Quem Avalia Quem

| Quem avalia | A quem | Público/Privado |
|---|---|---|
| Cliente | Estafeta | Pública (outros clientes não veem, mas o estafeta vê) |
| Cliente | Restaurante parceiro | Pública |
| Estafeta | Cliente | **Privada** (só a Bora vê) |

### 13.2 Formato
- **1–5 estrelas**
- **Etiquetas rápidas:** simpático, rápido, limpo, profissional, denúncia, etc.
- **Comentário opcional**

### 13.3 Regras
- **Opcional** (cliente/estafeta pode saltar)
- Avaliação do cliente pelo estafeta é **privada** — evita vinganças
- **Sem automatismo:** a Bora analisa casos problemáticos manualmente no painel admin (ver secção 16)

### 13.4 Gorjeta Associada
- No ecrã de avaliação, cliente pode dar gorjeta (se ainda não deu no pagamento)
- Ver divisão em secção 4.5

---

## 14. CARDÁPIO DIGITAL + RESERVAS (LANÇAMENTO)

### 14.1 Conceito
Cada restaurante parceiro tem uma **página digital completa** dentro da app, com **3 opções na mesma página:**
- Entrega ao domicílio
- Takeaway (cliente vai buscar)
- Reserva de mesa

**Diferenciação:** nenhuma plataforma na Guarda oferece reserva de mesa integrada. Uber Eats e Glovo só fazem entrega.

### 14.2 Estrutura da Página do Restaurante
- Nome, morada, horários, avaliação média
- Categorias de pratos em scroll horizontal (ex: combos, sushi, massas, menus)
- Cada prato: foto, nome, código, preço, descrição, botão "adicionar ao carrinho"
- Observações por prato: "sem cebola", "molho à parte", etc.

### 14.3 Cardápio Digital
- Restaurante gere totalmente o cardápio no seu painel
- Pode atualizar pratos, preços, fotos e disponibilidade a qualquer momento
- Disponibilidade por horário (ex: menu almoço só aparece 12h–15h)

### 14.4 Fluxo de Reserva de Mesa

**Passo 1 — Cliente pede:**
- Número de pessoas (1 a 8+)
- Data
- Hora (**slots de 30 minutos** — ex: 19:00, 19:30, 20:00)
- Tipo de refeição (almoço / jantar / criança com preço reduzido)
- Nota opcional (aniversário, mesa junto à janela, etc.)
- Cliente paga **€3 de pré-pagamento**
- Status: `reservation_requested`

**Passo 2 — Restaurante recebe notificação e responde:**
Restaurante tem 3 opções:
- **Aceitar** → `confirmed`, cliente recebe push
- **Sugerir outra hora** → `suggested_alternative` (ex: "às 20h estamos cheios, pode ser 20h30?")
- **Recusar** → `rejected`, cliente recebe reembolso total dos €3 automático

**Passo 3 — Se o restaurante sugeriu alternativa:**
- Cliente recebe a sugestão por notificação
- Pode: **aceitar** / **propor outra alternativa** / **desistir** (reembolso total)
- Diálogo continua até acordo ou desistência

### 14.5 Pré-Pagamento €3 (Anti No-Show)
**Se cliente comparece:**
- €3 são descontados da conta final
- Distribuição: **€1 Bora + €2 restaurante** (taxa de serviço + compensação mesa)

**Se cliente cancela até 4 horas antes:**
- Reembolso total ao cliente

**Se cliente cancela com menos de 4 horas OU não aparece:**
- Cliente perde €3
- Distribuição: **€1 Bora + €2 restaurante**

**Se restaurante rejeita o pedido:**
- Reembolso total automático ao cliente

### 14.6 Lembretes Automáticos
- **24 horas antes** → notificação push ao **cliente**: "Lembras-te da tua reserva amanhã às 20h no [Restaurante]?"
- **2 horas antes** → notificação push ao **cliente**: "A tua reserva é daqui a 2 horas. Ainda podes cancelar com reembolso total."
- **30 minutos antes** → notificação ao **restaurante** no painel: "Reserva daqui a 30 min — [nome cliente] ([nº pessoas] pessoas). Prepara a mesa."

### 14.7 Painel do Parceiro — Secção Reservas
- **Reservas pendentes** com:
  - Nome do cliente
  - Histórico na Bora (novo / cliente fiel / nº pedidos)
  - Detalhes (pessoas, data, hora, notas)
  - Confirmação do pré-pagamento
- **Botões:** Aceitar / Sugerir outra hora / Recusar
- **Timeline visual do dia** — todas as reservas organizadas por hora
- **Botão "Marcar sentado"** quando o cliente chega → status `customer_arrived`
- **Resumo mensal:** total de reservas, receita gerada, no-shows

### 14.8 Status da Reserva
`reservation_requested` → `restaurant_responding` → (`accepted` | `suggested_alternative` | `rejected`) → `confirmed` → `customer_arrived` → `completed` ou `no_show`

### 14.9 Takeaway
- Cliente escolhe "Ir buscar" em vez de "Entrega"
- Sem taxa de entrega (€2,50)
- Sem estafeta envolvido
- Cliente recebe notificação quando o pedido está pronto
- Hora estimada visível desde o início

### 14.10 Activação de Reservas pelo Parceiro
- Reservas de mesa são OPCIONAIS — não todos os restaurantes têm mesas
- Por defeito: reservas DESLIGADAS (reservations_enabled = false)
- O parceiro activa/desactiva no seu painel a qualquer momento
- Quando desligado: botão "Reservar mesa" NÃO aparece ao cliente
- Quando ligado: botão "Reservar mesa" aparece na página do restaurante
- Campo na DB: restaurants.reservations_enabled (boolean, default false)
- Só restaurantes com reservations_enabled = true mostram reservas

---

## 15. ENTRADA DE PARCEIROS (ONBOARDING)

### 15.1 Canais para Candidatura
O restaurante/loja pode candidatar-se por 3 vias:
- **Contacto direto:** telefone ou WhatsApp para +351 937 501 673
- **Formulário no site:** www.boraapp.pt/parceiro (quando existir)
- **Na app:** descarregar Bora e escolher "Sou parceiro" no registo

### 15.2 Dados Obrigatórios
- Nome do restaurante/loja
- Morada
- NIF / Nome da empresa
- Nome e telefone do responsável
- Email
- IBAN (para receber pagamentos)
- Foto do espaço / logotipo
- Horário de funcionamento
- Tipo de cozinha (italiana, japonesa, etc.)
- **Aceitação dos Termos e Condições parceiro** (checkbox obrigatório)

### 15.3 Prazo de Aprovação
- **Até 3 dias úteis** para resposta
- Admin revê candidatura no painel e aceita ou rejeita
- Candidato recebe notificação por email

### 15.4 Custo de Entrada
- **Grátis** — parceiro não paga taxa de adesão nem mensalidade
- Bora só ganha com a comissão por pedido (10+5+5%)

---

## 16. PAINEL ADMIN

### 16.1 Acesso
- **Só Danilo** por agora (único admin)
- Futuro: permissões por nível quando houver equipa

### 16.2 Áreas do Painel

**1. Pedidos ao Vivo (mapa global)**
- Vê todos os pedidos em tempo real
- Mapa com posição dos estafetas
- Alertas de SLA crítico

**2. Aprovação de Estafetas**
- Lista de candidaturas pendentes
- Revê fotos, documentos, veículo, IBAN
- Aprovar ou rejeitar com motivo

**3. Aprovação de Parceiros**
- Mesma lógica para restaurantes/lojas
- Prazo 3 dias úteis

**4. Gestão de Parceiros**
- Editar dados de parceiros existentes
- Suspender/ativar parceiro
- Ver histórico de vendas

**5. Ganhos e Pagamentos Semanais**
- Ver próximo payout (segunda-feira 3h)
- Histórico de transferências aos estafetas
- Acerto manual quando necessário

**6. Reclamações**
- Ver e responder a reclamações de clientes
- Decidir reembolsos caso a caso

**7. Avaliações Baixas**
- Lista de estafetas e parceiros com média < 3 estrelas
- Rever comentários privados
- Decidir ações (avisar, suspender, despedir)

**8. Gestão de Tokens**
- Dar tokens grátis a utilizadores (compensação, campanhas)
- Ver balance de todos os utilizadores
- Auditoria de transações

**9. Relatórios e Estatísticas**
- Pedidos por dia/semana/mês
- Receita total e por categoria
- Zonas mais quentes
- Conversão, ticket médio, etc.

**10. Bloquear/Suspender Utilizadores**
- Suspender cliente, estafeta ou parceiro
- Motivo obrigatório
- Notificação automática

**11. Cancelamento Manual de Pedidos**
- Admin pode cancelar qualquer pedido ativo
- Motivo obrigatório (aparece ao cliente)
- Decide reembolso manualmente

> **Implementado em commit 11c7497 (Fase 4 BUG 3).**
> Gaps documentados: GAP-1 (full refund em pickedUp/onTheWay como decisão Q4 — Bora absorve), GAP-2 (cliente vê mensagem mapeada do reason_code, não o motivo literal), GAP-3 (refund parcial/tokens não suportados). Ver ADR `.claude/.ai/decisions/2026-04-29-fase4-bug3-refund-policy.md`.

**12. Descontos Manuais**
- Admin pode aplicar desconto em qualquer pedido
- Usar para compensações, promoções especiais, VIP

---

## 17. MARKETPLACE (FUTURO)

### 17.1 Estado
- **Futuro** — planeado, não desenvolvido ainda

### 17.2 Categorias
- Tudo o que AliExpress vende (sem restrições)

### 17.3 Entrega
- **Correios normais** (CTT, DPD) — não envolve estafetas Bora
- Estafetas Bora focam-se só no delivery local

### 17.4 Duas Opções de Prazo
- **Entrega Rápida (Europa):** 3–7 dias (fornecedor europeu)
- **Entrega Padrão (AliExpress):** 2–4 semanas

### 17.5 Markup Escalonado

| Preço de custo | Markup |
|---|---|
| Até 10€ | **+40%** |
| 10–50€ | **+30%** |
| 50–150€ | **+30%** |
| Acima de 150€ | **+20%** |

Markup invisível. Cliente nunca vê preço de custo.

### 17.6 Devoluções
- **Cliente resolve direto com o fornecedor** — Bora é intermediária
- **Aviso obrigatório ao cliente** antes de comprar:
  > "Produto vendido por [fornecedor]. Problemas com o produto? Contactar [fornecedor]. A Bora é apenas intermediária."

---

## 18. LIMPEZA DE CASAS (FUTURO)

### 18.1 Estado
- **Futuro** — planeado, não desenvolvido ainda
- Lançamento após consolidação do delivery

### 18.2 Quem Faz
- **Empregadas domésticas independentes**, cadastradas na Bora (fluxo semelhante aos estafetas)
- Documentos, aprovação pelo admin, contas IBAN

### 18.3 Como Cobrar (cliente escolhe)
- **Por hora** (ex: 10€/hora)
- **Por tamanho da casa** (T0, T1, T2, T3, T4+)
- **Pacotes fixos** (limpeza básica, limpeza profunda, limpeza pós-mudanças)

### 18.4 Divisão do Valor
- **85%** para a empregada
- **15%** para a Bora

### 18.5 Produtos de Limpeza
Cliente escolhe na marcação:
- **Sem produtos** (cliente tem em casa, empregada só usa)
- **Com produtos** (empregada traz, **+€10** cobrado ao cliente)

---

## 19. STORAGE (BUCKETS)

### 19.1 Buckets Supabase
- `avatars` — fotos de perfil de clientes (público, upload por authenticated)
- `driver-documents` — documentos dos estafetas (privado)
- `product-images` — imagens dos produtos (público)
- `products` — outros ficheiros de produtos (público)
- `restaurant-photos` — logos e fotos dos parceiros (público)

### 19.2 Políticas
- Cada utilizador só faz upload para a sua própria pasta
- Path foto cliente: `avatars/{userId}.jpg`
- Path documentos driver: `{userId}/selfie.jpg`, `{userId}/document.jpg`, `{userId}/vehicle.jpg`

---

## 20. GDPR E PROTEÇÃO DE DADOS

### 20.1 Consentimento no Registo
- Checkbox **obrigatório** "Aceito os Termos e Política de Privacidade"
- Sem aceitar, não é possível registar
- Data/hora do consentimento guardada para prova legal

### 20.2 Apagar Conta
Utilizador pode pedir na app (Perfil → Apagar conta).

**Apaga imediatamente:**
- Nome, foto, telefone, endereços
- Conversas de chat
- Avaliações dadas
- Tokens
- Nome em pedidos antigos → substituído por "Utilizador apagado"

**Guarda 10 anos (obrigação legal AT):**
- Faturas (número, valor, data, NIF se fornecido)
- Extratos fiscais
- Comprovativos de pagamento Stripe

**Aviso obrigatório ao pedir apagar:**
> "Os teus dados pessoais serão apagados imediatamente. Por obrigação legal, os dados fiscais (faturas) são guardados por 10 anos. Confirmar?"

### 20.3 Consentimento de Cookies/Tracking
Banner na primeira abertura com **3 botões:**
- **Aceitar tudo**
- **Rejeitar**
- **Gerir preferências**

Rastreamento coberto: localização, análise de uso, notificações.

### 20.4 Contacto de Proteção de Dados
- Email: **boraappbora@gmail.com**
- Cliente pode pedir:
  - "Que dados têm sobre mim?"
  - "Corrige este dado"
  - "Dá-me os meus dados em ficheiro"
- Bora responde em até 30 dias (obrigação legal)

---

## 21. RLS (SEGURANÇA DE DADOS)

### 21.1 Tabela `orders`
- Cliente só vê os seus pedidos (`user_id = auth.uid()`)
- Driver só vê pedidos atribuídos a ele ou com oferta ativa
- Parceiro só vê pedidos do seu estabelecimento

### 21.2 Tabela `drivers`
- Driver só edita o seu perfil
- Admin lê todos

### 21.3 Tabela `driver_transactions`
- Driver lê e insere as suas transações
- Admin lê todas

### 21.4 Tabela `reservations`
- Cliente só vê as suas reservas
- Restaurante só vê as suas
- Admin lê todas

---

## 22. NOTIFICAÇÕES

### 22.1 Push Notifications (Firebase)
- **Driver:** notificação quando há nova oferta
- **Cliente:** atualizações de pedido (preparação, a caminho, entregue)
- **Cliente:** lembretes de reserva (24h, 2h antes)
- **Restaurante:** novo pedido, pedido de reserva, lembrete 30min antes
- Edge Function: `notify-driver`, `notify-customer`, `notify-partner`
- FCM token guardado na tabela respetiva

### 22.2 Som no App do Driver
- Toca som ao chegar oferta
- Para quando diálogo é fechado
- Não toca se o diálogo foi descartado pelo guard

---

## 23. CHAT

### 23.1 Chat Driver ↔ Cliente
- Disponível após driver aceitar o pedido
- Ambos podem enviar mensagens
- Visível enquanto o pedido estiver ativo

### 23.2 Chat Cliente ↔ Suporte
- Disponível sempre no Perfil → Suporte
- Futuro: chatbot de IA que aprende com Q&A

---

## 24. ATUALIZAÇÕES AUTOMÁTICAS DE PRODUTOS

### 24.1 Mercados (pg_cron)
Produtos atualizados automaticamente:
- Segunda: Mercadona
- Terça: Continente
- Quarta: Pingo Doce
- Quinta: Lidl
- Sexta: Auchan
- Sábado: Intermarché

### 24.2 Restaurantes Parceiros
- Próprio restaurante atualiza quando quiser (painel)
- 1× por mês (dia 1) — verificação automática de consistência

---

## 25. CONFIGURAÇÕES TÉCNICAS

### 25.1 Supabase
- Project ID: `ojykpzwqrtusfeakzrna`
- Edge Functions críticas: `dispatch-engine` (v31), `notify-driver`, `update-products`

### 25.2 Dispatch Engine — Constantes (NÃO alterar sem aprovação)
- Ficheiro: `supabase/functions/dispatch-engine/index.ts`
- Versão atual: v31
- Constantes:
  - `OFFER_TIMEOUT_SECONDS = 40`
  - `MAX_ORDERS_PER_DRIVER = 3`
  - `FIFO_RADIUS_KM = 0.2` (200m)
  - `BATCHING_RADIUS_KM = 3.0` (3 km entre lojas)
  - `SLA_CHECK_MINUTES = 7`
  - `SLA_BASE_MINUTES = 10`
  - `PREFERRED_RADIUS_KM = 10`

### 25.3 Flutter — Zonas Protegidas
Ficheiros críticos que NÃO devem ser editados sem análise prévia:
- `lib/services/pricing_service.dart`
- `lib/dispatch/driver_capacity_service.dart`
- `lib/stores/order_store.dart` (método `finalizePurchase`)
- Triggers DB: `bora_tokens`, `trg_award_tokens_on_delivery`
- Stripe: qualquer código de pagamento

---

## 26. CHECKLIST DE LANÇAMENTO

### 26.1 Funcionalidades Prontas ✅
- Dispatch engine (v31) com stacking até 3 pedidos
- Fluxo completo cliente (pedido → entrega)
- Fluxo completo estafeta (oferta → entrega)
- Sistema de tokens (ganho e uso)
- Pagamentos Stripe, MBWay, dinheiro
- Chat driver↔cliente
- Sacos (restaurante €0,30 fixo, mercado €0,10/saco)
- Checklist de compras no mercado
- Notificações push
- Cadastro e aprovação de estafetas
- Mapa com seta de bearing
- Cancelamento pelo estafeta
- Foto de perfil do cliente
- Histórico de pedidos
- Avaliações com etiquetas (BR §13) ✅
- Gorjetas/Tips — widget + DB (BR §4.5) ✅
- Fotos obrigatórias sendPackage/carryGroceries (BR §7.5/7.6) ✅
- Takeaway em parceiros (BR §14.9) ✅
- Reservas de mesa — fluxo base (BR §14) ✅
- Driver Help — botão + DB + RPC (BR §5.2) ✅
- Painel admin — reservas + avaliações (BR §16) ✅
- GDPR — checkbox registo, apagar conta, banner cookies (BR §20) ✅
- Cancelamento pelo cliente com taxas (BR §8.3) ✅
- Bugs corrigidos: botão voltar Android, foto perfil, checkbox estafeta ✅

### 26.2 A Desenvolver Para Lançamento
- Ecrã avaliação abrir automaticamente após entrega
- Botão "Reservar mesa" no ecrã do restaurante (com guard `reservations_enabled`, ver §14.10)
- Takeaway bypass no dispatch
- Gorjeta no checkout
- Pré-pagamento €3 nas reservas (Stripe)
- Toggle `reservations_enabled` no painel do parceiro (ver §14.10)

### 26.3 Futuro (Pós-Lançamento)
- Marketplace (secção 17)
- Limpeza de casas (secção 18)
- Chatbot de suporte IA
- Expansão para outras cidades

---

## 27. ATUALIZAÇÃO AUTOMÁTICA DE PRODUTOS DOS MERCADOS

### 27.1 Calendário Semanal (pg_cron)
- Segunda-feira: Mercadona (API pública tienda.mercadona.es)
- Terça-feira: Continente
- Quarta-feira: Pingo Doce
- Quinta-feira: Lidl
- Sexta-feira: Auchan
- Sábado: Intermarché
- Domingo: descanso / retry de falhas da semana

### 27.2 Requisitos de Qualidade (revisto 2026-04-18)

- Mínimo 5.000 produtos por mercado.
- **Fotos podem ser partilhadas entre mercados SE for o mesmo produto** (ex.: uma lata de Coca-Cola é a mesma em qualquer mercado). Match por `(nome_normalizado, marca, unidade)`.
- **PROIBIDO** usar fotos fictícias (placeholder recoloriado, imagem gerada, fallback repetido em lote).
- **PROIBIDO** usar foto de produto diferente (ex.: foto de leite num produto de iogurte).
- **Preços NUNCA partilhados** — cada mercado guarda o seu preço real, actualizado na mesma operação do scraper.
- Nomes dos produtos em português.
- Cascata canónica de imagens (tentar por ordem, parar no primeiro hit válido):
  1. **L1** — site oficial do próprio mercado (CDN do mercado).
  2. **L2** — biblioteca partilhada de outros mercados (Mercadona primeiro, depois os restantes), match por `(nome_normalizado, marca, unidade)`.
  3. **L3** — site oficial da marca (`brand_low` / `brand_mid` / `brand_premium`).
  4. **L4** — pesquisa de imagens: Bing Image Search (1.000/mês grátis) primeiro, Google Custom Search (3.000/mês grátis) como fallback.
  5. Se todos falharem → `photo_url = NULL` + `needs_photo = true`. **Nunca** guardar foto fictícia.
- Orçamento L4: €50/mês tecto máximo. Alerta admin aos €30 (80 %). Paragem obrigatória aos €50.

### 27.3 Mercadona (funciona)
- API pública: https://tienda.mercadona.es/api/categories/
- Extrai: nome, preço, foto CDN, unidade
- Tradução automática PT via mapCategoryPT()
- Estado actual: 5.011 produtos ✅

### 27.4 Outros Mercados (a implementar)
- Continente: API semi-aberta (Salesforce Commerce Cloud)
- Pingo Doce: scraping pingodoce.pt
- Lidl: scraping lidl.pt
- Auchan: scraping auchan.pt
- Intermarché: scraping intermarche.pt
- Análise legal obrigatória antes de implementar cada scraper

### 27.5 Regras Anti-Falha
- Se scraper falha → log + alerta admin + retry no domingo.
- Se menos de 5.000 produtos → alerta admin.
- Se foto em falta depois da cascata L1→L4 (§27.2) → `photo_url = NULL` + `needs_photo = true`. **PROIBIDO** usar foto fictícia ou foto de produto diferente como fallback.
- Máximo 1 pedido por segundo por mercado/host (anti-blocking).
- Orçamento L4 (Bing/Google Images): alerta aos €30, paragem obrigatória aos €50 por mês.

### 27.6 Estado Actual (pós-Fase 4, 2026-04-18)

Âmbito actual: cidade Guarda (`restaurant_id` com sufixo `-guarda`). Expansão a outras cidades é pós-lançamento.

Pós Fase 4 (Continente + Auchan via SFCC HTTP directo):

| Mercado             | Produtos | Com foto | L1    | L2  | `needs_photo` | Meta ≥5.000 | Estado              |
|---------------------|---------:|---------:|------:|----:|--------------:|:-----------:|---------------------|
| mercadona-guarda    | 5.011    | 5.011    | 5.011 | 0   | 0             | ✅          | OK                  |
| continente-guarda   | **6.332**| 4.304    | 4.303 | 1   | 2.028         | ✅          | +1.500 bestsellers L1 |
| auchan-guarda       | **4.503**| 1.505    | 1.500 | 5   | 2.998         | ❌ (−497)   | +1.500 bestsellers SFCC L1; reharvest restantes |
| pingodoce-guarda    | 3.101    | 64       | 59    | 5   | 3.037         | ❌ (−1.899) | Deferido — sem endpoint HTTP público |
| lidl-guarda         | 3.002    | 0        | 0     | 0   | 3.002         | ❌ (−1.998) | Deferido — SPA com auth 401; falta scraper |
| intermarche-guarda  | 3.004    | 5        | 0     | 5   | 2.999         | ❌ (−1.996) | Deferido — sem loja online; fallback OFF existente |

Fotos cleared na Fase 3: **14.064** (3.888 badges + 10.176 cross-leaks sem match). Fase 4 adicionou **+3.000 L1** reais em 2 mercados via SFCC HTTP directo (zero Playwright). Scraper SFCC funciona para Continente e Auchan (ambas `demandware.store/Sites-*-Site/*/Search-UpdateGrid?srule=best-sellers`). Pingo Doce/Lidl/Intermarché ficam deferidos para Fase 4b (Playwright ou folheto PDF). Reharvest L2→L4 dos `needs_photo` pertence ao par `market-scraper` + `market-harvester`, orquestrado por `products-updater`.

---

*Documento de regras de negócio — Bora App*
*Última atualização: 2026-04-18 (§27.6 actualizado — Fase 4 Continente +1.500 / Auchan +1.500 via SFCC L1; Pingo Doce/Lidl/Intermarché deferidos; cascata L1→L4 + orçamento L4 €50/mês; âmbito `-guarda`)*
*Atualizar sempre que houver mudanças nas regras de negócio*
*Fonte de verdade usada por: todas as skills do sistema*
