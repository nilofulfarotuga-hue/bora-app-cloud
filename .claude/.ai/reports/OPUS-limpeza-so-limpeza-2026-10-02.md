# Missão limpeza-so-limpeza — 02/10/2026

run_id `limpeza-so-limpeza-2026-10-02` · porta Claude Code · ramo `autonomous-night-2026-04-29`
Provas: `.claude/.ai/provas/limpeza-so-limpeza-2026-10-02/` · rasto: `e2e_log` (fluxo = run_id)

## Acessos

- Site de prova: https://app.boraguarda.com (bundle novo confirmado: 10 697 624 bytes)
- Commits: `2ff0a0e0` (portão por papel), `0338e887` (ficha de estafeta deixa de nascer por arrasto)
- Contas de prova (neutralizadas, não apagadas): `746b98a0…` PROVA Limpeza (teste) · `5a5d2b38…` PROVA Limpeza 2 (teste)

## O que NÃO ficou feito (ler primeiro)

> **Atualização 16:53 de Lisboa:** a base voltou sozinha às 16:03 (uma hora em baixo, sem reinício do
> Postgres). Repetido o build Android (run `37014873730`, tentativa 2): autoteste dos 3 perfis
> **success**, AAB enviado para o Play (alpha), `ci: bump versionCode to 638` no ramo. O ponto 1 abaixo
> ficou resolvido; o iOS foi reenviado e estava a correr. Digest gravado em `claude_ai_memoria`
> (`digest-2026-10-02-limpeza-so-limpeza`).

1. ~~A versão Android NÃO foi para o Play.~~ **Resolvido à segunda tentativa (ver atualização).** O
   autoteste dos 3 perfis falhou nas duas primeiras corridas, e o
   build ficou saltado nas duas. Nenhuma das falhas é do código desta missão:
   - corrida 1 (`37013815828`): parou no perfil CLIENTE, na página do Auchan, à procura do botão de
     adicionar ao carrinho (`demo_real_test.dart:440`, "Bad state: No element");
   - corrida 2 (`37014873730`): o login do cliente demo levou `504 upstream request timeout` do
     Supabase — é o incidente descrito mais abaixo.
   Falta repetir o job quando a API estiver boa. **A web já está publicada com a correção**; o Android
   e o iOS ainda não.
2. **Incidente em produção a decorrer no fecho deste relatório:** desde as 14:05 UTC (15:05 de Lisboa)
   a API do Supabase devolve 504/522 a quase tudo. A causa NÃO é esta missão: é a app Android a ler
   o catálogo inteiro ao arrancar, que já falhava desde as 12:04 UTC. Ver secção própria.
3. **Painel admin por papel: escrito e analisado, mas NÃO visto no ecrã.** Não tenho sessão de admin
   para abrir o painel. O que está provado é a função que o botão chama (`admin_review_cleaner`).
4. **Prova no emulador Android: não feita.** O PC tinha 189 MB livres (o Ollama a servir a VPS ocupa
   4,3 GB e estava em uso). A prova fez-se pela web, no site publicado, como manda o PADRAO §3.10.
5. **Push com o telemóvel bloqueado / app fechada: não provado.** O que se provou foi a entrega ao
   Firebase (`enviados: 1`) e a oferta visível no painel. O toque no aparelho precisa de telemóvel.
6. **Quem tem limpeza PENDENTE e entra pela porta "Sou Estafeta" ainda vê o ecrã do estafeta**
   ("Termos do Estafeta" + "Conta em análise"). Não fica presa nem ganha ficha de estafeta, mas o
   texto fala de estafeta e devia falar de limpeza.

## Bloco 1 — Inscrição só para limpeza funciona sozinha

**Causa real (duas origens, as duas provadas):**

- A porta "Sou Estafeta → Criar conta" ia direta ao `DriverSignupScreen`, que no passo 2 chama
  `driver_register_or_update` e cria logo a linha em `drivers` (mota, pendente). Foi assim que nasceu a
  da Mayra: `drivers` às 12:05:00, `cleaners` às 12:06:34 de 01/10.
- Pior: o `DriverStore._upsertDriverRow` criava uma linha em `drivers` a **qualquer pessoa** que abrisse
  o ecrã do estafeta sem ter ficha. Provado em produção com a conta de prova: ganhou `drivers`
  (car, pending) às 13:39:32 UTC só por entrar.
- O portão (`_RootNavigator` + `DriverHomeScreen._buildPendingScreen` + `_finishDriverLogin`) só olhava
  para `drivers.approval_status`.
