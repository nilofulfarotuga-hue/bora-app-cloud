# AUDITORIA DE PARIDADE — Categoria LIMPEZA (2026-07-05)

> FASE 0 da missão "auditoria de paridade + correção". Comparação da vertical
> Limpeza com delivery, TVDE e marcações. Tabela gerada ANTES de escrever
> código de correção. A coluna **Estado final** é preenchida no fecho.

---

## A. COMUNICAÇÃO

| Capacidade | Referência | Limpeza tinha? | Estado final |
|---|---|---|---|
| Chat bidirecional cliente↔profissional | delivery `messages` / TVDE `tvde_messages` | ❌ FALTA | ✅ FEITO (`cleaning_messages` + RLS, `a374f13`/`4233d26`) |
| Botão de chat com badge não-lidas + preview | `ChatBubbleButton` (delivery) | ❌ FALTA | ✅ FEITO (`CleaningChatButton`, badge 9+ + preview) |
| Push de mensagem nova (2 lados) | trigger + notify-chat-message / TVDE | ❌ FALTA | ✅ FEITO (trigger `_cleaning_chat_push`) |
| Botão LIGAR (tel:) nos 2 lados | TVDE E2 (`launchUrl('tel:…')`) | ❌ FALTA | ✅ FEITO (cliente + profissional) |
| Admin vê conversas (read-only + audit) | `admin_list_order_messages` + viewer | ❌ FALTA | ✅ FEITO (`admin_list_cleaning_messages` + viewer, `14a7f78`) |

**Decisão de arquitetura (desvio justificado do enunciado):** a missão pedia
reutilizar "tabelas `messages`/`conversations`". A auditoria mostrou que
(1) **não existe** tabela `conversations` — o chat do delivery é uma tabela
plana `messages` presa a `orders` (TEXT id, RLS `messages_insert_participant`
faz JOIN a `orders`, e a Edge Fn `notify-chat-message` resolve destinatários
APENAS a partir de `orders`); (2) o precedente mais recente e limpo — o
próprio **TVDE E1 citado pela missão** — usa **tabela dedicada**
(`tvde_messages` com scoping por ride + `read` + RPC mark_read). Encaixar a
Limpeza em `messages` obrigaria a mexer na RLS do delivery, na Edge Fn de
push do delivery e no `chat_mark_read` — risco em zona estável. Segue-se o
padrão TVDE E1: tabela `cleaning_messages` (booking_id UUID), mesma UX.
O `ChatBubbleButton` existente é acoplado a `OrderModel`; replica-se o padrão
visual (badge vermelho 9+, preview) num botão próprio da Limpeza.

## B. PERFIS E IDENTIDADE

| Capacidade | Referência | Limpeza tinha? | Estado final |
|---|---|---|---|
| Foto de perfil da profissional (upload) | bucket `avatars` `$uid/avatar.jpg` (profile_screen) | ⚠️ PARCIAL — `photo_url` existia e era exibido, mas SEM upload no cadastro | ✅ FEITO (upload obrigatório no cadastro, `472ff58`) |
| Card da profissional p/ cliente (foto/nome/★/nº limpezas/❤) | card motorista TVDE D1 | ✅ TEM (wizard passo 3 + tracking) — faltava telefone/LIGAR | ✅ FEITO (LIGAR + ★/nº limpezas no card) |
| Foto/nome do cliente p/ profissional | TVDE D2 | ❌ FALTA no serviço ativo. Nota: na OFERTA o TVDE **não mostra** identidade do cliente (privacidade pré-aceitação) — a Limpeza segue o mesmo padrão: identidade só depois de aceitar | ✅ FEITO (card na agenda via `cleaning_booking_client_public`) |
| Upload de documentos KYC no cadastro | `driver-documents`/`restaurant-documents` (privados) + `PrivateBucketImage` no admin | ❌ FALTA (`docs` jsonb existia vazio; aprovação era "às cegas") | ✅ FEITO (bucket `cleaner-documents` + review no admin) |

## C. PARIDADE HOME/PERFIL DA PROFISSIONAL (vs estafeta/TVDE F1)

| Item do estafeta | Limpeza tinha? | Estado final |
|---|---|---|
| Suporte (BoraSupportSheet: IA + WhatsApp + Email) | ❌ FALTA | ✅ FEITO (atalho no painel, `472ff58`) |
| Histórico de serviços com detalhe | ❌ FALTA (ganhos só tinha somas) | ✅ FEITO (`CleanerHistoryScreen`, `472ff58`) |
| Avaliação média recebida | ✅ TEM (painel + ganhos) | ✅ |
| Perfil editável (foto/bio/raio/zona) | ⚠️ PARCIAL (RPC existia; sem UI além do switch ativa/pausa) | ⏳ PENDENTE — ver secção H (edição de foto/bio pós-registo fica para v2; foto entra no cadastro) |
| Toggle online/offline | ✅ TEM (switch ativa/pausa) | ✅ |
| Ganhos | ✅ TEM | ✅ |

