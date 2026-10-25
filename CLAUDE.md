# CLAUDE.md — Bora App (repo bora-app-cloud)

> Cortado a 2026-10-23 (missão `livro-comum-2026-10-23`) de 706 para menos de 200 linhas.
> Nada se perdeu: o texto inteiro anterior está em `docs/contexto/claude-md-detalhe-2026-10-23.md`
> e na página `livro-claude-md-detalhe` do livro. Abrir esse ficheiro quando faltar detalhe.

@AGENTS.md

## 1. Antes de planear

- Ler `PADRAO_BORA.md` (lei da casa: o que uma categoria/papel novo tem de ter, regra dos
  gémeos, provas, publicação, segredos, zonas que não se tocam). Manda sobre hábitos; só perde
  para ordem explícita do Danilo na conversa. Se estiver errado, corrige-se o documento.
- Cérebro do repo: ler `.claude/.ai/knowledge/INDEX.md` e carregar SÓ os ficheiros do tema.
  Só o agente `bibliotecario-cerebro` escreve no Cérebro (handoff no fim, ver `PROTOCOLO.md`).
  Aplicar só factos `estado: atual`.
- Missões: skill `protocolo-missao-bora`; todo prompt de missão entra pelo CEO-AI
  (`.claude/skills/ceo-ai/`). Antes de abrir sites: skill `navegadores-e-contas`.
- LEI DO PRÉ-VOO: antes de começar, simular se o caminho vai dar certo (timeout, ficheiro em
  falta, permissão). Duas falhas iguais → mudar de abordagem, nunca uma 3.ª igual.

## 2. Modo de execução

- Tarefa pedida pelo Danilo = autorizada. Executar ponta-a-ponta, sem menus nem "posso?".
- Única travagem: dinheiro real (Stripe, preços, taxas, comissões, `finalizePurchase`,
  `bora_tokens`, `platform_settings` financeiros, migrações que mudem valores cobrados/pagos).
  Preparar tudo e escrever no relatório: "⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto
  — confirma que eu aplico." Só aplicar com o "autorizo"/"vai" dele.
- Classificador bloqueou uma ação: registar em `docs/TRANCAS.md`, saltar, continuar.
  Mods `bora-mods` (tranca, vigia): se negarem, não contornar — skill `mods-bora`.
- Identificar causa → corrigir → validar → repetir até resolvido. Nunca parar a meio.

## 3. Gate do Juiz (nenhum trabalho de agente é aceite sem isto)

1. `python .claude/juiz/anti_trapaca.py` SEMPRE primeiro (teste apagado/enfraquecido/skip/
   conserto-fantasma via git diff). exit 2 → rejeita.
2. `flutter analyze` limpo · `flutter test` verde · zona protegida intocada · business_rule respeitada.
3. Mudança Flutter: rubrica UI (funcional/visual/layout/UX).
4. Rejeição → lição (`.claude/juiz/reflexao.py`) → `bibliotecario-cerebro`.
Scripts em `.claude/juiz/`. Ver `.claude/juiz/README.md`.

## 4. Agentes e esquadrões

- 29 agentes em `.claude/agents/` (ver `README.md`). Agentes orquestram skills; nunca duplicam
  a lógica delas. CEO-AI é o dispatcher: um líder + 2 a 4 agentes, nunca o exército todo.
- 🟢 zona segura · 🟡 sensível · 🔴 dinheiro = PROPOSE-ONLY (`pagamentos-wallet`, `dispatch`).
- Gatilho de paridade: toda feature num domínio convoca também `admin` (ecrã PT-BR).
- Loop autónomo (Fase 5): `maestro-autonomia` → esquadrão → Juiz → Central
  (`AdminRobotSuggestionsScreen`). Kill switch `robot_b_enabled=false`. Detalhe em
  `docs/fase5/ENVELOPE_SEGURANCA.md`.
- Tabela completa de esquadrões por tipo de tarefa: ficheiro de detalhe, secção "Regras de despacho".

## 5. Produção (resumo de `regras-operacao-agentes`, 16/09)

- PODES: ler tudo; passar pedido a estafeta só com
  `select public.ops_reassign_order('<pedido>', '<user_id>', '<motivo>', 'claude-code');`
  (se `ok=false`, dizer o motivo ao Danilo; `p_forcar` só por ordem dele); devolver a todos com
  `ops_release_order_driver`; registar no Córtex.
- NÃO PODES: UPDATE/INSERT/DELETE direto em `orders`, `tvde_rides`, `appointments`, `drivers`,
  `client_wallets`, `wallets`, `ledger_entries`, `bora_tokens`, `driver_balances`, `payouts`,
  `platform_settings` de preços; mexer em dinheiro sem "vai"; migrar zonas protegidas
  (propor com `cortex_propor`); apagar dados (correção só com backup `bkp_<nome>_AAAAMMDD`).
