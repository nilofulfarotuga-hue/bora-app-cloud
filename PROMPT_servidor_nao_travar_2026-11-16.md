⚠️ MODO PROTECÇÃO TOTAL ⚠️

# Missão `servidor-nao-travar-2026-11-16`

**MOTOR:** Opus 5.5 · **PORTA:** Claude Code no PC do Danilo (Controlo Remoto, "bora-app-cloud · Danilo"), sessão nova.
**ORQUESTRADOR:** abre primeiro o CEO-AI (`.claude/skills/ceo-ai/`) e a skill `protocolo-missao-bora`.
**e2e_log:** fluxo `servidor-nao-travar-2026-11-16`, um passo por bloco (`B0`…`B8`), com prova material em cada um.

## Autorização do Danilo (citar e cumprir)

- 16/11/2026 16:50: "Eu autorizo. Isso não pode acontecer. Se tiver 10 clientes ao mesmo tempo, vai travar. Não pode acontecer com 100 clientes. Vai a fundo nisso aí. Como é que tem que fazer da maneira certa para não travar mais?"
- 16/11/2026 17:20: "Faz tudo isso que eu te falei aqui nessa conversa. Manda a tarefa, faz o que tem que fazer."
- Isto autoriza mexer em `lib/stores/order_store.dart` (zona do Juiz) SÓ na forma de reler pedidos e ligar o tempo real. NÃO autoriza preços, comissões, ganhos, Stripe, tokens, carteira, `finalizePurchase`, nem o motor de despacho (`dispatch_engine`). Se um bloco precisar disso: prepara tudo, escreve `precisa-danilo` no e2e_log com a frase "⚠️ ISTO MEXE EM DINHEIRO/DESPACHO. Está tudo pronto — confirma que eu aplico." e segue para o bloco seguinte.

## Regras desta missão (ler antes de tudo)

1. **Nunca pôr o cliente a resolver um problema nosso** (fechar a app, reinstalar, sair da conta). Regra do Danilo de 16/11 17:20. A proteção vem do servidor e da app.
2. **Nunca correr buscas pesadas em paralelo contra a produção** com clientes a usar a app: às 16:43 de 16/11 dois testes de busca ao mesmo tempo derrubaram o login. Testes pesados um de cada vez, e de preferência num ramo da Supabase.
3. **Modo leve no PC:** um ajudante de cada vez, builds e testes pesados no CI; se a memória livre do PC cair abaixo de 1500 MB, para e limpa (fechar o que não é preciso).
4. **O Claude Code nunca fala com o Danilo nem lhe dá passos.** O que precisar dele vai ao e2e_log com estado `precisa-danilo`; quem lho leva é a Claude.ai. Nunca acabes o turno à espera.
5. **Diz o que mexes e porquê** (função, tabela, ecrã). Outro erro encontrado pelo caminho → reporta no e2e_log e no relatório, não corrijas calado.
6. **Publicar = as 3** (Play Store, App Store/TestFlight, web) e provar as 3. Nunca mexer no versionCode. Juntar ao ramo `autonomous-night-2026-04-29` só os ficheiros desta missão (`git add` por caminho).
7. Migração aplicada em produção fica também em `supabase/migrations/`.

## O que aconteceu (diagnóstico feito pela Claude.ai por MCP, 16/11 16:30–17:20)

- O servidor é **Micro** (60 ligações, 1 GB, CPU partilhado). Quando o CPU é martelado, perde força e tudo fica ~10× mais lento.
- Entre 16:33 e 16:40 e outra vez às 16:43: login (GoTrue `/user` e `/token` 504 "context deadline exceeded"), painel admin, heartbeats dos estafetas (`driver_heartbeat_*` 500), pesquisas (`search_products`, `cliente_pesquisar`, `assistant_search_products` cortadas aos 8 s) e o robô amigo ("não consegui pesquisar agora") falharam.
- **Culpado principal:** a app Android da cliente Isabel Rebelo (`4abf0e49-d44b-4356-9e17-9126f5988581`) pedia `GET /rest/v1/orders?select=*&user_id=eq.<ela>&order=created_at.desc.nullslast` em laço: 2/s às 16:20, 5/s às 16:56, **27/s às 17:05** (8160 em 5 min), em rajadas de 5 pedidos iguais ao mesmo milissegundo. Parou sozinho ~17:15. Em 10 min essa consulta ocupou 59% do servidor (`pg_stat_statements`, mean 150 ms; isolada leva 10 ms). A conta do Danilo (`c9fccf85…`) também fez 410 em 5 min às 16:45.
- De ~4,5 em ~4,5 s a app dela fazia o lote inteiro de `_ServerMirrorOnResume.didChangeAppLifecycleState(resumed)` em `lib/main.dart`: `orders`, `users?select=tvde_access`, `tvde_rides` (driver_id / reservation_*), `washers`, `tvde_access_requests`, `appointments`. Ou seja, o "voltar à app" disparava sem parar. Ela usou o modo de voz do Amigo 16:34–16:36, mas o laço já vinha de 16:20.
- As buscas NÃO eram a causa: com o servidor calmo `pesquisa_produtos('vinho branco 1l')` leva 0,6–0,8 s (sob a carga levou 12 s).

