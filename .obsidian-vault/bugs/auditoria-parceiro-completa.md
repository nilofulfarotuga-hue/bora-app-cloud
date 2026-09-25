# Auditoria Parceiro — Completa (vs Uber Eats Manager / Glovo Partner / iFood Gestor de Pedidos)
> Data: 2026-04-24
> Âmbito: fluxo do parceiro (restaurante / loja) da Bora App
> Stack: Flutter + Supabase + Provider
> Ficheiros analisados:
> - `lib/screens/partner_dashboard_screen.dart`
> - `lib/screens/partner_login_screen.dart`
> - `lib/screens/partner_earnings_screen.dart`
> - `lib/screens/partner_hours_screen.dart`
> - `lib/screens/partner_products_screen.dart`
> - `lib/screens/register_partner_screen.dart`
> - `lib/screens/add_product_screen.dart`
> - `lib/screens/restaurant_dashboard_screen.dart`
> - `lib/screens/admin/admin_partners_screen.dart` (+ admin_*)
> - `lib/stores/partner_product_store.dart`
> - `lib/stores/restaurant_store.dart`
> - `lib/stores/order_store.dart` (parte parceiro: linhas 1168–1210)
> - `lib/auth/auth_store.dart` (parte parceiro: linhas 786–870)
> - `lib/services/sound_service.dart`
> - `lib/services/notification_service.dart`

---

## 🔴 BUGS CRÍTICOS

### [BUG-PT-001] `partner_login_screen.dart` — falta botão "Esqueceu a palavra-passe?"
**Ficheiro:** `lib/screens/partner_login_screen.dart`
**Sintoma:** Existe `resetPasswordForEmail` em `AuthStore` mas o ecrã de login do parceiro NÃO expõe nenhum `TextButton` "Esqueceu a palavra-passe?". O `client_login_screen.dart` tem-no; o do parceiro **não**. Parceiro que perca password fica fora da app.
**Impacto:** Parceiro perde acesso ao seu negócio sem alternativa. Crítico para SLA.
**Fix:** Adicionar `TextButton(onPressed: _forgot, child: Text('Esqueceu a palavra-passe?'))` por baixo do botão Entrar e chamar `authStore.resetPartnerPassword(email)` (criar wrapper análogo a `resetDriverPassword`).

### [BUG-PT-002] `auth_store.dart:807-845` — `registerPartner` cria o parceiro **localmente** e só faz `signUp` em background fire-and-forget
**Ficheiro:** `lib/auth/auth_store.dart` (linhas 786–845)
**Sintoma:** O novo parceiro é gravado em `_partnersByEmail` e em SharedPreferences ANTES de o `signUp` no Supabase confirmar. Se o `signUp` falhar (email já existente, password fraca, rede), o parceiro fica num estado fantasma — local sim, Supabase não → não consegue iniciar sessão noutros dispositivos, não recebe pedidos via realtime/RLS, mas no dispositivo onde registou parece estar logado.
**Fix:** Tornar o `signUp` síncrono com `await`, só persistir local após sucesso, e mostrar erro real ao utilizador.

### [BUG-PT-003] `restaurant_store.dart` — `registerPartnerRestaurant` gera ID com `microsecondsSinceEpoch`
**Ficheiro:** `lib/stores/restaurant_store.dart` (`registerPartnerRestaurant`)
**Sintoma:** `id: 'partner-${DateTime.now().microsecondsSinceEpoch}'` — colisão possível entre dispositivos (relógios divergentes / rebootados) e desalinhado com Supabase que normalmente preferiria UUID. Insert poderá ser aceite mas depois realtime de `restaurants` recebe payload com id ad-hoc, divergindo de qualquer convenção dos outros recursos (orders usam timestamp+rng ou uuid).
**Fix:** Usar `Uuid().v4()` (já dependência) ou deixar o Supabase gerar (`gen_random_uuid()` na coluna) e ler-o de volta.

### [BUG-PT-004] `restaurant_store.dart` — `registerPartnerRestaurant` faz fallback para `via.placeholder.com`
**Ficheiro:** `lib/stores/restaurant_store.dart` (`registerPartnerRestaurant`)
**Sintoma:** Se o parceiro não der foto, é gerado `https://via.placeholder.com/240x140.png?text=Nome`. Esse domínio terceiro **morreu** (foi descontinuado em 2024). Resultado: cards de restaurante sem imagem em produção.
**Fix:** Usar asset local `assets/images/restaurant_placeholder.png` (idêntico ao que o cliente espera) ou exigir foto obrigatória no registo (Uber Eats / Glovo / iFood **exigem foto na onboarding**).

