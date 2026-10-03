---
id: memoria-claude-ai-digest-2026-09-23-ios-lancar-102
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-23
zona: verde
confianca: alta
estado: atual
---

# iOS: 1.0.2 lancada e o iPhone passa a publicar-se sozinho

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-23-ios-lancar-102`, origem `claude-code`, atualizada em 2026-09-23T11:43:13.720602+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 23 ios lancar 102 · memoria claude.ai · claude_ai_memoria

O QUE FUNCIONA AGORA
A versao 1.0.2 da Bora esta lancada. A Apple aprovou-a a 22/09 as 22:44 UTC mas ela ficou parada um dia inteiro em PENDING_DEVELOPER_RELEASE: tinha sido criada com lancamento MANUAL e faltava um clique. Lancada hoje pela API (POST /v1/appStoreVersionReleaseRequests) e lida de volta: appStoreState=READY_FOR_SALE, appVersionState=READY_FOR_DISTRIBUTION. ATENCAO: ate 12:10 Lisboa o itunes lookup (id6809954739, pt e br) ainda servia version 1.0 -- a propagacao do CDN da Apple leva ate 2h. Quem for confirmar, confirma pelo lookup ou pelo iPhone, nao pelo painel.

O iPhone deixou de precisar de maos. O build_ios.yml ganhou o input submeter_revisao (ligado por omissao) e, logo a seguir ao altool, corre .github/scripts/ios_publicar.py: espera a build ficar VALID, cria/reaproveita a versao seguinte (nome = maior existente +1 no patch) com releaseType=AFTER_APPROVAL, liga a build, escreve o "O que ha de novo" a partir de ios/notas_de_versao.json e submete por reviewSubmissions. Push -> build -> submissao -> lancamento, sem ninguem carregar em nada; so a analise da Apple faz esperar. Desligar submeter_revisao sobe so para TestFlight. O script le tudo de volta e rebenta o job se a Apple nao ficar como pedido -- um 201 nao prova nada.

COMO SE USA
Continua a ser workflow_dispatch com enviar=true. Nao ha passo novo a fazer a mao. As notas de versao editam-se em ios/notas_de_versao.json (chave por idioma; "padrao" tem pt e en de rede). A ficha da loja so tem pt-PT hoje -- se um dia se abrir en-US, o script apanha-o sozinho sem alteracao.

CONFIRMADO E NAO MEXIDO: CFBundleLocalizations pt-PT+en ja no Info.plist; primaryCategory=LIFESTYLE (Estilo de vida), secondaryCategory=FOOD_AND_DRINK (Gastronomia).

PUSH iOS (H5 da paridade): ha 1 token ios activo em driver_push_tokens (o iPhone do Danilo, iOS 26.6.1). _notify_driver_assigned_http devolveu HTTP 200 {"ok":true,"sent":3,"failed":0} com detail platform:ios ok:true. Armadilha para o proximo: p_type SO aceita order_reassigned, order_preassigned, order_unassigned, driver_offline -- com "generic" a funcao SQL devolve void (parece sucesso) e por baixo e HTTP 400. Ver sempre net._http_response.

O QUE FALTA / AVISO IMPORTANTE
O git push a partir do PC NAO funciona: "Unable to persist credentials with the wincredman credential store" -- o cofre do Windows esta inacessivel na sessao headless e sem TTY o GCM nao abre janela. GCM_INTERACTIVE=always (a cura de 30/08) ja nao resolve, foi tentado. Nao ha gh CLI. Contornei pela VPS (bundle + scp + push do clone com a chave de deploy SSH); script com guarda em provas/ios-lancar-102-20260923/publicar_pela_vps.sh. Qualquer agente que precise de empurrar deste PC deve ir por ai e nao perder tempo com o GCM. Arranjar a credencial e tarefa de sessao interactiva do Danilo.

Commit 8354cf32 no ramo autonomous-night-2026-04-29, com [skip ci] (nada entra no APK Android nem no bundle web). Provas: e2e_log fluxo ios-lancar-102-2026-09-23, 12 linhas.

FECHO (23/09 12:15 Lisboa, segunda passagem da mesma missao). A prova que faltava esta feita: o itunes lookup id6809954739 devolve version=1.0.2 em country=pt E em country=br, currentVersionReleaseDate 2026-09-23T10:54:57Z, nome "Bora - entregas e servicos" e categorias "Estilo de vida, Gastronomia e bebidas". Ou seja, a loja publica ja serve a 1.0.2 e confirma tambem, do lado de fora, o idioma pt-PT e a categoria nova. A propagacao demorou ~14 min (as 11:01 ainda dava 1.0, as 11:08 ja dava 1.0.2), nao as 2 h que se temiam -- quem repetir isto espera uns minutos e rele, nao investiga.

LICAO: o appStoreState=READY_FOR_SALE que a API devolve e o involucro. Quem decide o que chega ao telemovel do cliente e o lookup publico, e ele fica para tras. So as DUAS leituras juntas provam que uma versao esta no ar. A prova ficou como script refazivel em provas/ios-lancar-102-20260923/lookup_no_ar.py (sai 0 se a loja ja serve a versao esperada, 1 se ainda propaga; para a proxima versao muda-se so a constante ESPERADA).

Ferramenta nova: publicar_pela_vps_v2.sh, a mesma coisa do v1 mas parametrizada (<sha> <pai-esperado> [bundle] [ramo]) -- o v1 tinha o SHA cravado no corpo e servia uma vez so. Mantem a guarda que PARA se o ramo se tiver mexido no GitHub. Caminho SSH confirmado: root@srv1786862.hstgr.cloud com ~/.ssh/id_ed25519_vps (o IP Tailscale 100.71.105.7 continua partido).

Commits 897fe0f3 e de79064d, ambos empurrados pela VPS em fast-forward sem --force e lidos de volta. e2e_log do fluxo: 15 linhas.

RESSALVA MEDIDA (reverificacao 23/09 11:43Z, linha 18 do e2e_log): o iPhone ainda nao se publica com um push simples. O job B do build_ios.yml so corre com disparo a mao e enviar=true (if na linha 438: github.event_name == 'workflow_dispatch' && inputs.enviar), e o gatilho de push so olha o ramo ios-lancamento. O que ficou mesmo automatico e tudo o que vem DEPOIS desse disparo: submeter_revisao ja vem ligado por defeito, por isso o CI cria a versao seguinte com AFTER_APPROVAL, liga a build, escreve as notas e submete -- e a loja serve sozinha quando a Apple aprovar. Sobra 1 clique (o disparo) em vez dos 2 de antes. Nao foi corrigido de proposito: por o gate a correr em push faria cada push ao ramo submeter a Apple, e isso e decisao do Danilo.