- O servidor **não** exigia `drivers` para a limpeza (`cleaner_accept_booking`, `_cleaning_next_offer`,
  `_cleaning_current_cleaner` só leem `cleaners`). Não foi preciso mexer na base.

**O que mudou e porquê:**

| Ficheiro | Mudança |
|---|---|
| `lib/services/roles_service.dart` | `entradaDoPrestador()` — função pura: entra quem tiver QUALQUER papel aprovado |
| `lib/widgets/portao_do_prestador.dart` (novo) | `PortaoDoPrestador`: com o estafeta por aprovar, abre o ecrã do papel aprovado; relê ao voltar à app; 8 s de limite |
| `lib/main.dart` | `_RootNavigator` passa pelo portão quando o estafeta não está aprovado |
| `lib/screens/driver_login_screen.dart` | `_finishDriverLogin` deixa entrar com limpeza/lavagem aprovada; "Criar conta" abre a escolha de atividade |
| `lib/auth/auth_store.dart` | `switchToRole(driver)` aceita quem só tem limpeza/lavagem aprovada; sem linha em `drivers` o estado é "por aprovar" |
| `lib/stores/driver_store.dart` | removido `_upsertDriverRow`: a ficha de estafeta só nasce da candidatura |
| `lib/screens/cleaner/cleaner_home_screen.dart`, `washer/washer_home_screen.dart` | `comoEntrada`: botões de sair, trocar de atividade e usar como cliente |

**Provas:**

- Antes/depois da porta: fotos 01 e 02. Depois: "Entregas / Corridas de passageiros / Limpeza / Lavagem de carros".
- Caso da Mayra reproduzido: conta de prova com `limpeza=approved`, `estafeta=pending` (SELECT) entra
  direto em "Limpezas — Profissional", "A receber novas limpezas"; o estafeta pendente aparece como
  cartão "Candidatura a estafeta em análise". Foto 04.
- Só limpeza sem ficha de estafeta: conta 2 entrou pela mesma porta com o segundo deploy e ficou com
  `drivers = 0`, papéis = `cleaner` (SELECT).
- `flutter analyze` nos ficheiros tocados: só 1 aviso antigo (`anonKey`, main.dart:383).
  `flutter test test/*.dart`: +840 All tests passed. Teste novo: `test/portao_do_prestador_test.dart` (12).
- Juiz: anti-trapaça CLEAN, zonas protegidas CLEAN, identidade do estafeta OK. Verificador de contexto
  limpo: 0 graves, 6 menores, 5 corrigidos (conta fabricada em cache, espera sem limite, biometria
  oferecida a quem não a pode usar, "Aprovar" sem confirmação em suspensos, texto do painel).

## Bloco 2 — Notificações da limpadora

**Causa:** o aparelho só era registado para a limpeza ao abrir o painel da limpeza. A Mayra foi
aprovada sem nunca lá ter conseguido entrar. Prova: `ofertas_prestador_log` 02/10 12:38:32 —
`tem_aparelho=false`, janela de 1 minuto, `sem_resposta`; `provider_push_tokens` só às 12:46:48.

**O que mudou:** `cleaner_apply_screen.dart` regista o aparelho logo na candidatura;
`push_token_service.dart` deixa de deitar fora pedidos de registo que chegam com outro a meio.

