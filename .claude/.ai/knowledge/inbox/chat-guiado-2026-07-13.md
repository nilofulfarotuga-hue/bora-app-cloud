---
escopo: agente:chat-suporte
data: 2026-07-14
autor: executor autónomo (loop noturno, branch autonomous-night-2026-04-29)
---

# Chat guiado de suporte + persona Hermes + escalação Telegram

Pedido do Danilo: redesenho do chat de suporte estilo Glovo/Uber (menu guiado por categoria →
"falar com humano" com persona → escalação ao Danilo via Telegram). A maior parte já estava
implementada (Flutter + Supabase + Edge Function), não commitada, de uma corrida anterior do
loop. Esta corrida: auditou o que existia, corrigiu uma lacuna de realtime, escreveu o gatilho
VPS que faltava, e fechou (commit + push).

## O que já existia (verificado, não recriado)
1. **Menu guiado por categoria** — `lib/screens/support_guided_menu_screen.dart`. Categoria →
   sub-opção → resposta pronta. Dados em `support_categories` / `support_category_options`
   (migration `20260714010000_chat_guiado_categorias.sql`), 7 categorias seed + 12 Q&A prontas.
   Editável no admin sem redeploy.
2. **Falar com humano** — `lib/screens/support_human_chat_screen.dart` fala com o Edge Fn
   `supabase/functions/support-human-chat/index.ts` (Gemini com system prompt de persona:
   Thayline/Thabyta, alterna por conversa, respostas curtas/naturais, nunca revela ser IA).
   Reusa `support_chatbot_sessions`/`support_chatbot_messages` do Robot A (só `mode` muda) —
   **não tocou no Robot A** (`support-chatbot`), como a Constituição exige.
3. **Escalação ao Danilo** — quando a persona não sabe resolver, marca
   `[ESCALATE_DANILO]` → grava em `support_escalations` + dispara `notify-admin-urgent`
   (push in-system imediato) → fica pendente para o Danilo responder. RPC
   `admin_reply_escalation(escalation_id, reply)` grava a resposta na mesma sessão do
   cliente (chega por realtime) e fecha a escalação.
4. **Paridade admin (PT-BR)** — `admin_support_escalations_screen.dart` (ver/responder
   escalações, realtime) e `admin_support_categories_screen.dart` (CRUD de categorias/Q&A).
   Ambas já ligadas em `admin_dashboard_screen.dart`.
5. **Deploy remoto** — confirmado via MCP Supabase: migration `chat_guiado_categorias` e o
   Edge Fn `support-human-chat` (v1, verify_jwt=true) já estavam ACTIVE no projeto
   `ojykpzwqrtusfeakzrna` antes desta corrida (aplicados por uma sessão anterior sem commit).

## O que esta corrida fez
1. **Lacuna encontrada e corrigida:** `support_escalations` não estava na publication
   `supabase_realtime` — o admin só veria escalações novas ao dar pull-to-refresh, não em
   tempo real. Aplicado via MCP (`ALTER PUBLICATION supabase_realtime ADD TABLE
   support_escalations`, guardado por `IF NOT EXISTS` em `pg_publication_tables`) +
   migration local `20260714020000_support_escalations_realtime.sql`.
2. **Verificação de correção de negócio:** o texto seed sobre reservas ("€2 fica para o
   restaurante, €1 é da Bora") foi cruzado com `reservation_partner_payout_cents` (default
   200 = €2 ao parceiro) em `20260503020000_reservation_rpcs_sync.sql` — confirmado correto,
   não alterado.
3. **Gatilho VPS que faltava (ponte Telegram):** criado
   `.claude/scripts/hermes-suporte-escalacao.sh`, no mesmo padrão de
   `hermes-aprovador-vermelho.sh` — cron */10 no host, lê o watermark anon
   `support_escalation_watermark()` (já existia na migration, mas sem consumidor), e ao
   detetar item novo (ou staleness ≥15min) injeta uma ordem que acorda o agente
   `chat-suporte` para ler a escalação e mandá-la ao Danilo por Telegram, citando o ID.
   **Este script ainda não está instalado no VPS** (só existe no repo) — falta o
   `hermes(host)` copiar para `/usr/local/bin/` + registar no cron, exatamente como os
   outros scripts em `.claude/scripts/`.
4. **`chat-suporte.md` atualizado** — passou a listar a posse de
   `support_categories`/`support_category_options`/`support_escalations`/
   `support-human-chat` e a regra MUST de nunca inventar a resposta de uma escalação (é
   sempre o Danilo).
5. `flutter analyze` limpo nos 6 ficheiros tocados (0 erros, só 4 infos de estilo
   pré-existentes — `withOpacity` deprecated, consistente com o resto do código).

## Pendências (para o Bibliotecário do Cérebro / próxima corrida)
- **Registar o novo loop em `permanente/semantica/loops.md`** (🟢 verde — chat guiado, dono
  Hermes(host)/`chat-suporte`), igual aos outros watermark-loops já lá.
- **Instalar `hermes-suporte-escalacao.sh` no VPS** (copiar para `/usr/local/bin/` + cron
  `*/10`) — isto fica fora do alcance deste executor (só tem o repo `bora_app`, não o
  filesystem do container VPS).
- A ponte Telegram→`admin_reply_escalation` propriamente dita (o agente `chat-suporte`
  a interpretar a resposta do Danilo no Telegram e chamar a RPC) depende do runtime do
  Hermes já ter esse fluxo de "ler pergunta, mandar Telegram, aguardar resposta, aplicar" —
  o mesmo padrão do Balde B do `aprovador-vermelho`. Não há código Python/agente novo a
  escrever aqui; é o agente `chat-suporte`, quando acordado pela ordem, que faz isso via
  as suas próprias ferramentas (Telegram + RPC), seguindo a instrução na ordem.

CHAT GUIADO + personas + ponte Telegram OK.
