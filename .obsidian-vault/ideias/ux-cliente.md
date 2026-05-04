# UX — Melhorias para o Cliente (App Bora)

> Comparação com Uber Eats, iFood e Glovo — oportunidades concretas

---

## 🏠 Ecrã Principal (Home)

### O que os concorrentes fazem bem
- **iFood**: homepage modular adaptativa com banners personalizados por hora do dia (manhã → café, tarde → almoço)
- **Glovo**: "Flash Deals" em destaque no topo, muda a cada hora
- **Uber Eats**: secção "Pedir de novo" com os restaurantes mais usados pelo utilizador

### Melhorias para a Bora
- [ ] **Secção "Os teus favoritos"** — mostrar os 3 restaurantes/lojas mais pedidos (usar `favorite_store.dart` que já existe mas não está ligado ao home)
- [ ] **Saudação personalizada** — "Bom dia, João!" com sugestão baseada na hora ("Aqui está o teu almoço favorito")
- [ ] **Banner de promoção** — espaço no topo para o Danilo colocar promoções sazonais
- [ ] **Categorias visuais** com ícones grandes: Restaurantes, Supermercado, Enviar Pacote, Carregar Compras

---

## 🛒 Fluxo de Pedido

### O que os concorrentes fazem bem
- **Uber Eats**: máximo 3 taps para confirmar pedido
- **Glovo**: preview do tempo de entrega ANTES de entrar no restaurante
- **iFood**: opção de agendar entrega para hora específica

### Melhorias para a Bora
- [ ] **Tempo estimado visível na lista de restaurantes** — mostrar "~25 min" antes de clicar
- [ ] **Confirmação rápida de pedido repetido** — "Repetir o último pedido?" em 1 tap
- [ ] **Notas para o restaurante** — campo de texto livre por produto ("sem cebola")
- [ ] **Upsell inteligente** — "Queres adicionar uma bebida?" no momento do checkout

---

## 📍 Tracking em Tempo Real

### O que os concorrentes fazem bem
- **Uber Eats**: mostra o nome e foto do driver, botão para ligar directamente
- **Glovo**: animação do rider no mapa com rota suave
- **iFood**: notificações push a cada mudança de estado ("O restaurante está a preparar o teu pedido!")

### Melhorias para a Bora
- [ ] **Foto do driver no ecrã de tracking** — o `driver_model.dart` já tem campo de foto
- [ ] **Chat em contexto** — botão de mensagem directa ao driver visível no ecrã de tracking
- [ ] **ETA dinâmico** — actualizar "chega em X minutos" com base na localização real do driver
- [ ] **Notificação de saída** — "O João saiu para ir buscar o teu pedido!"

---

## 💳 Pagamentos

### O que os concorrentes fazem bem
- **iFood**: integração com Pix (instantâneo, sem taxas)
- **Uber Eats**: carteira digital com saldo
- **Glovo**: Apple Pay e Google Pay nativos

### Melhorias para a Bora
- [ ] **Google Pay / Apple Pay** — Stripe suporta nativamente, reduz fricção no checkout
- [ ] **Guardar cartão para próxima vez** — Stripe suporta `Customer` + saved payment methods
- [ ] **Histórico de pagamentos** no perfil do cliente
- [ ] **MBWay real** — quando implementado, é diferenciador forte em Portugal

---

## ⭐ Ratings e Feedback

### O que os concorrentes fazem bem
- **Uber Eats**: sistema de tags ("Rápido", "Comida quente", "Embalagem boa")
- **iFood**: separação entre avaliação do restaurante e do entregador
- **Glovo**: pedir avaliação apenas 10 min depois da entrega (não imediatamente)

### Melhorias para a Bora
- [ ] **Tags rápidas de feedback** — botões tipo "Rápido ✓", "Simpático ✓", "Pontual ✓" além das estrelas
- [ ] **Delay na notificação de avaliação** — pedir feedback 15 min depois da entrega
- [ ] **Feedback negativo com opções** — "O que correu mal?" com opções (produto errado, frio, embalagem partida)

---

## 🔔 Notificações

### O que os concorrentes fazem bem
- **Todos**: notificações para cada mudança de estado
- **iFood**: notificação quando o restaurante aceita, quando o rider sai, quando está a 1 min

### Melhorias para a Bora
- [ ] Notificações para: pedido confirmado → preparando → driver a caminho → entregue
- [ ] Opção de desactivar notificações por tipo no perfil
- [ ] **Deep link** na notificação → abre directamente o ecrã do pedido

---

## 🌙 Dark Mode e Acessibilidade
- [ ] Suporte a dark mode do sistema (Flutter suporta `ThemeMode.system`)
- [ ] Tamanho de texto ajustável (Flutter `textScaleFactor`)
- [ ] Contraste adequado em todos os ecrãs (verificar cores actuais em `config/colors.dart`)
