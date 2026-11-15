# Lista para publicar o #19 nas 3 (Play, App Store, web)

Preparado pelo ajudante A da missão fechar-tudo-15-11, sem mexer em nada: só leitura de
git, dos ficheiros do CI, da API pública do GitHub e SELECT no Supabase. Lido a 15/11/2026
entre as 15:05 e as 15:20 (em novembro a hora de Lisboa é igual à UTC). O #19 continua a
receber commits: repetir as verificações marcadas com "repetir" no momento de juntar.

Autorização: o Danilo disse "Pode publicar" às 14:57 (e2e_log 9297): juntar o #19 e
publicar nas 3 quando o CI sair verde e o Juiz 2 aprovar. O Juiz 2 aprovou com consertos
(9313, nota 8/10) e os consertos estão no commit bcb22fe4.

---

## A. Antes de juntar

[ ] A1. Testes do CI verdes no ÚLTIMO commit (repetir)
- No pedido de revisão só corre a "build-ios" (gatilho pull_request para o ramo de
  produção, caminhos lib/, ios/, pubspec.yaml). Faz: análise com 0 erros, testes
  unitários e goldens, compilação para o simulador e o percurso da app com capturas.
  Não assina nem envia nada para a Apple.
- Estado às 15:20: #305 (fd17054c, a cabeça atual) à espera; às 15:07 a #294 (4ecba043)
  ainda estava a correr, já com análise e testes verdes. As #296 a #304 foram canceladas:
  cada commit novo cancela a corrida que estava à espera. Última verde inteira: #289
  (7d2196b8), acabou às 14:11.
- A ordem do Danilo fala na "302". Essa foi cancelada (entrou um commit novo). A que conta
  é a corrida do commit que se vai juntar. Cada corrida demora cerca de 1h40 a 2h.
- O autoteste do Android (emulador com cliente, estafeta e parceiro demo) NÃO corre no
  pedido de revisão, só depois de juntar. Para o ver antes, correr à mão o workflow
  "Build Android & Deploy to Google Play" escolhendo o ramo ai/2026-11-15-app: o envio
  para a Play está preso ao ramo de produção (condição `if` do job build), por isso só
  corre o autoteste. Leva cerca de 30 minutos.
- CUIDADO, nunca fazer: correr à mão o "Build & Deploy Web (Cloudflare Pages)" num ramo
  que não seja o de produção (não tem trava de ramo e publica direto no site); correr o
  build-ios à mão com "enviar" ligado fora do ramo de produção (envia e submete à Apple).

[ ] A2. Juiz 2: feito (9313). Se entrarem mais commits de código depois do fd17054c
  (por exemplo os botões da Área do parceiro, registo 9320), esses também passam pelo Juiz.

[ ] A3. Notas do iPhone: trocar o `ios/notas_de_versao.json` pelo texto da
  NOTAS_DA_VERSAO.md (parte 2). Hoje tem o texto da 1.0.43; sem a troca, a 1.0.44 repete-o.
  Fazer no mesmo envio dos últimos consertos para não gastar mais uma volta de CI.

