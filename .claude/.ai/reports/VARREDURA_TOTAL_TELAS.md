# VARREDURA TOTAL TELA-A-TELA — Relatório vivo

> Missão noturna 2026-08-16/17 · "O código é o olho" · 4 papéis · Matriz 🔴 bug real / 🟡 abaixo do padrão / 🟢 ok
> Inventário técnico completo: `VARREDURA_TOTAL_TELAS.inventario.md` (414 ficheiros, 196 ecrãs, BFS de alcançabilidade)
> Base funcional: mapas de fluxos do Córtex (35 fluxos, 2026-07-10) — atualizados no fecho.

## Tabela mestre de áreas (F0)

| Área | Raiz | Ecrãs (aprox.) | Referência de comparação |
|---|---|---|---|
| F1 Motorista TVDE | `TvdeDriverHomeScreen` (root p/ `carPassengers`) | tvde_offer, tvde_ride_active, tvde_driver_rate, ganhos, planos, histórico | Uber Driver, Bolt Driver, 99 |
| F2 Cliente TVDE | tile Bora Motorista → `TvdeRequestRideScreen` | request, tracking, plans, unlock, histórico | Uber, Bolt, 99 |
| F3 Cliente Delivery | `ClientMainScreen` (4 tabs) | home, restaurantes, mercados, produto, carrinho, checkout, tracking, histórico, avaliação | Glovo, Uber Eats, iFood |
| F4 Estafeta Delivery | `DriverHomeScreen` | home/mapa, oferta, compra em loja, talão, entrega, ganhos | Uber Driver, Glovo courier |
| F5 Marcações/Reservas/Limpeza/Favores | tiles do home cliente + hubs parceiro | wizard limpeza, availability reservas, appointments, errand form | Fresha/Booksy, TheFork, Helpling |
| F6 Parceiro + Admin | `PartnerEntryScreen` / rotas `/admin` | dashboard, produtos, horários, ganhos; 82 ecrãs admin | iFood parceiro, painéis internos |

Caminho de clique de cada ecrã: secção "Árvore de alcançabilidade" do inventário (BFS caminho mais curto).

## Matriz por área (preenchida ao fechar cada área)

### F1 — MOTORISTA/TVDE
_(em curso)_

### F2 — CLIENTE TVDE
_(pendente)_

### F3 — CLIENTE DELIVERY
_(pendente)_

### F4 — ESTAFETA DELIVERY
_(pendente)_

### F5 — MARCAÇÕES + RESERVAS + LIMPEZA + FAVORES
_(pendente)_

### F6 — PARCEIRO + ADMIN
_(pendente)_

### F-OLHO — automação de visão
_(pendente)_

## Propostas grandes (fora do perímetro — para Claude.ai/Danilo)
_(acumulado ao longo da varredura)_

## Digest Hermes (8 linhas — preenchido no F7)
_(pendente)_
