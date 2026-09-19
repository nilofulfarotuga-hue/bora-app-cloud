# Relatório — Admin: Autoridade TOTAL sobre prestadores de Beleza/Serviços

**Data:** 2026-07-18
**Branch:** `autonomous-night-2026-04-29`
**Modo:** Protecção Total · Opus
**Esquadrão:** `parceiro-servicos` + `flutter-ui` + `admin` (via CEO-AI)

## Objetivo

Dar ao painel admin autoridade total sobre a tabela `service_providers`
(vertical Serviços/Beleza), igualando o que já existia para restaurantes.
Antes o admin de beleza só aprovava/rejeitava/ativava. Agora edita dados,
logo, capa, horários, gere serviços/preços e apaga.

## O que foi adicionado

Nova tela **`AdminServiceProviderDetailScreen`** com 4 abas PT-BR, aberta a
partir da lista de prestadores (botão passou de "Ver perfil" → **"Gerir"**).

### Aba 1 — Dados
- Editar e gravar em `service_providers`: **Nome, Endereço, Telefone,
  Descrição, Categoria** (dropdown PT-BR: Barbearia, Salão de Beleza,
  Cabeleireiro, Manicure/Unhas, Estética, Spa, Tatuagem, Outro — a categoria
  atual do prestador é sempre incluída no dropdown mesmo que fora da lista).
- **Logo** — "Trocar/Enviar imagem" via `SafeImagePicker` → Edge Function
  `upload-restaurant-asset` (kind=`logo`, o id do prestador vai no campo
  `restaurantId` = só prefixo da pasta) → `.update({'photo_url': publicUrl})`.
  Preview + "Remover".
- **Capa (banner)** — igual mas kind=`hero` → `hero_image_url`. Preview + "Remover".

### Aba 2 — Horários
- Reutiliza o model `BusinessHours`/`DayHours` (o mesmo dos restaurantes).
- Switch Aberto/Fechado por dia + time-pickers 24h. Grava em
  `service_providers.business_hours` (jsonb mon..sun) via `.update(...)`.

### Aba 3 — Serviços & Preços (CRUD de `provider_services`)
- Lista **todos** os serviços (activos e inactivos), ordenados por `sort_order`.
- **Adicionar** (nome, descrição, duração min, preço em €). Preço mostrado
  em € ao admin, gravado em `price_cents` (×100). Validação preço > 0 e
  duração > 0. `id` gerado pelo Postgres (`gen_random_uuid()`).
- **Editar**, **Activar/Desactivar** (`is_active`), **Reordenar** (subir/descer
  → reatribui `sort_order` sequencial), **Apagar**.
- Apagar serviço com marcações (`appointments.service_id`, FK NO ACTION):
  deteta antes e **desactiva** em vez de apagar (preserva histórico) + avisa.

### Aba 4 — Estado / Ações
- Estado da aprovação + motivo de rejeição.
- Toggles **Online/Offline** (`is_online`) e **Activo no admin** (`is_active_admin`).
- **Aprovar** / **Rejeitar** (RPCs `admin_appointment_provider_approve` /
  `admin_appointment_provider_reject`, já existentes).
- **Apagar prestador** (confirmação dupla). Se houver histórico
  (`appointments` ou `appointment_payouts`, FKs NO ACTION) → **desactiva** em
  vez de apagar + avisa. Sem histórico → DELETE (CASCADE remove
  `provider_services` + `staff_members` automaticamente).

## Ficheiros tocados

| Ficheiro | Ação |
|---|---|
| `lib/screens/admin/admin_service_provider_detail_screen.dart` | **NOVO** — tela de gestão total (4 abas). |
| `lib/screens/admin/admin_service_providers_screen.dart` | Editado — import + botão "Gerir" abre a tela + recarrega ao voltar; removido o dialog read-only `_showProfile` (substituído pela tela completa). |

## Verificações (MCP, DB live `ojykpzwqrtusfeakzrna`)

- **RLS confirmada:** `sp_update` / `sp_delete` / `sp_insert` (service_providers)
  e `ps_write` (provider_services, ALL) permitem `is_admin()` → UPDATE/DELETE/
  INSERT diretos funcionam para o admin.
- **FKs de deleção:** `provider_services` e `staff_members` → CASCADE;
  `appointments.provider_id`, `appointments.service_id`,
  `appointment_payouts.provider_id` → NO ACTION (bloqueiam delete → tratado
  com fallback para desactivar).
- **Colunas** todas confirmadas; `provider_services.id` = `gen_random_uuid()::text`
  (default, não é preciso enviar id no insert).

## Zonas protegidas / dinheiro

- **NÃO** foi tocado o Edge Function `upload-restaurant-asset` (reutilizado tal
  como está).
- **NÃO** foi tocado o fluxo de restaurantes (só espelhado para beleza).
- Editar `provider_services.price_cents` é gestão de catálogo do próprio
  prestador (preço de serviço), análogo aos preços de menu dos restaurantes que
  o admin já edita — **não** é o motor de preços/taxas/comissões da plataforma
  (`pricing_service`), logo **não** é Lista Vermelha.

## Qualidade

- `flutter analyze` nos 2 ficheiros tocados: **No issues found!** (0 erros, 0 warnings, 0 infos).
- Sem tocar `versionCode` (CI faz o build).

## Commit

Apenas os 2 ficheiros do código + este relatório foram staged
(**não** foi feito `git add -A`) para não arrastar alterações concorrentes não
relacionadas presentes no working tree — incluindo uma edição em
`supabase/functions/tvde-payment/index.ts` que mexe em dinheiro e não é minha.

## Checklist — o que o admin agora consegue na Beleza

- [x] Editar nome, endereço, telefone, descrição, categoria
- [x] Trocar / remover **logo**
- [x] Trocar / remover **capa (banner)**
- [x] Editar **horários** (por dia, com abrir/fechar)
- [x] **Adicionar / editar / activar-desactivar / reordenar / apagar** serviços
- [x] Preços em € (gravados em cents), com validação
- [x] Aprovar / rejeitar
- [x] Online/Offline e Activo/Inactivo
- [x] **Apagar** prestador (com proteção de histórico)

## Nota

Assim que instalada, esta tela permite ao Danilo pôr o logo da **Barbearia Ouro
e Prata** (`ouro.prata@bora.app`): Beleza → prestador → **Gerir** → aba Dados →
"Trocar/Enviar imagem" no cartão Logo.