## Já feito (não repetir)

- Ramo `ai/2026-11-16-servidor-nao-travar`, **PR #28** (commit `3ce988c9`): (1) `main.dart`: a releitura ao voltar só corre se a app passou por `paused`/`hidden` e no máximo de 15 em 15 s; (2) `OrderStore.loadOrders({force})`: leituras automáticas juntam-se à que está a correr e não se repetem em 5 s; `force: true` depois de ações (cancelar, aceitar, falha de ação do estafeta, aviso de atribuição, folha do favor) e no puxar para atualizar; (3) `_subscribeToOrders` idempotente por conta (`_ordersSubKey`). Juiz anti-trapaça limpo; `zonas_diff` marca `order_store.dart` (autorizado acima). O CI de PR (`build_ios.yml`, job A) foi cancelado por falta de Mac no GitHub; a Claude.ai pediu nova execução.
- Função de teste `public.pesquisa_produtos_teste(text,text,integer,vector)` ficou criada em produção — apagar no B4.

## Blocos

### B0 · Pré-voo
Ler `erros-aprendidos` (as duas páginas), `regras-do-danilo`, `PADRAO_BORA.md`, o último digest. RAM do PC. `git fetch`; trabalhar no ramo `ai/2026-11-16-servidor-nao-travar`. Ver o estado do CI do PR #28 (`gh api repos/nilofulfarotuga-hue/bora-app-cloud/commits/<head>/check-runs`).

### B1 · Fechar a causa na app e publicar
1. `flutter analyze` (0 erros) e `flutter test` (verde) no ramo do PR #28.
2. Achar o gatilho real no Android de `resumed` a cada ~4 s (pedido de permissão em laço depois de "não permitir"? microfone do Amigo? notificação de ecrã inteiro? `trabalho_oferta_overlay_host`?) e a origem das **rajadas de 5 GET iguais** (candidatos: vários `onAuthStateChange` → `loadOrders` acumulados, `client_home_screen.dart:180`, `_revertToGeneralStream` chamado por `updateDriverStore` quando o `currentDriverId` de um cliente oscila, stream do Supabase a religar após erro). Reproduzir no emulador com uma conta de teste de cliente, com o Amigo em voz e uma permissão negada; contar os `GET /orders` dessa conta nos `edge_logs` durante 2 min, antes e depois. Corrigir a causa (não só o sintoma) e meter o teste automático que prove que N eventos de `resumed` em 10 s dão no máximo 1 leitura.
3. Ver as 3 plataformas: Android, iPhone (simulador/TestFlight) e web (no web a "volta" é `hidden`→`resumed`; confirmar que a releitura ainda acontece ao voltar ao separador).
4. Com tudo verde: juntar o PR #28 ao `autonomous-night-2026-04-29` → CI publica. Provar Play (versionCode novo), App Store Connect/TestFlight (build nova) e web (página no ar com a versão nova).

### B2 · Travão para as apps antigas que ainda têm o laço
Quando a versão corrigida estiver aprovada na Play Store e na App Store: subir `app_min_supported_version_code` (Android) e `app_min_supported_version_code_ios` para essa versão (são definições de versão, não de dinheiro). Confirmar no código como a app trata a versão mínima; se só confere ao abrir, passar a conferir também ao voltar à app (no máximo 1 vez por hora). O ecrã de "atualizar" tem de ser claro em PT-PT e levar à loja. Nada de pedir ao cliente por mensagem.