[ ] A4. Servidor: o que a app nova usa e ainda não está publicado (conferido às 15:20 por
  SELECT em pg_proc e schema_migrations e pela lista de Edge Functions)

  Antes de publicar (pedido no registo 9278):
  - Caixa 29, Edge `admin-sync-user-name`: não existe no servidor. Sem ela, quando o apoio
    muda o nome de um cliente no painel, o cliente continua a ver o nome antigo na app. A
    app não rebenta: o erro é apanhado.
  - Caixa 52, Edge `ocr-receipt` (robô do talão, 3 ficheiros e os `_shared` do mesmo
    commit): no ar está a v24 de 11/11; as correções de 14 e 15/11 não estão publicadas.
  - Caixas 30 e 31, Edge `client-cancel-order` (dinheiro, C1): no ar a v40 de 02/11.
    Autorizada pelo Danilo a 15/11 às 08:50 (bloco C), só com testes verdes.
  - Caixa 32, Edge `stripe-webhook` (dinheiro, C3): no ar a v48 de 09/11. ANTES dela entra
    a migração C3 (`docs/propostas/manha-15-11/C3-20261115100000_reconsumir_tokens_pedido_reativado.sql`):
    a função `reconsumir_tokens_pedido_reativado` não existe e o webhook novo chama-a
    (linha 461 do ficheiro final).
  - Caixa 33, farmácias (SQL): `farmacia_prescricao_fechar_demo`,
    `admin_farmacia_chegadas_listar` e `admin_farmacia_lembretes_listar` não existem. A app
    aguenta: o botão "Marcar como levantado" das farmácias de demonstração diz que a parte
    não está instalada.
  - Caixa 51, Edge `delete-account`: no ar a v33 de 07/09. Sem ela, quem tem uma limpeza
    "cancelada sem prestador" não consegue apagar a conta.
  - Antes de publicar cada Edge de dinheiro (30, 31, 32), guardar a versão que está no ar
    (ler com get_edge_function) para poder voltar a ela.

  Pode ser depois (a app avisa que a parte não está instalada):
  - Caixa 48 (SQL dos achados do vigia de pagamentos sem repetidos): não aplicada (não
    existe a cópia `bkp_payment_reconciliation_findings_20261115`).
  - Caixa 49, Edge `payments-reconciler`: no ar a v17 de 02/11.
  - Caixa 50 (aprovar várias sugestões): `admin_bulk_approve_skill_suggestions` não existe
    e o painel chama-a.
  - Caixa 63: aplicada às 15:00 SEM a P5.3 (migração `area_estafeta_p5_sem_p53`); falta
    `admin_revogar_sessoes`.
  - Caixa 64, Edge `admin-force-driver-logout`: no ar a v21 de 29/04; precisa da P5.3 antes.

  Já aplicado e conferido: caixas 25 a 27 (31 trechos de ajuda indexados), 39 a 44, 45
  (coberta pela migração `seguranca_rls_tabelas_bkp_20261115`), 46 e 47, 53 a 55, 58 a 60,
  61 (client-assistant v26), 62 (Central do robô), 66 (Loja Online, com
  `loja_online_ativa = false`), 67 (P6, as 7 funções da Área do parceiro) e a migração do
  reembolso de pedido recusado pela loja (as duas às 15:12 pela hora do servidor; o
  registo 9318 cita o "Autorizo tudo" do Danilo para elas).

[ ] A5. iPhone: confirmar que não há nenhuma versão em análise na Apple
  ("Waiting for Review" ou "In Review"). Hoje a 1.0.43 está à venda desde 15/11 00:40
  (prova pública: https://itunes.apple.com/lookup?id=6809954739&country=pt). Se houver
  uma versão em análise, a build nova fica só no TestFlight e não é submetida.

[ ] A6. Escolher "Create a merge commit" no botão do GitHub (não "Squash" nem "Rebase").
  Assim, voltar atrás é desfazer um só commit (ver parte D).

---

## B. A junção

- Conflitos: nenhum. `git merge-tree --write-tree origin/autonomous-night-2026-04-29
  origin/ai/2026-11-15-app` acabou com saída 0 e sem nenhuma linha CONFLICT (com a cabeça
  fd17054c). O GitHub diz mergeable = true, mergeable_state = clean.
- O ramo de produção não anda desde 14/11 às 18:22 (219b5a97, "ci: bump versionCode to
  732"). O #19 está 93 commits à frente e 0 atrás: nada de produção fica por trás.
- Tamanho: 292 ficheiros, mais 42 831 linhas e menos 1 559.
- Não toca em pubspec.yaml, android/, ios/ nem .github/. O versionCode continua a ser do CI.
- O ramo de produção não está protegido no GitHub (protected = false): nada impede juntar
  com testes vermelhos. A trava é só a nossa regra.
- Linhas novas sem segredos (conferido na cabeça fd17054c): procurei chaves da Stripe,
  tokens JWT, chaves Google, GitHub, AWS e Supabase; zero. As migrações que chamam o
  servidor leem a chave do cofre (`vault.decrypted_secrets`) na hora, não a escrevem. Os
  emails do Danilo que aparecem já existiam em mais de 100 ficheiros do ramo de produção.
- Repetir no momento de juntar (só leitura):
  `git fetch origin autonomous-night-2026-04-29 ai/2026-11-15-app`
  `git rev-list --left-right --count origin/autonomous-night-2026-04-29...origin/ai/2026-11-15-app`
  `git merge-tree --write-tree origin/autonomous-night-2026-04-29 origin/ai/2026-11-15-app`

O que viaja junto, de outras sessões e não só desta:
- #18 fechar-app (noite de 14/11): compra guardada e fila do estafeta, MB WAY do lado da
  app, vigia dos pedidos presos e lembretes (`ferramentas/vps/*.py`). Os scripts da VPS
  não vão sozinhos para a VPS: só contam quando forem copiados para lá.
- #20 manhã: nome só pelo apoio, MB WAY C1 e C3 (a parte da app; o servidor está pendente,
  ver A4), código dos robôs (já publicados pela Claude.ai às 13:19 e 14:01), ajuda pública
  (`docs/ajuda`), e conteúdo de IA: 400 roteiros em `docs/conteudo-ia/roteiros` e a
  migração `conteudo_ia_fila`. Isto é da fábrica de conteúdo, não da app da Bora. Não
  entra na app (docs/ não vai para o build e a migração não está aplicada), mas fica no
  repositório da app.
- app-15-11, painel-admin-15-11 e fechar-tudo-15-11: painel (Conversas ao vivo, Área do
  estafeta, Área do parceiro, Central do robô, Loja Online desligada, "Para que serve"),
  farmácias, varredura, textos PT-PT, 40 propostas em `docs/propostas`, e o alinhamento
  das migrações com o servidor (fd17054c).
- Relatórios em `.claude/.ai/reports`, com uma imagem
  (`editar-perfil-2026-11-11/web-fuku-caixa-mix-36-24-73.png`): vi-a, mostra só um
  produto e o preço, sem dados pessoais.
- Duas migrações ficam no repositório SEM estarem aplicadas (o próprio commit fd17054c
  diz isso): `20261115023000_bkp_tabelas_fechadas.sql` (substituída pela
  `20261115085052_seguranca_rls_tabelas_bkp_20261115`) e `20261115110000_conteudo_ia_fila.sql`.
  Nada da app as usa. Nunca correr "supabase db push" com este repositório sem tirar
  estas duas primeiro.
- Nenhum workflow publica funções do servidor nem migrações. O servidor só muda pela mão
  da Claude.ai.

---

## C. Depois de juntar, loja a loja

Os três workflows arrancam ao mesmo tempo e são independentes: se um falhar, os outros
publicam na mesma. Tempos da última publicação (14/11 17:51): web 2,5 minutos; Android
40 minutos; iPhone 2 horas e 5 minutos.

### Web (Cloudflare Pages, projeto bora-app-web, endereço app.boraguarda.com)
O que faz sozinho: constrói a web, carimba o `versao.json` com o commit, guarda uma cópia
no ramo `web-build` e publica no site.
Provar:
[ ] https://app.boraguarda.com/versao.json mostra o commit da junção (hoje mostra 9323c040,
    de 14/11 17:53).
