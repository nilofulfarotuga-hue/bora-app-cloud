# 🎯 /goal — Paridade Admin 360° (Fase 5, o primeiro loop)

**slug:** `paridade-admin-360` · **tabela:** `autonomy_goals` (+ `autonomy_backlog_items`)

## Definição
> Para **cada domínio SEM gestão no admin** (auditoria 2026-07-01), construir o ecrã de gestão
> (**ver/editar/criar/banir/configurar/exportar/auditar**), **um de cada vez**, **Juiz-gated**,
> até a paridade admin chegar a **20/20**.

## Done mensurável (o placar)
- **Métrica:** nº de domínios com paridade admin completa. **Alvo = 20. Início = 1/20** (só
  Parceiros restaurante/loja). Fonte: auditoria de paridade 360° (`episodica/auditoria-360.md`).
- Cada `autonomy_backlog_items.estado='feito'` incrementa `autonomy_goals.metrica_atual` (via
  `maestro_link_suggestion`). A Central mostra a barra de progresso ao vivo.

## Tetos (o 1º run é LENTO e PEQUENO)
- `itens_por_ciclo = 1` · `teto_max_turns = 40` · `teto_orcamento_tokens = 2.000.000` · `cadencia_min = 60`.
- **Auto-mode só para 🟢 N1** — e só se o **dial** permitir (começa cauteloso).

## Backlog (19 itens — 6🟢 / 4🟡 / 9🔴)
- **🟢 verde (N1, auto-elegível):** Visualizador de auditoria · Exportar CSV · Filtros de descoberta ·
  Gestão Serviços/agendamentos · Config Reservas Pro · Gestão de Favores.
- **🟡 amarela (N2, 1 toque):** Revisão KYC estafeta · Revisão KYC/docs TVDE · Bucket driver-documents
  privado · GDPR export.
- **🔴 vermelha (N3, só propõe — dinheiro):** Zonas de entrega · Taxa por zona · Pedido mínimo ·
  Surge · Cupões/promo · Config tokens · Reclamações+refund · Idempotency refund · Settlements override.

## Como o loop corre este goal
Ver `maestro-autonomia.md` (o ciclo) e `ENVELOPE_SEGURANCA.md` (as 5 paredes). Ordem: itens 🟢
primeiro (ordem baixa) para o teto-baixo do arranque; 🔴 no fim (só propostas).
