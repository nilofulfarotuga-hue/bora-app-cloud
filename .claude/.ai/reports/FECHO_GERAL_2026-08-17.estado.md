# FECHO GERAL 2026-08-17 — ESTADO (retomável)

> Missão iniciada 2026-08-17 (manhã, mesma sessão da varredura) · Motor: Fable 5
> Branch de trabalho: `autonomous-night/fase2-cortex-tasks` (produção = autonomous-night-2026-04-29, vc530)
> NÃO TOCAR: stripe-webhook v34 · fix do cêntimo · guardas dispatch · sweeper pagamento abandonado ·
> driver_earnings_summary (corrigida pela Claude.ai 17/08 — status 'finalizada' + chave tolerante).

## Plano de fases
- [x] **F0 — LIGAR OS OLHOS 2 e 3** (chave Gemini GRAVADA em backend/.env ✓ gitignored; Test Lab se secret existir)
- [x] **F1 — BLINDAGEM ANTI-MENTIRA** (5 medidas da ordem-20260811160435-2540 do Córtex)
- [x] **F2 — P6: PIN validado no SERVIDOR** (servidor FEITO+provado; costura Flutter = PROPOSTA zona 🔴) (RPC driver_validate_delivery_pin + app envia, nunca decide)
- [x] **F3 — P8: REATRIBUIR no admin** (padrão Isabel/Valdemir: user_id, offer limpo, notify, auditoria)
- [ ] **F4 — C4: pc_judge vivo na VPS** (copiar master→container, restart, prova com travada real)
- [ ] **F5 — FECHO** (relatório + vault + platform_settings + Córtex + digest Hermes + ctx)

## MARCOS

### MARCO F0 (olhos) — 2026-08-17
- Olho 2 (juiz de visão): chave Gemini gravada em backend/.env, MAS a chave está com **Spend cap breached**
  no projeto GCP 765097014497 (403 PERMISSION_DENIED em query-param E header — provado por curl). O juiz
  corre e é fail-visible; falta o Danilo levantar o teto de gasto / trocar a chave. 13 achados-erro
  removidos da vision_findings (não poluir).
- Olho 3 (Test Lab): secret GCP_SA_KEY EXISTE (o Danilo pôs). 1º run falhou no build APK (faltava decode
  do google-services.json) → CORRIGIDO (workflow no ref da varredura + cópia no main p/ cron). Re-disparado
  (run 32009467418). O gate do secret passou; a autenticação da service account será provada nesse run.

### MARCO F1 (blindagem anti-mentira, ordem-20260811160435-2540) — 2026-08-17
As 5 medidas do conselho VERIFICADAS no sistema vivo (não duplicadas — já existiam desde 11/08, confirmei
que estão ligadas):
- M1 PROVA MATERIAL: `prova_material()` corre ANTES de todo fecho positivo no carteiro vivo (linhas 1598-1610);
  sonda `pc-prova` provada nos 2 lados: sem ficheiro→`SEM-PROVA` (barra→estado `incompleta`), com ficheiro
  real→`HA-PROVA`+caminho. As duas metades da prova-canário demonstradas.
- M2 UM FICHEIRO VERDADEIRO: sem espelho carteiro.sh no repo cortex-brain; sync-brain só escreve num ESPELHO
  MORTO documentado, o vivo /root/orquestracao/carteiro.sh está sob git local — reset nunca o toca. ✓
- M3 CAPTURA REAL: criado /root/orquestracao/capturas-reais/ (SAIDA-VAZIA real de 12/07 + sucesso real de
  06/08) + replay-prova.sh que corre os classificadores REAIS; provado, nunca mudo. Regra do minimax gravada.
- M4 LOG REAL ANEXO: canário A travou honesto com CLI-SEM-AUTH + JSON de auth literal na nota (não genérica) —
  é a própria prova da medida; clean() já preserva linhas com ERRO desde 01/08.
- M5 NADA PENDENTE PARA SEMPRE: 502 travadas históricas (>2 dias) fechadas em lote como `falhou_historico`
  com ledger m5-fecho-historico-20260817.tsv, backup tgz antes, ZERO apagadas; 6 recentes ficam p/ triagem.

### MARCO F2 (PIN server-side) — 2026-08-17
Descoberta: o PIN NUNCA teve coluna — é derivado do UUID no Dart (4 hex %9000+1000); por isso a validação
era local. RPC `driver_validate_delivery_pin` aplicada (deriva o MESMO valor server-side, tabela
delivery_pin_attempts, bloqueio à 5.ª + alerta admin via pg_net, idempotente). PROVADO por SQL com
identidade de teste: errado→wrong_pin(4), certo→ok+delivered, repete→already_delivered, 5×→blocked; pedidos
de teste limpos. Costura Flutter (order_store 🔴) = PROPOSTA em F2_PIN_order_store_PROPOSTA.md.


### MARCO F0.3 (Olho 3 — Test Lab, atualizado) — 2026-08-17
Run 32009467418 (13m13s): gate ✓, google-services ✓, build APK ✓, service account AUTENTICOU ✓.
Falhou SÓ no gcloud com `403: Not authorized for project boraapp-d2bea` — a SA está autenticada mas
sem permissão na Testing API do projeto. GUIA 2 CLIQUES (Danilo):
  1) console.cloud.google.com → projeto boraapp-d2bea → APIs & Services → ativar "Cloud Testing API"
     e "Cloud Tool Results API" (se ainda não estiverem).
  2) IAM & Admin → IAM → encontrar a service account do GCP_SA_KEY → Edit → Add role
     "Firebase Test Lab Admin" (roles/cloudtestservice.testAdmin). Guardar.
Depois: Actions → olho-testlab-robo → Run workflow (o build e a autenticação já passam; falta só o papel).
Download de artefactos endurecido (gs://boraapp-d2bea_test/ + fallback test-lab-*).

### MARCO F3 (reatribuir no admin) — 2026-08-17
Descoberta: a RPC `admin_reassign_order` JÁ EXISTIA (o gap era só a UI — a varredura viu 0 no Flutter).
Fazia o padrão certo (user_id, offer limpo, auditoria log_admin_action) mas FALTAVA a notificação ao
novo estafeta. Acrescentei o notify-driver via pg_net (aditivo, best-effort, WARNING nunca silêncio).
PROVADO por SQL com identidade admin simulada + rollback: reatribuir a Valdemir (user_id real) →
status callingDriver→driverAccepted, assigned_driver_id = user_id, current_driver_offer_id=null,
auditoria gravada. UI aplicada em admin_order_detail_screen.dart: botão "Reatribuir estafeta" (só em
pedido ativo) → folha de elegíveis (admin_live_drivers: online+aprovado) → confirma → RPC → refresh.
analyze 0 erros. NÃO é zona 🔴 (reatribuição não cobra/calcula dinheiro).

## Notas de retoma
- Chave Gemini: GRAVADA como GEMINI_API_KEY em backend/.env (2026-08-17, colada pelo Danilo no chat; NUNCA versionar).
- Stash intacto: "tvde-plan-payment v10 tokens PENDENTE-VAI".
- gh autentica via credencial wincredman: TOKEN=$(git credential fill) → GH_TOKEN.
- vision_findings (tabela) e test/golden (13 fotos) já existem da varredura.