- Identidade do estafeta: `user_id` manda em tudo o que a app vê (`assigned_driver_id`,
  `current_driver_offer_id`, créditos, saldo). `drivers.id` só para `tried_driver_ids`.
  Flutter: `.eq('user_id', uid)`, upsert `onConflict: 'user_id'`. Verificador:
  skill `identidade-estafeta`.
- Funções SQL novas nascem fechadas a `anon`; abrir só com `GRANT EXECUTE ... TO anon` explícito
  e motivo (app antes do login, página pública, robô com `p_chave`).

## 6. Regras de código (Core Rules)

- Model → Store → Screen. NUNCA String para status: enum `OrderStatus`
  (created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered).
- Nunca partir o que funciona; manter compatibilidade com o Supabase.
- `OrderStore` compara por ID, nunca por referência (o realtime substitui objetos).
- Navegação: `_RootNavigator` em `main.dart` reconstrói por estado (`SessionStore`/`AuthStore`).
  Nunca `pushReplacement` para os ecrãs principais.
- Providers em ordem de dependência em `main.dart`; `DispatchEngine.attach` é idempotente.
- Preços só por `PricingService.calculateBreakdown(...)`. Nunca calcular taxas em ecrãs.
- `OrderModel.fromSupabase`/`toSupabase` para toda a serialização.
- `assigned_driver_id` é TEXT de propósito (cast `::UUID` nos triggers). Não mudar o tipo.
- `restaurants.id`, `products.id`, `orders.id` são TEXT em prod (legado).
- Mapas: `google_maps_flutter` (widget) + `latlong2` (contas); `toGMaps()` em
  `lib/utils/map_utils.dart`; importar o Google com `hide LatLng`.
- Segredos: `String.fromEnvironment` + `.dart_defines` (gitignored). Nunca chaves em `lib/`.
- `supabase/schema.sql` é documento (snapshot), não migração. Migrações em `supabase/migrations/`.
- Arquitetura completa (auth dual, realtime, batching, dispatch, pagamentos, autocomplete):
  ficheiro de detalhe, secção "Architecture Overview".

## 7. Comandos

```bash
flutter pub get
flutter analyze        # 0 erros
flutter test
flutter run --dart-define-from-file=.dart_defines
```
Portão de RAM do PC (4 GB): 400 MB livres para trabalho leve, 800 MB para compilar/analisar
Flutter, 3 GB para emulador. Medir com
`(Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes`.

## 8. Publicação

- Push no ramo `autonomous-night-2026-04-29` = publicação (build Android → Play + deploy web).
  Commits só-`.md`/só-`.claude/` não disparam, mas o paths-ignore avalia TODOS os commits do
  push: ver sempre o que viaja junto. `git add` por caminho; WIP de outras sessões fica fora.
- `versionCode` é do CI. Nunca mexer no `pubspec`.
- `context-mode` (`ctx_*`, `/ctx doctor`) só existe em sessões interativas, não no loop `-p`.

## 9. Comportamento (Karpathy)

1. Pensar antes de codificar: dizer as suposições; se há várias leituras, escolher e explicar.
2. Simplicidade: o mínimo que resolve. Nada especulativo, nada de abstração para um só uso.
3. Mudanças cirúrgicas: cada linha mudada liga-se ao pedido. Não "melhorar" código vizinho;
   limpar só os órfãos que a tua mudança criou.
4. Objetivo verificável: transformar a tarefa num teste/critério e repetir até passar.

## 10. Decidido pelo Danilo (15/10/2026, vale até ele dizer o contrário)

- Autorização é por missão, com a frase dele e a data. Nunca "para sempre".
- Tokens do cliente: usa no máximo METADE do valor dos tokens que tem; conta linha a linha.
- Quem desliga um papel (TVDE, limpeza, lavagem) não recebe ofertas desse papel.
- Reembolso ao meio original (cancelamento sem estafeta): pronto, interruptor DESLIGADO.
- NÃO FAZER: devolver dinheiro aos 4 clientes dos tokens nem os 2,50 € do Martim; da lista
  Uber/iFood nada além da lupa e do carro a deslizar; preços dos mercados; prémios do check-in.
- Check-in diário no ar (5,5,10,10,15,15,40 tokens; 60 dias). 2.ª novidade: Receita do Dia.
- TVDE: fila inteligente (40 s, passa ao 2.º sem recalcular); reservas tocam pelo tempo de
  estrada (mínimo 10 min).
- Marca "Já Está" registada no INPI; a app continua "Bora". A Stripe está no nome dele: não mexer.
- Mercadona parada até "vamos reabrir a loja" (página `mercadona-reabrir-loja`).

## 11. Issue tracker e domínio

- Ficheiros locais em `.scratch/`, nunca GitHub Issues (`docs/agents/issue-tracker.md`).
- `CONTEXT.md` na raiz + ADRs em `.claude/.ai/knowledge/wiki/decisoes/` (`docs/agents/domain.md`).
- Contexto por área em `docs/contexto/` (01 fundador … 08 lições; 00 = contexto nuclear antigo).