### B3 · Escudo do servidor: uma app avariada nunca mais derruba tudo
O objetivo do Danilo: 10 ou 100 clientes ao mesmo tempo sem travar, e uma app com defeito não pode levar o login, o painel e os estafetas atrás.
1. Medir a carga normal: `pg_stat_statements` (zerado às 16:45:37 de 16/11) por consulta, crons (`cron.job` + duração em `cron.job_run_details`), tempo real (`realtime.list_changes`/subscrições).
2. Proteção por utilizador do lado do servidor, testada primeiro num ramo da Supabase: estudar e, se for seguro, aplicar um limitador por conta (ex.: função `db-pre-request` do PostgREST com tabela sem registo, que **deixa passar em caso de erro** e trava só leituras repetidas da mesma tabela acima de um limite por segundo). Se não houver forma segura, escrever a proposta e o porquê no relatório.
3. Vigia: alerta automático ao Danilo (Telegram, `notify-admin-urgent`) quando uma consulta passar de X% do servidor em 5 min ou o login der 504, com quem/onde. Aparece também no painel admin (PT-BR, paridade).
4. Rever `statement_timeout` de `authenticated`/`anon` (hoje 8 s): propor o valor certo com números.
5. Comparar com dados o custo/benefício do tamanho do servidor (Micro → Small/Medium partilhados, Large com CPU dedicado a ~110 USD/mês): só relatório com números, **não mudar o plano** (é dinheiro do Danilo).

### B4 · Busca mais leve
1. Aplicar como migração a melhoria já testada de `public.pesquisa_produtos`: o `catn` passa a `select distinct coalesce(cand.category, '') as category from cand` e o join `left join catn kn on kn.category = coalesce(c.category, '')` (em vez de `is not distinct from`, que fazia 1,25 M comparações). Provado a 16/11: resultados iguais em 8 buscas (`vinho branco 1l`, `leite`, `frango`, `chocolate fundue`, `batata`, `papel higenico`, `coca cola 1,5l`, `pizza`), 15–25% mais rápido. Manter o `SET pg_trgm.word_similarity_threshold = '0.45'`. Apagar `pesquisa_produtos_teste`.
2. Ver `assistant_search_products` (robô amigo) e `cliente_pesquisar` com `EXPLAIN ANALYZE`, uma de cada vez; meta < 300 ms com o servidor calmo.
3. Na app: a pesquisa espera ~350 ms depois da última letra e cancela a anterior (como a Glovo/Uber Eats), se ainda não fizer.

### B5 · Catálogo do Continente sem descarregar tudo
A app pede o catálogo inteiro do Continente em páginas de 1000 (`offset=0` até `offset=19000`, ~20 mil produtos) cada vez que a loja abre, e a home pede os produtos de 15 restaurantes de uma vez. Mudar para carregar por secção/categoria e por página quando o cliente rola, como a Glovo e a Uber Eats. Medir pedidos e tempo antes e depois. Não tocar preços nem fotos.

### B6 · Crons
Listar todos os `pg_cron` com frequência e duração média/máxima. Os que correm de 15 em 15 s ou de minuto a minuto e pesam (ex.: `tvde_reservations_sweep` máx 28 s, `produtos_esgotados_voltam` máx 17 s, `encomendas_telefone_relogio` máx 26 s, limpeza de `net._http_response` máx 52 s): propor e aplicar a frequência certa nos que não mexem em dinheiro nem despacho; os outros, proposta.

### B7 · Estafeta: vários pedidos de mercado ao mesmo tempo
Pedido do Danilo de 16/11 17:03 (ele é estafeta e tinha 2 pedidos no Continente, da Letícia e da Dona Isabel, e a app só deixa um de cada vez): "faz uma compra, seleciona os pedidos, deixa em stand-by; na caixa um botãozinho de trocar de pedido; passa um, tira a foto de um, passa o outro, tira a foto do outro; depois dá o destino. Ver como os grandes fazem."
1. Pesquisar primeiro como a Instacart e a Uber Eats (mercado) fazem as compras em lote (agente `pesquisa-concorrencia`); não inventar.
2. Fazer: lista de compras única com cada produto marcado pelo pedido a que pertence (cor/letra); **progresso da compra gravado no servidor** (erro de 14/11: o progresso só vivia no telemóvel e perdeu-se); na caixa, botão "Trocar de pedido" → pedido 1: passar, foto do talão, finalizar → pedido 2: o mesmo; no fim, entregas pela ordem do caminho. Cada pedido mantém o seu talão, o seu pagamento e o seu recibo, sem mudar as contas.
3. A parte de oferecer/atribuir um 2.º pedido a um estafeta que já tem um ativo é despacho (zona vermelha): preparar a proposta completa e marcar `precisa-danilo`. Até lá, o 2.º pedido pode chegar pelo painel admin com `ops_reassign_order`.
4. Paridade admin (PT-BR): ver os pedidos agrupados de cada estafeta e o progresso de cada um.
5. Testes de pagamento sempre em dinheiro.

### B8 · Fecho
Provas das 3 plataformas, e2e_log de cada bloco, relatório curto ("fiz isto, falta isto") no e2e_log, digest `digest-2026-11-16-servidor-nao-travar` em `claude_ai_memoria`, lições novas com `livro_aprender`. Terminar com `/ctx doctor` e `/ctx stats`.