**Provas:** conta 2, ainda pendente, já tinha 1 aparelho de limpeza registado. Oferta de teste (a
dinheiro, cliente demo): `tem_aparelho=true`, janela 30 min, visível no painel ("Ganhas €20,40 ·
Expira em 28 min · Recusar / Aceitar", foto 05), `notify-cleaner` → `{"ok":true,"enviados":1,"aparelhos":1}`.
A primeira tentativa deu `UNREGISTERED` com HTTP 200 — culpa do meu guião de prova, que apagava o
service worker; corrigido e repetido.

## Bloco 3 — Painel admin (PT-BR)

`lib/screens/admin/admin_papeis_screen.dart`, aba "Pessoas": uma linha por papel de trabalho
(Estafeta / Limpeza / Lavagem de carros: aprovada · pendente · recusada · suspensa · não inscrito), com
"Aprovar" e "Recusar" nas pendentes. Aprovar a Limpeza chega para a pessoa entrar — provado pela
função (`admin_review_cleaner`) e pelo login a seguir. **Ecrã não visto** (ver "não ficou feito").

Corrigido de caminho, porque o botão novo dependia dele: `admin_approve_driver(p_driver_id)` tem duas
versões na base e a chamada só com o id dava `42725 is not unique` — o "Aprovar" de estafeta nesta
tela estava partido. Passa a ir com `p_force=false`.

## Bloco 4 — Dados existentes

`cleaners` com `drivers` criado no mesmo minuto: **só a Mayra** (`9a8a5657…`, mota, sem carta, sem
matrícula, 2 minutos de diferença). Os outros dois são contas do Danilo, estafeta há meses. Nada apagado.

## Outros erros encontrados (reportados, não corrigidos)

- A aprovação manual do `drivers` da Mayra deixou-a **estafeta aprovada sem documentos nem veículo**.
  Com a app nova ela entra pelo ecrã do estafeta (que tem prioridade) e chega à limpeza pelo botão de
  troca. O certo é recusar essa ficha no painel — mas só **depois** de ela ter a app nova, senão a
  versão antiga volta a bloqueá-la.
- A lavagem tem o mesmo buraco do push: `washer_apply_screen` não regista o aparelho na candidatura.
- O registo de estafeta cria a linha em `drivers` no passo 2, antes de a pessoa acabar; quem desiste
  fica como candidatura pendente vazia.
- Rascunho de candidatura a estafeta fica escondido para quem já tem limpeza aprovada.
- O ecrã de entrada do prestador ainda diz "Área do Estafeta / Entrar como estafeta".
- `admin_approve_driver` com duas versões na base: outras chamadas só com o id falham igual.
- Não usar `demo@bora.app` em provas manuais enquanto o autoteste do CI corre: é a mesma conta, e o
  emulador recebeu a minha notificação de limpeza a meio do percurso.

## Incidente em produção — API do Supabase em baixo desde as 14:05 UTC

- `edge_logs` por minuto: até às 14:04 normal (~130 respostas 200/204); 14:05 começam 504 e 522;
  das 14:10 às 14:15, 100 % 504. A ligação direta à base também passou a dar timeout.
- Página de estado do Supabase: "Partially Degraded Service — API Gateway degraded_performance".
- Não houve pico de pedidos antes (1068, 636 e 841 pedidos nos três blocos de 5 min anteriores).
- A região eu-west-1 está "operational"; o incidente público do Supabase é nos EUA. É a nossa instância.
- **A degradação começou às 12:04 UTC, antes de esta sessão existir (12:51 UTC) e antes do primeiro
  deploy (13:37 UTC).** `postgres_logs`: "canceling statement due to statement timeout" numa leitura de
  `products` às 12:04, 12:35, 12:41, 13:01, 13:20, 13:21, 13:32 e 13:33. `edge_logs`: são pedidos
  `GET /rest/v1/products?select=…&restaurant_id=in.(…)` com `supabase-flutter 2.18.0; platform=Android`
  — a app Android a pedir os produtos de todas as lojas de uma vez ao arrancar, a devolver 500.
- Por hora, nos registos do Postgres: consultas lentas 0 até às 11h, 2 às 12h, 5 às 13h, 36 às 14h;
  timeouts 0 / 3 / 8 / 87. Às 14:08 houve uma consulta de 132 s e às 14:22 acabou uma de 876 s.
  Depois das 14:05 até `select now()` demora 10 a 60 s.
- Deadlocks em `drivers` / `driver_locations` são crónicos (20 a 50 por hora sempre que há estafetas
  ligados, desde ontem): dois caminhos a atualizar a posição do mesmo estafeta ao mesmo tempo.
- A corrida 1 do autoteste falhou pela mesma causa: a página da loja não chegou a ter produtos.
- **Conclusão: a causa é a leitura pesada do catálogo pela app Android, não esta missão.** O que a
  missão acrescentou foi carga pequena (duas contas de prova, duas reservas de teste).
- Danilo avisado por Telegram (texto e voz) às 15:19, 15:25 e 15:35 de Lisboa, com a página
  "Restart project" aberta no Chrome do PC. Não tenho forma de reiniciar daqui.

## PARA O DANILO

0. **Agora:** "Restart project" no painel do Supabase (página já aberta no Chrome do PC). A seguir,
   missão própria e urgente: a app Android não pode pedir o catálogo inteiro ao arrancar — é isso que
   está a asfixiar a base, e vai repetir-se a cada dia com mais gente.
1. Quando a API voltar: mandar repetir o build Android (ou dizer-me "repete o build").
2. Depois de a Mayra atualizar a app: recusar a ficha de **estafeta** dela no painel (Papéis → Pessoas).
3. Decidir se quem tem limpeza pendente deve ver um ecrã próprio em vez do do estafeta.