[ ] https://app.boraguarda.com/apagar-conta mostra o título "Apagar a tua conta Bora".
    Atenção: HOJE esse endereço já responde 200, mas com a app, porque a Cloudflare devolve a
    app para páginas que não existem. O 200 não prova nada; tem de aparecer o texto. O
    endereço com ".html" é redirecionado (308) para "/apagar-conta", como já acontece com
    "/fiscalizacao.html".
[ ] Entrar como cliente demo, fazer um pedido com pagamento em dinheiro e ver o seguimento.
[ ] Painel: entrar com a conta de administrador e abrir Conversas ao vivo, Área do
    estafeta, Área do parceiro, Central do robô, Loja Online (tem de dizer desligada) e
    Saúde da web.
[ ] Depois de o texto aparecer: pôr https://app.boraguarda.com/apagar-conta na Play
    Console, no perfil do Chrome da Bora (Conteúdo da app, Segurança dos dados, pergunta
    do link para eliminar a conta). Hoje o link registado é o da função do servidor, que
    responde 401 à Google.

### Android (Google Play)
O que faz sozinho:
1. Autoteste no emulador com cliente, estafeta e parceiro demo (cerca de 30 minutos).
   Se falhar, não envia nada para a Play (mas a web e o iPhone seguem).
2. Sobe o versionCode para 733 (commit "ci: bump versionCode to 733 [skip ci]" no ramo
   de produção), constrói e envia para as faixas internal, alpha e produção, a 100%
   (status completed). A Google ainda revê a produção (pode levar horas).
3. Grava `app_latest_version_code = 733`. O aviso "há versão nova" aparece logo nos
   Android com a 732, mesmo antes de a Google aprovar a produção. Já era assim; não bloqueia.
- Novidades: o CI não envia texto (o passo de envio não tem pasta de notas), e a página
  pública da Play não mostra secção de novidades. Ou fica sem texto, como as versões
  anteriores, ou põe-se o texto da NOTAS_DA_VERSAO.md (parte 1) à mão na Play Console, se
  a consola deixar. Pôr o CI a enviar o texto é mudar o CI: não fazer à pressa.
Provar:
[ ] Corrida verde com os passos: autoteste, bump, upload e aviso.
[ ] `select value from platform_settings where key = 'app_latest_version_code'` dá 733.
[ ] Play Console: versão 733 nas faixas internal, alpha e produção.
[ ] Num Android pela faixa interna (chega primeiro): os passos da lista comum, no fim.