### [BUG-PT-005] `restaurant_store.dart` `updatePartnerProduct` — fire-and-forget sem rollback nem feedback
**Ficheiro:** `lib/stores/restaurant_store.dart` (`updatePartnerProduct`)
**Sintoma:** Atualiza local primeiro, depois `supabase.from('products').update(...).then().catchError(debugPrint)`. Se falhar em rede:
- Local diz "produto atualizado a 8.50€"
- Supabase continua com 7.50€
- Outros parceiros / clientes veem 7.50€
- O dono do restaurante vende ao preço errado.
**Fix:** Aguardar com `await`, mostrar erro, fazer rollback do estado local em falha. Igual para `addPartnerProduct` / `deletePartnerProduct`.

### [BUG-PT-006] `partner_dashboard_screen.dart` — som/vibração de novo pedido **não existe**
**Sintoma:** A pesquisa por `SoundService`, `playLoop`, `Vibration`, `HapticFeedback` no contexto do `partner_dashboard_screen.dart` retorna **nada**. Só o `driver_home_screen.dart` toca som (`_soundService.playLoop()`) ao receber novo pedido. O parceiro recebe o pedido em silêncio — basta o telemóvel estar com ecrã desligado e o pedido não é notado durante minutos.
**Comparação:** Uber Eats Manager, Glovo Partner e iFood Gestor de Pedidos **tocam som contínuo em loop** até o parceiro carregar em "Aceitar". É o ponto #1 do produto.
**Fix:** Adicionar `SoundService` + `Vibration.vibrate(pattern: [0, 500, 250, 500])` em `partner_dashboard_screen.dart` no listener de novos pedidos `created` (filtrar `partnerOrders.where((o) => o.status == OrderStatus.created)`).

### [BUG-PT-007] `partner_dashboard_screen.dart` — sem push notification quando o parceiro está com app em background
**Sintoma:** O `order_store.dart:557-576` faz fire-and-forget de FCM push para o restaurante, mas:
1. Não há registo do `restaurantId → fcm_token` (procurar `partner_fcm_tokens` na BD — não existe).
2. `notification_service.dart` não está montado dentro do `partner_dashboard_screen.dart` para subscrever ao tópico do restaurante.
**Resultado:** Push é "enviado" mas nunca chega ao dispositivo do dono. Pedido cai no vazio.
**Fix:** Tabela `partner_devices(restaurant_id, fcm_token, platform)`; registar token no login do parceiro; FCM topic `restaurant_<id>`; subscribe no `_init` do dashboard.

### [BUG-PT-008] `restaurantMarkReady` — não verifica se status é `preparing` antes de avançar
**Ficheiro:** `lib/stores/order_store.dart:1186-1198`
**Sintoma:** A doc do CLAUDE.md descreve a transição `preparing → callingDriver`. Mas `restaurantMarkReady` aceita ser chamado em qualquer status (apenas filtra `serviceType != restaurant`). Se a UI tiver bug e o botão aparecer em `created`, marca `callingDriver` saltando o `preparing` → drivers chamados antes de a comida estar pronta. Igual para `restaurantAcceptOrder` (linha 1168).
**Fix:** `if (order.status != OrderStatus.preparing) return false;` em `restaurantMarkReady`. Análogo em `restaurantAcceptOrder` (`!= OrderStatus.created`).

### [BUG-PT-009] `partner_hours_screen.dart` — sem validação de `close > open`
**Ficheiro:** `lib/screens/partner_hours_screen.dart` (`_pickTime`, linha ~43)
**Sintoma:** O parceiro pode definir abertura 22:00 e fecho 09:00. O `BusinessHours.isOpenAt` (testado nos restaurantes públicos) provavelmente fica sempre fechado ou sempre aberto consoante a impl. Não há validação UI nem no save.
**Fix:** Validar `close > open` (ou suportar overnight com flag explícita "fecha no dia seguinte"); mostrar erro inline.

### [BUG-PT-010] `partner_dashboard_screen.dart` — `onCallDriver` chama `restaurantMarkReady` em vez de existir botão dedicado "Pedido pronto"
**Ficheiro:** `lib/screens/partner_dashboard_screen.dart` (`_OrdersSection`)
**Sintoma:** O nome do callback é `onCallDriver` mas a ação interna é `restaurantMarkReady`. Confunde semântica: o parceiro carrega "Chamar estafeta" mas tem realmente de carregar quando A COMIDA ESTÁ PRONTA. Em iFood / Uber Eats o fluxo é "Pedido aceite → Em preparação → Pronto para recolha", e o estafeta é chamado automaticamente pela plataforma.
**Fix:** Renomear UI para "Marcar como pronto"; deixar o `OrderStore` decidir o dispatch internamente.

---

## 🟡 BUGS MÉDIOS

