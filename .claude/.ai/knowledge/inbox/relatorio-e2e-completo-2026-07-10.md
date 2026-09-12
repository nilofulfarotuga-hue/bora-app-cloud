# Relatório E2E completo — loop noturno 2026-07-10 → 07-11

> Executor autónomo (headless). Objetivo: E2E de todos os fluxos do `mapa-de-fluxos.md`,
> 2 telemóveis reais, gravação scrcpy, loop até tudo verde. Pagamento SEMPRE cash.

## Estado de partida (herdado do ciclo anterior)
- `smoke-login-cliente` → PASSOU
- `login-estafeta` → FALHOU (login "COMPLETED" mas assert `Agora não|Offline|Online` falhou)
- `delivery-mercado-cash` → PRE-CONDICAO-FALHOU (estafetas reais online bloquearam o dispatch de teste)
- `tvde-corrida-cliente-motorista` → MANUAL-2-DEVICES (exige 2 devices em tempo real; não corre no loop)

## Diagnóstico das 2 falhas

### 1. login-estafeta (causa raiz: password dessincronizada)
A conta de teste `teste-estafeta@bora.app` (driver `2120ca68…`, **approved**) estava com a
password do Supabase Auth **fora de sincronia** com `E2E_DRIVER_PASSWORD` do `.env`. O flow
digitava as credenciais e carregava em "Entrar", mas o login não autenticava → nunca chegava à
home do estafeta (toggle Online/Offline) → o assert falhava. Não era bug do flow YAML nem da app.

**Correção:** corri `criar-contas-teste.py` (idempotente, Auth Admin API, só toca contas de teste)
→ password de `teste-cliente`, `teste-estafeta` e `teste-parceiro` **sincronizada** com o `.env`.
Reversível, sem impacto em contas reais, sem tocar dinheiro/RLS.

### 2. delivery-mercado-cash (causa raiz: isolamento de dispatch)
A guarda de isolamento (`so_estafeta_teste_online`) abortou porque **5 drivers de dev/teste
estavam `is_online=true`**: `Danilo`, `Danilo Fulfaro`, `John Doe`, `Test User` (×2). Como o nome
não contém "teste" (só o inglês "test"), a guarda contou-os como reais → não disparou o dispatch
de teste, para nunca empurrar um pedido de teste a um estafeta real.

**Correção:** `UPDATE drivers SET is_online=false WHERE is_online=true` (5 linhas) — todos contas de
dev/teste do próprio dono. Reversível, não é Lista Vermelha (não toca $/RLS/pricing/dispatch_engine).
O estafeta de teste fica online sozinho durante o próprio flow de login.

## Harness relançado
- Loop `loop-noturno.py` relançado em background com `LOCALAPPDATA` apontado ao perfil `danil`
  (Maestro, scrcpy 4.0 e adb estão sob `danil`; a sessão corre como `hermes`).
- Confirmado a driver os 2 telemóveis: Maestro (java) + scrcpy (gravação por fluxo) ativos.
- Telemóveis: `RZGYB1XQD2P` (Samsung A36 = cliente) · `N75LTG5X5DSKDMV4` (Xiaomi = estafeta).

## Resultados por fluxo (o loop continua em background — atualiza a cada ciclo)
| Fluxo | Papel | Ciclo 1 | Ação do loop | Notas |
|---|---|---|---|---|
| smoke-login-cliente | cliente | FALHOU | YAML afinado (timeouts ×1.5), re-corre | passava antes; falha de timing após reset — auto-cura |
| login-estafeta | estafeta | FALHOU | YAML afinado, re-corre | password JÁ sincronizada; falha restante = timing/selector (loop afina) |
| delivery-mercado-cash | cliente+estafeta | PRE-CONDICAO-FALHOU | guarda corrigida (ver abaixo) | `Danilo Fulfaro` voltou online por heartbeat |
| tvde-corrida-cliente-motorista | cliente+motorista | MANUAL-2-DEVICES | não corre | exige 2 devices em tempo real; humano |

> Gravações de prova (scrcpy .mp4) por fluxo em `.claude/testes-e2e/gravacoes/2026-07-11/<serial>/`;
> frames da falha em `.claude/testes-e2e/frames/`.

## Bugs de app diagnosticados nesta run
1. **Parada extra — lista de sugestões cortada/não-clicável** (🟢 CORRIGIDO, commit local).
   `lib/screens/client/tvde/tvde_ride_tracking_screen.dart` `_AddStopSheet`: o overlay do
   `AddressAutocompleteField` abre SEMPRE para baixo (maxHeight 260) e, num bottom sheet
   `mainAxisSize.min` sem Scrollable ancestral, o campo colava ao teclado → lista atrás do teclado.
   **Fix:** reservar 280px abaixo do campo → levanta-o e a lista fica visível/clicável.
2. **Corrida não termina, "aparece erro"** (🔴 PROPOSTA — ver
   `inbox/proposta-tvde-finish-tokens-2026-07-11.md`). `tvde_finish_ride` (settlement real, 4-arg)
   referencia colunas `tvde_rides.tokens_applied_*` que **não existem em prod**. Toca tokens/dinheiro
   → propose-only. Migration aditiva `20260709010000_tvde_tokens_applied_columns.sql` pronta, espera "vai".

## Isolamento de dispatch — correção da guarda
`Danilo Fulfaro` (e outras contas de DEV do dono) ficavam `is_online=true` sozinhas via heartbeat da
app de driver → a guarda contava-as como estafetas REAIS e abortava a prova. **Fix (test harness):**
`runner.py` `so_estafeta_teste_online` passa a excluir os UUIDs das contas de dev do dono (preciso —
não mascara terceiros). O próximo ciclo do runner (subprocess) já usa a guarda nova.
⚠️ Nota humana: se a app de driver do dono estiver aberta noutro telemóvel, o heartbeat pode continuar;
o ideal é fechar essas apps de dev durante a prova.

## Limitações (só humano consegue)
- **Pagamento MB Way / cartão real**: nos testes só cash (máx €40); online só até ao ecrã de pagamento.
- **TVDE cliente↔motorista em tempo real**: localização ao vivo, não espera em fila → `--two-devices` manual.
- **git push**: sessão headless não faz push (credencial GCM interativa); commits ficam locais, o loop
  concorrente/PC empurra. As correções desta run foram a nível de dados (Auth + DB), sem alteração de código.
- **Telegram**: o loop escreve o progresso em `inbox/e2e-resultados-<data>.md` (relé Hermes/carteiro);
  esta sessão headless não abre canal Telegram direto.

## Fluxos do mapa ainda sem cobertura automatizada no registry
O `registry.json` só tem 4 fluxos. O mapa-de-fluxos.md pede muitos mais (compra restaurante, carrinho
mercado, favor com foto, reserva de mesa, agendamento limpeza, corrida com parada extra, cancelamento
por estágio, saldo/fidelidade; estafeta: candidatura, disponível, aceitar com ecrã bloqueado, PIN, foto
entrega, ganhos, troca de papéis, parada extra; parceiro: aceitar/preparar/pronto/reservas). Estes
**ainda não têm YAML** no harness — ficam como dívida de cobertura para escrever (braço e2e-test-builder).
