---
tipo: handoff
origem: claude-code (missão CEO-AI, sem agente dedicado invocado)
data: 2026-07-21
para: bibliotecario-cerebro
---

# Handoff — perfil rico do parceiro de Serviços (about_text/gallery_urls/social_*)

**Facto novo (estado: atual):** `service_providers` ganhou 4 colunas (via MCP,
antes desta tarefa): `about_text` (text), `gallery_urls` (jsonb, default `[]`),
`social_instagram` (text), `social_facebook` (text). O modelo Dart
`ServiceProviderModel` (`lib/models/service_provider_model.dart`) agora mapeia
as 4. Válido para **qualquer** prestador da vertical Serviços, não só a
Ouro e Prata.

**Padrão reutilizável:** upload de galeria usa a Edge Function genérica
`upload-restaurant-asset` (já existia para logo/hero) com
`kind: 'gallery/photo'` → produz `{providerId}/gallery/photo-{ts}.ext` no
bucket público `restaurant-assets`. Nenhuma Edge Function nova foi precisa.

**Bug corrigido:** `StaffAvatar` (`lib/widgets/services/staff_avatar.dart`)
não tinha fallback quando a foto do profissional falhava a carregar (ficava
um círculo liso). Agora cai para o gradiente+iniciais via
`onBackgroundImageError`. Candidato a entrada em
`procedural/licoes/` (categoria UI/Flutter): "avatar de rede sem
`onBackgroundImageError` = fallback mudo em erro de rede".

**Pendências reportadas (não corrigidas, fora do escopo):**
- `register_partner_screen.dart`: `_formKey` nunca lido + 4 imports não
  usados — possível validação de formulário silenciosamente quebrada.
- `refund_choice_dialog.dart:65`: `_tokenValueCentsX100` nunca lido — zona
  🔴 tokens/refund, só reportado.

Relatório completo em
`.claude/.ai/reports/relatorio-perfil-parceiro-servicos-2026-07-21.md`.