### [BUG-PT-011] `partner_earnings_screen.dart:25-32` — cálculo de revenue ignora descontos / promoções
`_partnerRevenue` faz `subtotal - commission` mas não desconta `discount` se houver promoção paga pelo parceiro. Em iFood, o parceiro vê "ganho líquido" e "descontos da casa" separados.

### [BUG-PT-012] `partner_earnings_screen.dart` — sem export CSV / Excel / PDF
Concorrentes permitem exportar relatório fiscal mensal.

### [BUG-PT-013] `partner_products_screen.dart` — sem pesquisa, sem filtro por categoria, sem ordenação
Restaurante com 200+ produtos fica ingerível. Glovo Partner tem search-as-you-type.

### [BUG-PT-014] `partner_products_screen.dart` — sem **bulk actions** (desativar todos da categoria, mudar preço em lote)
Caso de uso: rotura de stock de todos os hambúrgueres → tem de desativar 1 a 1.

### [BUG-PT-015] `restaurant_store.dart` — `deletePartnerProduct` é **hard delete**
Risco: parceiro apaga produto popular por engano e não há undo. Concorrentes fazem soft delete (`is_archived`) com 30 dias de retenção.

### [BUG-PT-016] `partner_dashboard_screen.dart` — toggle online/offline não tem confirmação
Um clique acidental e o restaurante fica offline em hora de pico. Concorrentes mostram modal "Tem a certeza? Vai parar de receber pedidos durante X".

### [BUG-PT-017] `register_partner_screen.dart` — sem upload real de foto, depende de URL
Pesquisa não mostra `image_picker` no register_partner; o `MandatoryPhotoPicker` existe mas é usado só para entregas. Parceiro tem de copiar/colar URL.

### [BUG-PT-018] `auth_store.dart:851` — `loginPartner` (sync) não verifica `bora_role` no Supabase
Apenas a versão `loginPartnerAsync` verifica role. Um cliente pode tecnicamente fazer login no ecrã de parceiro se já estiver em `_partnersByEmail` (não acontece em prática mas a defesa é fraca).

### [BUG-PT-019] `partner_hours_screen.dart` — sem feriados / horário especial
Concorrentes têm "Fechado no Natal", "Horário especial em 25 Abril".

### [BUG-PT-020] `partner_dashboard_screen.dart` — sem secção "Pedidos rejeitados / cancelados" recentes
Parceiro perde visibilidade do que correu mal.

### [BUG-PT-021] `add_product_screen.dart` — sem suporte de variantes (S/M/L, sabores) na UI do parceiro
A tabela `product_variants` existe e é lida no cliente, mas o parceiro não tem como criar/editar variantes. Concorrentes têm.

### [BUG-PT-022] `partner_dashboard_screen.dart` — `_OrdersSection` provavelmente sem agrupamento por estado
Em pico, lista mistura "novos / em preparação / a aguardar estafeta" — difícil priorizar.

### [BUG-PT-023] `partner_earnings_screen.dart` — gráfico só tem `today / week / month`, sem range custom
iFood Gestor de Pedidos permite escolher datas arbitrárias.

---

## 🟢 BUGS BAIXOS

### [BUG-PT-024] `partner_login_screen.dart` — sem "lembrar email" / persistência leve
### [BUG-PT-025] `partner_dashboard_screen.dart` — sem badge numérico na tab "Pedidos"
### [BUG-PT-026] `partner_products_screen.dart` — fotos não têm `loading=lazy` / placeholder shimmer
### [BUG-PT-027] `partner_hours_screen.dart` — `setState` chama `_pickTime` async sem `if (!mounted) return`
### [BUG-PT-028] `register_partner_screen.dart` — sem validação NIF (Portugal)
### [BUG-PT-029] `partner_earnings_screen.dart` — sem comparação vs período anterior ("+12% vs semana passada")

---

## 🔴 MELHORIAS CRÍTICAS

### [MEL-PT-001] Som persistente + vibração + push notification quando chega pedido
Bloqueante. Já detalhado em [BUG-PT-006] e [BUG-PT-007]. **Sem isto, a app não é viável em ambiente real**.

### [MEL-PT-002] Tempo de preparação configurável por pedido
iFood / Uber Eats permitem o parceiro carregar "+5min", "+10min" se a cozinha está em pico, e o cliente vê ETA real.

### [MEL-PT-003] Recusa com motivo (esgotado / cozinha fechada / muito longe)
Hoje `restaurantRejectOrder` rejeita sem capturar `rejection_reason`. Cliente recebe "rejeitado" sem contexto.

### [MEL-PT-004] Modo "Pausar pedidos por X minutos"
Pico súbito? Parceiro pausa 15min. Concorrentes têm. Bora não.