**Não adaptados (justificação, sem buraco silencioso):**
- *Chip de tokens*: a Limpeza não atribui tokens (ver E) — chip ficaria a zero.
- *Permissões de pedidos* (`DriverPermissionsScreen`): específico dos tipos de
  serviço de entrega/veículo — não se aplica a limpezas.
- *Modo teste da home do estafeta*: ferramenta interna do fluxo delivery.
- *Saldo/wallet*: profissional recebe por fora (cash/valores libertados);
  o acerto do caixa é gerido no admin. Wallet v2 se a procura justificar.
- *Documentos pós-registo* (ecrã de docs do driver): na Limpeza os docs
  entram na candidatura (novo, ver B); gestão posterior fica para v2.

## D. AVALIAÇÃO BIDIRECIONAL

| Sentido | Backend | UI | Estado final |
|---|---|---|---|
| Cliente → profissional | ✅ (`cleaning_submit_rating` → `subject_type='cleaner'`) | ✅ TEM (tracking) | ✅ |
| Profissional → cliente | ✅ (mesma RPC → `'cleaning_client'`) | ❌ FALTAVA UI | ✅ FEITO (diálogo "Avaliar o cliente" na agenda, `4233d26`) |

## E. OUTRAS PARIDADES

| Item | Veredito da auditoria | Estado final |
|---|---|---|
| Tokens (cliente ROUND(€×3) mín 1; profissional por serviço) | ❌ Limpeza não atribui — MAS **TVDE e marcações também não** (só o delivery atribui, via `trg_award_tokens_on_delivery`). Atribuir na Limpeza mexe em `bora_tokens` = 🔴 LISTA VERMELHA → **proposta preparada, NÃO aplicada** (`supabase/PROPOSTA_20260705_cleaning_tokens.sql`) | ⚠️ proposta |
| Push em TODAS as transições | ✅ TEM (oferta, aceite, a caminho, iniciada, concluída, confirmada, cancelamentos, reatribuição, no-show, lembretes 24h/2h) | ✅ |
| Cancelamento: janelas + contadores dos 2 lados | ✅ TEM (server-side; cliente 24h/2h; profissional `cleaner_cancel_events` 3/30d → suspensão) | ✅ |
| Banner "Pagar agora" p/ unpaid | ✅ TEM (tracking) | ✅ |
| Deep-link do push | Os outros verticais TAMBÉM não fazem deep-link de estado (só oferta TVDE, broadcast e chat do delivery). Limpeza fica **consistente**: push abre a app. Registado; deep-link global é melhoria transversal futura | ✅ consistente |

## F. PAGAMENTO (FASE 1 — decisão do Danilo, executada)

Cartão deixou de usar retenção manual (hold expirava em ~7 dias) e passou a
**cobrar na reserva**, igual ao MB Way; cancelamento estorna automaticamente
o que exceder a taxa (`reverse`, mecânica já existente). `cleaning-checkout`
**v2 redeployada** (ACTIVE). Ação `capture` mantida só para holds legados.
Dinheiro inalterado. ✅ FEITO (`912ce6d`).

## G. BUGS ENCONTRADOS FORA DO SCOPE (a reportar, não corrigidos aqui salvo indicação)

1. **`business_rules.md` desatualizado (tokens do cliente):** doc diz "3% do
   valor"; o código (canónico desde Batch D) faz `GREATEST(1, ROUND(price×3))`
   = 3 tokens por €. E "+50 stacking" no doc vs código `+50 = loja parceira`.
2. **`admin_ratings_screen`** não tinha filtros para `tvde_passenger`,
   `cleaner`, `cleaning_client` (avaliações existiam na BD mas invisíveis por
   filtro) → **corrigido na FASE 3** (adicionados os 3).
3. **`notify-client` ignora `type`/`kind` do payload** e hardcoda
   `type:'order_status'` no FCM — sem impacto hoje, mas bloqueia deep-link
   futuro por tipo.
4. Edge Fns `upload-driver-document` e `upload-order-photo` estão deployed
   mas **sem fonte local** em `supabase/functions/` (drift repo↔prod).
