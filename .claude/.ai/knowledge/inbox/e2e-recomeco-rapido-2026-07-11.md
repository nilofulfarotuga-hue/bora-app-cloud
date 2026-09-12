---
id: e2e-recomeco-rapido-2026-07-11
tipo: relatorio
origem: [executor-noturno]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: auto
---

# E2E — recomeço rápido (junta f6aa + 7c4f) — 2026-07-11

## 1) Processo preso + telemóveis
- A ordem f6aa arrancou `comum/reset-role-screen.yaml` às **18:57:13 UTC** (device
  RZGYB1XQD2P) e ficou parada — o "destravar-tudo" das **19:04 UTC** já a tinha matado.
  **PID 832 (o run f6aa) confirmado MORTO** — não havia maestro/runner pendurado para matar.
- Processos vivos eram só: 2× `graphify-mcp` + 2× `tail_e2e_log.py` (watchers) + 1 scrcpy de
  gravação. Inofensivos.
- `adb devices`: **os 2 telemóveis respondem e estão autorizados** —
  `N75LTG5X5DSKDMV4` (Xiaomi cloud) e `RZGYB1XQD2P` (SM-A366B). (Às 18:41 o RZGY tinha caído
  para `unauthorized`; recuperou.)

## 2) Causa-raiz do hang de 20+ min — CORRIGIDA
`comum/reset-role-screen.yaml` tinha **dois `extendedWaitUntil` com `timeout: 300000` (5 MINUTOS
cada)**. Se a app resumisse num estado inesperado (ANR/ecrã sem "Sou Cliente"), o Maestro ficava
5–10 min parado por reset — exatamente o hang silencioso.
- Reduzidos para **timeout curto (~25–45s)** (ponto 4 da tarefa). Um loop concorrente afinou os
  valores finais (25s no diálogo, 45s no assert RoleScreen) — ambos curtos, sem regressão.
- O `runner.py` **já tinha** o teto duro `MAESTRO_TIMEOUT_S = 480` por chamada Maestro +
  `screenshot_falha` (regra de ouro: foto + segue) — a rede de segurança contra hang já existia.

## 3) Regra de ouro (ponto 3) — já implementada
`runner.corre_maestro` → em falha/timeout tira `adb exec-out screencap`, regista o caminho no
`e2e_log` e devolve `ok:False` sem rebentar o loop. Os passos frágeis do flow são `optional`.

## 4) Flow delivery-mercado-cash (ponto 2) — já cobre o pedido
O `cliente/delivery-mercado-cash.yaml` já faz: abrir loja → scroll DOWN/UP (prova) → abrir lista de
produtos → **scrollUntilVisible do preço `€[0-9]+[.][0-9][0-9]`** → adicionar pelo **`+` (Semantics
id `btn_add_carrinho`)** com fallback pelo detalhe → confirmar "Ver carrinho" → Finalizar →
**Dinheiro** → Confirmar pagamento. Sem alterações necessárias à lógica de adição ao carrinho.

## 5) BUG HTML (ponto 5) — JÁ RESOLVIDO
- DB: **0 produtos** com entidades HTML (`&atilde;`, `&#NNN;`, `&#xHH;`). Os 870 nomes com `&` são
  **legítimos** (J&B Whisky, M&M's, Fast & Furious, Repair & Protect…). Não há nada a descodificar.
- Crawler: `supabase/functions/update-products/index.ts` **já tem `decodeEntities` completo**
  (nomeados PT/Latin-1 + numéricos `&#N;` + hex `&#xH;`) aplicado a name/brand/category com
  duplo-passe para entidades duplamente codificadas (`&amp;atilde;`). Futuro protegido.

## 6) Criar 1 pedido real (ponto 6)
- Baseline `orders`: **35 linhas, último 2026-07-09** → confirma que os runs de 10–11/07 criaram
  **0 pedidos** (o bug que motivou a tarefa).
- Lançado `runner.py --fluxo delivery-mercado-cash --single-device` (device RZGYB1XQD2P).
  <!-- RESULTADO_RUN -->

## Ficheiros tocados
- `.claude/testes-e2e/flows/comum/reset-role-screen.yaml` — timeouts 300000→curto (anti-hang).