### iPhone (App Store Connect e TestFlight)
O que faz sozinho:
1. Job A no simulador (cerca de 1h40): análise, testes e capturas.
2. Job B (cerca de 25 minutos): confere os segredos de assinatura (existem: a corrida
   #272 de 14/11 passou nesse passo e enviou), pede o perfil à Apple, constrói o IPA com
   o número da corrida, envia para o App Store Connect (fica no TestFlight), cria a versão
   seguinte à maior que existe (1.0.44, se não houver já outra depois da 1.0.43) com
   lançamento automático depois da aprovação, escreve as notas do
   `ios/notas_de_versao.json` e submete para revisão.
3. Se já houver uma versão em análise, a build fica só no TestFlight e o passo acaba
   verde com o aviso "fica no TestFlight" (ver A5).
4. O aviso de versão nova nos iPhones só liga quando a Apple publicar (vigia
   `ios_aviso_versao`, que corre de meia em meia hora; última corrida verde às 08:28).
Provar:
[ ] Corrida verde com os passos "Enviar para o App Store Connect" e "Versão seguinte com
    lançamento automático + submeter".
[ ] App Store Connect: 1.0.44 em "Waiting for Review", com a build nova e as notas novas.
[ ] TestFlight: instalar num iPhone e fazer a lista comum; no iPad, tocar em Partilhar.
[ ] Depois da aprovação: o lookup acima mostra 1.0.44 e
    `app_latest_version_code_ios` passa a ter o número da build nova.

### Lista comum (nas 3, só com contas demo)
Os gatilhos de demonstração estão ligados (conferido por SELECT:
`a_trg_pedido_demo_caixa_fechada`, `a_trg_pedido_demo_zz_loja_escondida`,
`a0_trg_demo_loja_sem_entrega`): o pedido de uma conta demo fica marcado como teste e em
dinheiro e não chama estafetas reais. Pagamentos de teste sempre em dinheiro.
[ ] Entrar e sair com cliente, estafeta e parceiro (também com o Google).
[ ] Cliente: pedido em dinheiro; Editar perfil (só o telemóvel muda; o nome manda para o
    apoio); conversa do Amigo abre; o botão Cancelar só aparece quando dá para cancelar.
[ ] Estafeta: ficar disponível, aceitar, ver o ganho em grande, marcar produtos numa
    compra (aparece "Guardado"), ver "Entregas" por período.
[ ] Parceiro: entrar sem ficar preso, aceitar o pedido, marcar pronto.
[ ] Painel abre (web).
[ ] Perfil, Apagar conta: o botão aparece (não carregar com conta real).

---

## D. Voltar atrás, se for preciso

Web: a Cloudflare guarda as publicações anteriores. No painel da Cloudflare (perfil da
Bora), projeto bora-app-web, Deployments, escolher a de 14/11 (commit 9323c040) e
"Rollback". Demora segundos. Reserva: o artefacto `bora-web-build` da corrida #280 fica
guardado 7 dias. Não usar "Run workflow" da web noutro ramo.

Android: a Play não deixa voltar a uma versão antiga e, com envio a 100%, não há travão.
O caminho é publicar outra por cima: desfazer o commit de junção no ramo de produção
(`git revert -m 1 <commit da junção>`: é um commit novo, não reescreve nada) e enviar. O
CI faz a 734 com o código antigo e manda para as mesmas faixas (outra revisão da Google).
Nunca pôr a árvore inteira igual à 219b5a97: isso baixava o pubspec para 732, o CI
voltava a fazer a 733 e a Play recusa um número repetido.

iPhone: antes da aprovação, no App Store Connect, tirar a 1.0.44 da revisão; a 1.0.43
continua à venda. Para trocar a build de uma versão em análise: tirar da revisão (fica
"Developer Rejected", que o script reaproveita) e correr outra vez. Depois de publicada,
não há volta: o mesmo `git revert` faz o CI enviar e submeter a 1.0.45 com o código
antigo; se for grave, pedir revisão acelerada à Apple.

Servidor: não volta atrás com a app. O que foi aplicado hoje fica. Se uma Edge de
dinheiro (30, 31, 32) der problema, volta-se a publicar a versão anterior dela, guardada
antes (ver A4).

---

## E. Ordem recomendada

1. Últimos consertos com o Juiz, e as notas do iPhone no mesmo envio (A2, A3).
2. Servidor: caixas 29, 52, 33 e 51; e 30, 31 e 32 (com a migração C3 antes da 32), só
   com testes verdes e guardando antes a versão no ar de cada uma (A4).
3. build-ios do último commit verde; se possível, também o autoteste Android à mão no ramo (A1).
4. Confirmar que não há versão do iPhone em análise (A5).
5. Juntar com "Create a merge commit" (A6).
6. Web (cerca de 3 minutos): provas e o link na Play Console.
7. Android (cerca de 40 minutos): provas.
8. iPhone (cerca de 2 horas): provas; depois da aprovação, o lookup e o aviso.
9. Registar no e2e_log e no digest da sessão.
