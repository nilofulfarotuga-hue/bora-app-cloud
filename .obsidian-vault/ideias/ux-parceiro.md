# UX — Melhorias para o Parceiro (Dashboard Bora)

> Comparação com Uber Eats Manager, iFood para Parceiros, Glovo Merchant — oportunidades concretas

---

## 📊 Dashboard Principal

### O que os concorrentes fazem bem
- **Uber Eats Manager (2025)**: dashboard mobile com Menu, Insights e Payouts numa única app
- **iFood**: relatórios em tempo real, comparação semana a semana
- **Glovo**: métricas de performance (tempo médio de preparação, taxa de cancelamento)

### Melhorias para a Bora
- [ ] **Resumo diário no topo** — "Hoje: X pedidos · Y€ de receita · Z min tempo médio"
- [ ] **Gráfico simples de pedidos por hora** — para o parceiro perceber os picos (usar `fl_chart` que já está na dependência!)
- [ ] **Comparação "Hoje vs. Ontem"** — seta verde/vermelha simples
- [ ] **Alerta de produtos esgotados** — notificação quando um produto está em ruptura

---

## 🍽️ Gestão de Produtos

### O que os concorrentes fazem bem
- **Uber Eats**: toggle instantâneo "disponível/indisponível" por produto sem sair do ecrã
- **iFood**: gestão de horários por produto (só disponível ao almoço, por ex.)
- **Glovo**: upload de foto directamente da câmara com recorte automático

### Melhorias para a Bora
- [ ] **Toggle rápido por produto** — botão on/off visível na lista sem precisar de editar
- [ ] **Stock mínimo** — campo "últimas X unidades" que aparece no menu do cliente
- [ ] **Ordenação de produtos por drag-and-drop** — controlar a ordem em que aparecem
- [ ] **Duplicar produto** — criar variações rapidamente (Ex: Pizza M → copiar → Pizza G)

---

## 📦 Gestão de Pedidos

### O que os concorrentes fazem bem
- **Uber Eats**: sons diferentes para novo pedido vs. pedido urgente
- **iFood**: confirmação de pedido com 1 tap + timer visual para aceitar
- **Glovo**: impressão automática de ticket para a cozinha (integração com impressoras)

### Melhorias para a Bora
- [ ] **Timer visual para aceitar** — pedido novo tem countdown de 60s antes de ir para outro parceiro
- [ ] **Som de alerta personalizado** — `audioplayers` já está na dependência, aproveitar
- [ ] **Vista "Cozinha"** — ecrã simplificado só com pedidos activos, sem menus (para tablet na cozinha)
- [ ] **Tempo de preparação editável** — parceiro pode ajustar "Este pedido demora 20 min" por pedido

---

## 💰 Financeiro

### O que os concorrentes fazem bem
- **iFood Pago**: conta digital integrada, pagamentos semanais automáticos
- **Uber Eats**: histórico de payouts com filtros por período
- **Glovo**: facturação automática gerada pelo sistema

### Melhorias para a Bora
- [ ] **Extracto mensal** — listagem de todos os pedidos com comissão deduzida e valor líquido
- [ ] **Previsão do mês** — "Com base nas últimas 2 semanas, este mês deves receber X€"
- [ ] **Botão "Exportar para Excel"** — parceiros precisam disto para contabilidade
- [ ] **Data de próximo pagamento** visível no dashboard

---

## 📅 Reservas de Mesa

### Situação Actual
A Bora já tem `partner_reservations_screen.dart` e `reservation_model.dart`

### Melhorias
- [ ] **Calendário visual** — ver todas as reservas do dia num calendário (hora × mesa)
- [ ] **Confirmação/recusa rápida** com mensagem automática ao cliente
- [ ] **Capacidade por hora** — configurar "máximo 20 pessoas às 20h"
- [ ] **Lista de espera** — quando lotado, adicionar cliente à fila e notificar se cancelar

---

## 🔔 Notificações para Parceiros

### Melhorias
- [ ] **Notificação push quando chega novo pedido** (PushNotification já existe no projeto!)
- [ ] **Alerta de driver a chegar** — "O driver está a 5 min do teu estabelecimento"
- [ ] **Resumo nocturno** — notificação às 23h com o resumo do dia (pedidos, receita)

---

## 📸 Perfil do Parceiro

### Melhorias
- [ ] **Horário de funcionamento** — definir dias e horas em que aparece na app
- [ ] **Fotos do espaço** — galeria de fotos para o perfil do restaurante
- [ ] **Responder a avaliações** — parceiro pode responder às reviews dos clientes
- [ ] **Link externo** — website ou redes sociais no perfil
