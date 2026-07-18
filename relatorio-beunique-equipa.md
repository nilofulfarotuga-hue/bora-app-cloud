# Relatório — BeUnique Beauty and Academy: fotos + feature "Equipa"

**Data:** 2026-07-19 · **Branch:** `autonomous-night-2026-04-29`
**Provider:** `BeUnique Beauty and Academy` (`service_providers.id = 192c7d0b-b8ef-4d52-bac3-307895fbbf8e`, category=`beauty`)
**Squad (CEO-AI):** parceiro-servicos + flutter-ui + admin · **Não toca dinheiro** (Lista Vermelha).

---

## PARTE 1 — Imagens (obtidas, processadas e INSTALADAS ✅)

### Fonte real encontrada (Noona)
A API pública do Noona **expôs as fotos reais** dos profissionais:
`https://api.noona.is/v1/marketplace/companies/beuniquebeauty` → company id `CL9mwu5XHxaNZJaej`
→ `.../companies/CL9mwu5XHxaNZJaej/employees` (foto em `employee.profile.image.image`).
Todas as imagens do Noona vivem em `res.cloudinary.com/timatal-ehf` (públicas, sem login).
Instagram **não** foi tentado (exige login) — conforme instrução.

### O que foi feito
- **Logo + Capa** do salão: baixados do Cloudinary, re-processados (logo ≤800px; capa ≤1280×720)
  e **re-hospedados no nosso bucket público** `restaurant-assets` via Edge Function
  `upload-restaurant-asset`. Deixámos de depender do hotlink do Noona.
- **9 profissionais**: 7 com **foto real** do Noona (recorte quadrado centrado 512×512, JPG q80);
  2 sem foto no Noona → **avatar de iniciais elegante** gerado por código (gradiente do design
  system, iniciais brancas, 512×512).
- Todos os 11 uploads devolveram `public_url` (registados abaixo) e servem **HTTP 200** (verificado).
- **SQL aplicado via MCP** (não é dinheiro): `service_providers.photo_url/hero_image_url` +
  `staff_members.photo_url` das 9. Confirmado por `SELECT` (as 9 ficaram preenchidas).

### Foto real vs avatar de iniciais

| # | Profissional (DB) | Origem | Nome no Noona |
|---|---|---|---|
| 1 | Camila Pissarra | ✅ foto real | Camila Pissarra - Cabeleireira Master Top |
| 2 | Amalia Cavalcante | ✅ foto real | Amália Cavalcante - Cabeleireira |
| 3 | Bruna Frias | ✅ foto real | Bruna Frias - Designer de sobrancelhas |
| 4 | Priscila Santana | ✅ foto real | Priscila Santana |
| 5 | Diana | ✅ foto real | Diana João |
| 6 | Jenniffer | ✅ foto real | Jennyffer Sabino |
| 7 | Viviane Torres | ✅ foto real | Viviane Silva |
| 8 | Liliana Elias | 🎨 avatar "LE" | (não é employee bookável no Noona) |
| 9 | Dra. Bianca Melo | 🎨 avatar "BM" | (não é employee bookável no Noona) |

### URLs finais (bucket público `restaurant-assets`)
Base: `https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/restaurant-assets/192c7d0b-b8ef-4d52-bac3-307895fbbf8e/`
- logo → `logo-1784416088189.jpeg` · capa → `hero-1784416088923.jpeg`
- staff 1..9 → `staff-1-1784416090030.jpeg` … `staff-9-1784416096705.jpeg`

O SQL completo (com todas as URLs e `WHERE id=...`) está em **`relatorio-beunique-fotos.sql`**.
Estado: **APLICADO** (não pendente).

---

## PARTE 2 — Feature "Equipa" (Flutter)

### Auditoria
- **Cliente / detalhe do prestador** (`provider_detail_screen.dart`): mostrava hero, nome, rating,
  morada, descrição e Serviços — **não** mostrava a equipa. → adicionado.
- **Cliente / fluxo de marcação** (`booking_flow_screen.dart`, passo "Escolher profissional"): já
  mostrava foto/inicial. → unificado ao novo widget (fallback bonito).
- **Admin** (`admin_service_provider_detail_screen.dart`): 4 abas (Dados/Horários/Serviços/Estado)
  — **sem** gestão de equipa. → adicionada aba "Equipe".
- **Parceiro** (`partner_manage_staff_screen.dart`): já tinha CRUD de staff com upload de foto.

### O que foi construído
1. **Widget partilhado** `lib/widgets/services/staff_avatar.dart` — foto redonda (`photo_url`) ou,
   em fallback, iniciais sobre gradiente do design system (determinístico por nome). Fonte única
   de verdade para cliente + admin.
2. **Cliente (PT-PT)** — secção **"A nossa equipa"** no detalhe do prestador: lista horizontal de
   cartões (foto/avatar, nome, função, até 2 chips de especialidades). Só `is_active=true`, por
   `sort_order`. Fluxo de marcação passa a usar o mesmo `StaffAvatar`.
3. **Admin (PT-BR)** — 5.ª aba **"Equipe"** em `admin_service_provider_detail_screen.dart`:
   listar (activos+inactivos), **adicionar/editar/desactivar/apagar/reordenar** profissionais e
   **upload/troca de foto** por profissional (SafeImagePicker → Edge Function
   `upload-restaurant-asset` kind=`staff_photo` → `staff_members.photo_url`), reutilizando o padrão
   já usado para logo/capa. RLS confirmada (`sm_write` permite `is_admin()`). Apagar com marcações
   no histórico → desactiva (soft delete) em vez de apagar.

### Qualidade
- `flutter analyze` nos 4 ficheiros tocados: **No issues found!**
- Design system respeitado (verde #16A34A, laranja só nos CTAs existentes; sem 2.º laranja novo).
- Nada tocado em restaurantes, pagamentos ou na Edge Function.

---

## Ficheiros tocados
**Novos:** `lib/widgets/services/staff_avatar.dart` · `tools/beunique/build_photos.py` ·
`tools/beunique/.gitignore` · `relatorio-beunique-fotos.sql` · `relatorio-beunique-equipa.md`
**Editados:** `lib/screens/client/services/provider_detail_screen.dart` ·
`lib/screens/client/services/booking_flow_screen.dart` ·
`lib/screens/admin/admin_service_provider_detail_screen.dart`

## O que falta
- Nada bloqueante. As imagens já estão em produção (DB + bucket). O app mostra a equipa assim que
  a próxima build do CI sair (não mexemos no versionCode — CI trata).
- (Opcional/futuro) reordenar/gerir equipa **no lado do parceiro** já existia; a paridade admin
  ficou agora coberta.