### [MEL-PT-005] Onboarding completo do parceiro com KYC
Hoje `register_partner_screen` cria restaurante imediatamente. Concorrentes têm flow de aprovação: enviar alvará, NIF, IBAN, foto da fachada → admin aprova → vai a produção. `admin_partners_screen.dart` existe (4.6KB) mas suspeito que está limitado.

---

## 🟡 MELHORIAS MÉDIAS

### [MEL-PT-006] Chat parceiro ↔ cliente (via plataforma)
Para ajustes de pedido (sem coentros, etc.). Concorrentes têm.

### [MEL-PT-007] Chat parceiro ↔ estafeta
"Pedido na entrada lateral" — fundamental.

### [MEL-PT-008] Impressão térmica de pedidos (Bluetooth)
iFood e Uber Eats integram impressoras Bluetooth. Cozinha usa papel.

### [MEL-PT-009] Inventário / stock por produto
Marcar "esgotado" automático quando stock = 0.

### [MEL-PT-010] Promoções / cupões geríveis pelo parceiro
"-20% segunda-feira", "Combo 2x1". Hoje só admin pode (e mesmo isso é duvidoso).

### [MEL-PT-011] Reviews dos clientes — responder
A tabela de ratings existe, mas o parceiro não pode responder. Concorrentes permitem.

### [MEL-PT-012] Métricas operacionais: tempo médio de aceitação, taxa de rejeição, tempo de preparação
KPIs que os concorrentes mostram para penalizar/recompensar parceiros.

### [MEL-PT-013] Catálogo agrupado por menus / secções
Café da manhã / almoço / jantar com horários distintos.

### [MEL-PT-014] Ações em massa nos produtos (CSV import/export)
Restaurantes grandes precisam disto.

### [MEL-PT-015] Multi-loja (mesmo dono, várias unidades)
Concorrentes suportam: 1 conta = N restaurantes. Hoje 1 email = 1 restaurante.

---

## 🟢 MELHORIAS BAIXAS

### [MEL-PT-016] Dark mode no painel parceiro
### [MEL-PT-017] Tutorial interactivo na primeira utilização
### [MEL-PT-018] Atalhos de teclado (versão tablet)
### [MEL-PT-019] Widget de "Top 5 produtos do mês"
### [MEL-PT-020] Notificação push de pagamentos recebidos / payouts semanais

---

## Pontuação vs concorrentes

| Categoria                          | Bora | Uber Eats Manager | Glovo Partner | iFood Gestor |
|------------------------------------|------|-------------------|---------------|--------------|
| Login / autenticação               |  5/10 | 9/10 | 9/10 | 9/10 |
| Recepção de pedido (som/push)      |  2/10 | 10/10 | 10/10 | 10/10 |
| Gestão de menu                     |  5/10 | 9/10 | 9/10 | 10/10 |
| Histórico / relatórios             |  5/10 | 9/10 | 8/10 | 10/10 |
| Horários de funcionamento          |  6/10 | 9/10 | 9/10 | 9/10 |
| Comunicação com cliente / estafeta |  0/10 | 8/10 | 8/10 | 9/10 |
| KYC / onboarding                   |  3/10 | 9/10 | 9/10 | 9/10 |
| Operacional (pausa, preparação)    |  2/10 | 9/10 | 9/10 | 10/10 |
| Multi-loja                         |  0/10 | 9/10 | 9/10 | 9/10 |
| **TOTAL**                          | **28/100** | **89/100** | **89/100** | **94/100** |

---

## Recomendação — top 5 a atacar primeiro

1. **[BUG-PT-006] + [BUG-PT-007] — Som + push notification de novo pedido**
   Sem isto, parceiros não usam a app. Implementação: ~1 dia (já existe `SoundService` no driver).

2. **[BUG-PT-002] + [BUG-PT-003] — Tornar `registerPartner` síncrono com Supabase + UUID + foto obrigatória + `via.placeholder.com` → asset local**
   Bloqueador para qualquer onboarding em produção. ~1 dia.

3. **[BUG-PT-001] — Botão "Esqueceu a palavra-passe?" no `partner_login_screen`**
   Trivial (10 linhas), mas crítico para SLA.

4. **[BUG-PT-005] — Tornar mutações de produtos (`updatePartnerProduct`, `deletePartnerProduct`, `addPartnerProduct`) `await` com rollback e feedback de erro**
   Risco de venda a preço errado. ~0.5 dia.

5. **[MEL-PT-003] + [BUG-PT-016] — Recusa com motivo + confirmação no toggle online/offline**
   Toques pequenos com grande impacto na qualidade percebida. ~0.5 dia.

> **Trabalho total estimado para fechar os 5 críticos: 3-4 dias.**
> Após isso, o painel do parceiro passa de **28/100** para ~**55/100** — ainda longe dos concorrentes, mas operacionalmente viável.
