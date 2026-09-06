---
id: mapa-de-fluxos
tipo: semantica
origem: [missão noturna 2026-07-09 Fase 1 — varredura fan-out do código (4 agentes) + business_rules + backend-map]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: verificado-no-codigo
---

# 🗺️ Mapa de Fluxos — Olho do Bora (índice)

> TODOS os fluxos testáveis da app, por papel, com pré-condições, passos numerados
> (ecrã → ação → resultado), variações de pagamento e marca `[2-DEVICES]` quando envolve
> cliente + estafeta/motorista. Base para os testes E2E Maestro (`.claude/testes-e2e/`).

## Sub-ficheiros (nenhum > ~20 KB)
| Ficheiro | Conteúdo |
|---|---|
| `mapa-de-fluxos-cliente.md` | 11 fluxos: registo/login, delivery parceiro, storeShopping V2, mercados, favores v3, reservas, limpeza T0–T4, TVDE cliente, cancelamento E1–E4, wallet/tokens, chat |
| `mapa-de-fluxos-estafeta.md` | 11 fluxos: candidatura, login+online gate, oferta (som/overlay), entrega+PIN, mapa, ganhos, multi-papel, TVDE motorista, planos TVDE, batching |
| `mapa-de-fluxos-parceiro-transversal.md` | 13 fluxos: onboarding, login, aceitar→pronto, rejeitar, menu CRUD, reservas/chegada, settlement + push FG/BG/morto, deep links, PT-PT, offline, sessão |
| `mapa-de-fluxos-antiregressao.md` | 24 checks anti-regressão (1 por bug `estado: atual` de `bugs-resolvidos.md`) + tabela backend por fluxo (RPCs/EFs/tabelas + validação read-only) |

## Convenções de teste (valem para todos os fluxos)
- **Navegação raiz = widget-rebuild** (`_RootNavigator` observa `SessionStore`/`AuthStore`);
  sub-ecrãs usam `Navigator.push` normal. Login/troca de papel NUNCA usa pushReplacement.
- **Selectors Maestro:** `Semantics(identifier:)` = **0 ocorrências em `lib/`** (2026-07-10) →
  os flows YAML usam TEXTO dos labels (PT-PT, exatos, listados por fluxo). A Fase 2 da missão
  adiciona identifiers `btn_*` nos fluxos críticos (commit separado, só UI).
- **Contas de teste:** cliente demo `cliente@bora.app`/`123456` (pré-preenchida em kDebugMode);
  driver debug `driver@bora.app`/`123456`. Pedidos de teste marcados `[E2E-TESTE]`.
- **Isolamento de dispatch (crítico):** o dispatch-engine NÃO tem filtro de zona/raio duro
  (10 km é preferência soft). Um pedido de teste chega deterministicamente ao estafeta de
  teste sse ele for **o único elegível**: `is_online=true` (e todos os outros offline),
  lat/lng perto do pickup, `vehicle_type` compatível, <3 ativos, fora de `tried_driver_ids`.
  Antes de cada ciclo E2E: verificar (read-only) que nenhum driver real está online.
- **Pagamento em testes automáticos = SEMPRE dinheiro (cash, máx €40).** Cartão/MB Way:
  navegar até ao ecrã de pagamento e validar UI, NUNCA confirmar cobrança real.
- **Precedência:** business_rules vence nos NÚMEROS; DNA na filosofia. Números citados nos
  sub-ficheiros foram confirmados no código/BR em 2026-07-10.

## Discrepâncias detetadas na varredura (2026-07-10)
1. **No-show entrega €3.50 NÃO existe no código** — só cancel fees (E1–E4) e no-show TVDE.
   (No-show de RESERVA = €3 retidos, esse existe.)
2. **Reservas:** split real = **€2 parceiro + €1 Bora** (BR §18) — não €0.50/€2.50.
3. **Rejeição de pedido pelo parceiro não captura motivo** (confirmação simples).
4. **Tokens cliente = 3 tokens por €** (`GREATEST(1, ROUND(valor×3))`) — a frase "3% do valor"
   está superada.
5. `send_package_screen.dart` e `map_screen.dart` (cliente) e `ReservationFlowScreen` (legado)
   parecem duplicados/legado com ecrãs novos a coexistir.
