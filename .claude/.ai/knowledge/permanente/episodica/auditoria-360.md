---
tema: auditoria-360 · escopo: projeto · estado: atual · atualizado: 2026-07-06
id: auditoria-360
tipo: conceito
origem: [audits/AUDITORIA_PARIDADE_360_2026-07-01.md]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# 🔎 Auditoria de Paridade 360° (2026-07-01) — resumo ingerido

> Relatório completo (22 KB): `audits/AUDITORIA_PARIDADE_360_2026-07-01.md` (repo) e cópia no
> Obsidian. Isto é o resumo para prioridades. **Não re-derivar** — ler o relatório para detalhe.

## Os 5 P0 (bloqueadores)
1. **Onboarding TVDE possivelmente PARTIDO** — `driver_signup_screen` força
   `p_vehicle_type:'motorcycle'` (~linha 299) → motorista novo nunca fica `carPassengers`.
   Ver `episodica/bugs-resolvidos.md` (vehicle_type). `estado: atual`
2. **KYC não-bloqueante** (estafeta submete sem carta) + TVDE sem docs próprios + admin não
   revê KYC TVDE (compliance IMT/DL 45/2018). `estado: atual`
3. **Prova de entrega valida PIN client-side** (`driver_map_screen.dart:1148`) — risco de fraude;
   devia ser RPC server-side. `estado: atual`
4. **3 buckets públicos com listing** (`avatars`, `product-images`, `restaurant-assets`) —
   confirmar que `driver-documents` é privado. `estado: atual`
   ↳ **[2026-07-06] escrita anónima em `avatars`:** policies `{authenticated, anon}` sem check de
   pasta → qualquer portador da anon key pode upload/update/delete de QUALQUER avatar. PROPOSE-ONLY,
   Danilo decide. Ver `procedural/licoes/licao-storage-policy-auth-users.md`. `estado: atual`
5. **Zonas de entrega / taxa por zona / pedido mínimo / surge INEXISTENTES** (backend + admin).
   P0 para escalar; adiável enquanto for só Guarda. `estado: atual`

## Placar de paridade admin
- Só **1 de 20 domínios** com paridade completa (~5%) — Parceiros restaurante/loja.
- **Verbo mais fraco: EXPORTAR** (2/20). Depois CRIAR (~5) e CONFIGURAR (~4).
- Cobertura zero: Zonas/taxas/surge (0/7).

## Estado por superfície (1 linha)
- **Backend:** maduro (~120 tabelas, 50 edge fns, ~330 RPCs, 72 triggers, RLS em tudo). Gaps: refund idempotency, zonas, RLS não-otimizado à escala.
- **Cliente:** verticais completas; faltam reorder-comida, cupão no checkout, agendar entrega.
- **Estafeta/TVDE:** isolamento TVDE sólido; não vê/saca ganhos reais (só tokens); KYC frágil.
- **Parceiro:** comida completo (Reservas Pro 8 ecrãs); serviços assimétrico (sem pausar/horário/chat).
- **Admin:** cobertura larga mas EXPORTAR/CRIAR/CONFIGURAR em falta; `admin_approve_driver` duplicado.

## Bug fora de escopo
`admin_approve_driver` **duplicado** no schema (overload ambíguo PostgREST). `estado: atual`