5. `chat_bubble_button.dart` tem `_myRole` sem uso (warning pré-existente).
6. Colunas de chat (`sender_type`, `conversation_type`, `read`) e a tabela
   `tvde_messages` existem em prod **sem migration no repo** (drift).

## H. O QUE FOI CORRIGIDO / PENDENTE

### ✅ Corrigido nesta sessão (paridade fechada)

**Comunicação (A):**
- Tabela `cleaning_messages` (booking_id UUID) + RLS participantes-only + INSERT
  só em estados ativos (accepted…done) + realtime. RPC
  `cleaning_mark_messages_read`. Trigger `_cleaning_chat_push` (push aos 2 lados).
- `CleaningChatStore` (refcount por booking, badge + preview partilham a
  subscrição), `CleaningChatScreen`, `CleaningChatButton` (badge vermelho 9+).
- Botão de chat + LIGAR (tel:) no tracking do cliente **e** na agenda da
  profissional. Card do cliente para a profissional via
  `cleaning_booking_client_public` (nome/foto/telefone — só depois de aceitar).
- Admin: "Ver conversa" (read-only) em cada limpeza via
  `admin_list_cleaning_messages` (com `log_admin_action`).

**Perfis e KYC (B):**
- `CleanerUploadService`: foto → `avatars` (público); documento → bucket
  privado novo `cleaner-documents` (4 policies own-folder + admin).
- Cadastro passa a **exigir** foto de perfil + documento de identificação.
- Admin vê foto + documentos (signed URL via `PrivateBucketImage`, que passou a
  reconhecer `cleaner-documents` e `restaurant-documents`) **antes** de aprovar.

**Home da profissional (C):** atalho Suporte (`BoraSupportSheet`) + Histórico
de serviços com detalhe (`CleanerHistoryScreen`).

**Avaliação bidirecional (D):** diálogo "Avaliar o cliente" na agenda (a RPC
`cleaning_submit_rating` já suportava o sentido; faltava a UI).

**Pagamento (F / FASE 1):** cartão passa a cobrar na reserva (fim do hold de
7 dias) — `cleaning-checkout` v2 redeployada. Estorno automático via `reverse`.

**Bug fora de scope corrigido (G2):** `admin_ratings_screen` ganhou os filtros
`cleaner`, `cleaning_client`, `tvde_passenger` (subject_types confirmados na BD).

### ⚠️ Pendente de ato humano (🔴 Lista Vermelha)

- **Tokens da Limpeza** — `supabase/PROPOSTA_20260706_cleaning_tokens.sql`:
  trigger que atribui tokens ao cliente `GREATEST(1, ROUND(total×3/100))` +
  profissional (+40) ao concluir. O Danilo disse "vai", **mas a Trava mecânica
  (`protege-banco.sh`) bloqueia DDL de tokens vinda do agente** — por design.
  Está pronto e reversível; **o Danilo aplica à mão** (SQL editor ou mover para
  `migrations/`). Enquanto não aplicado, a Limpeza não atribui tokens (tal como
  TVDE e marcações — coerente com o resto da app hoje).

### ⏳ Deixado para v2 (justificado, não é buraco silencioso)

- **Edição de perfil pós-registo** (foto/bio/raio) com UI dedicada: a foto e os
  dados entram no cadastro; a RPC `cleaner_set_profile` existe. UI de edição
  completa fica para v2 (não bloqueia o fluxo).
- **Gestão de documentos pós-registo** (re-upload): docs entram na candidatura;
  substituição posterior fica para v2.
- **Deep-link de estado no push**: transversal (nenhum vertical o faz hoje além
  de oferta TVDE/broadcast/chat) — melhoria global futura (G3).

### 🐞 Bugs fora de scope — reportados, NÃO corrigidos (ficam para o dono)

G1 (`business_rules.md` tokens "3%" vs código ×3 — **corrigido no doc**, ver
abaixo), G3 (`notify-client` hardcoda `type`), G4 (Edge Fns `upload-*` sem
fonte local), G5 (`_myRole` unused), G6 (drift de DDL de chat em prod sem
migration). Recomendo uma sessão de "sincronização repo↔prod" para G4+G6.

### Verificação

- `dart analyze` **por ficheiro** (regra da máquina 4GB) — limpo em todos os
  ficheiros alterados.
- Chão anti-trapaça (`python .claude/juiz/anti_trapaca.py --base f0bd479`):
  ✅ CLEAN — 0 testes tocados, 0 casos removidos.
- **NÃO foi feito push** — tudo commitado localmente na branch
  `autonomous-night-2026-04-29`, pronto para revisão do Danilo.
