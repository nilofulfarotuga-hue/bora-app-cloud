---
id: memoria-claude-ai-livro-areas-play-store-release
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Bora App release pipeline nas 3 plataformas (Play Store/Android, iOS/App Store, web) — CI/CD, regras de paridade, histórico de envios e rejeições

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-play-store-release`, origem `claude-ai`, atualizada em 2026-10-23T05:39:13.911249+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas play store release · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/play-store-release.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: play-store-release
description: Bora App release pipeline nas 3 plataformas (Play Store/Android, iOS/App Store, web) — CI/CD, regras de paridade, histórico de envios e rejeições
sources: [backfill]
aliases: [pt.boraapp.bora]
---
⚠️ ESTADO ATUAL — CORRIGIDO POR ELE A 18/09/2026 (chateado, porque eu disse o contrário): A BORA ESTÁ PÚBLICA na Google Play desde 31/07/2026. Qualquer pessoa a transfere na loja; já NÃO é faixa de teste. NUNCA mais dizer que a Bora está em teste fechado nem que falta esse teste.

⚠️ CORREÇÃO 22/09/2026, com prova no ecrã do painel dele: o acesso à produção é POR APP, não pela conta. A parte antiga desta linha que dizia que nenhuma app nova desta conta precisava de repetir os 12 testadores × 14 dias está ERRADA. No painel da Em Dia a Google mostra "Candidate-se ao acesso à produção" com "0 testadores atualmente a participar" e o botão cinzento; o teste ABERTO também exige acesso à produção (só o interno é livre) e não existe isenção nem recurso. Ele aceitou o facto: "Play Store agora não dá, mas o iPhone dá". A única saída estrutural seria conta de organização com D-U-N-S — a opção "Alteração do tipo de conta" existe no painel dele mas exige validar primeiro um website (pus lá https://boraguarda.com a 22/09).

- [stated] App `pt.boraapp.bora` in closed alpha track with 12 testers (PrimeTestLab)
- [stated] CI now publishes directly to closed 'alpha' track automatically on push (first correct build = 383)
- [stated] `codemagic.yaml` is legacy — do not use
- [stated] Open testing only unlocks after production access, which requires 12 testers × 14 consecutive days of real engagement (emulator/fake accounts don't count)
- [stated] Demo account `demo@bora.app` / `[REMOVIDO]` created via MCP for the Play Console "App access" field
- [stated] Estimated timeline to production request: 16–21 days
- [stated] Candidatura de acesso à produção submetida em 22/07/2026 às 00:27 — Google a rever, resposta em até 7 dias (por vezes mais)
- [stated] ACESSO À PRODUÇÃO CONCEDIDO (confirmado no Painel de Controlo em 28/07/2026) — app pode ir para a faixa de Produção
- [stated] 28/07/2026: a criar o lançamento de produção "1.0" (rascunho), bundle 392 (versionName 1.0.1), 2 países/regiões selecionados; faltava selecionar o bundle e completar as notas <pt-PT> quando delegou a tarefa ao agente de browser
- [stated] Notas de lançamento têm de vir dentro das etiquetas de idioma (`<pt-PT>...</pt-PT>`) senão a Play Console dá erro "texto fora das etiquetas de idioma"
- [stated] 28/07/2026: rascunho de produção "1.0" ficou montado (bundle 498 / versionName 1.0.1, rollout 10%, países PT+BR) mas o envio ficou BLOQUEADO por 2 questões de política: (1) declaração Data Safety inválida — dados transmitidos não declarados; (2) aviso "usar seletores de sistema alternativos para fotos/vídeos" (Photo and Video Permissions), que exige alteração de código Flutter
- [stated] O bundle 392 não serve para o lançamento de produção — já era o bundle da versão ativa da faixa, e incluí-lo gera os erros "não adiciona nem remove app bundles" / "não permite atualização para utilizadores existentes"

CI/CD migration (May 2026)
- [stated] Migrated from Codemagic to GitHub Actions (`build_android.yml`)
- [stated] `DART_DEFINES_FILE_B64` secret for `.dart_defines`
- [stated] Keystore: alias `bora-app`, path `bora-app-release.jks`
- [stated] versionCode auto-incremented by CI — NEVER manually increment in `pubspec.yaml`
- [stated] Google Play service account reused from Codemagic

Web deploy parity (2026-07-20) — see [[bora-app]]
- [stated] PERMANENT RULE: every update that ships to the Play Store must also update the web app — the two ship together
- [stated] ⚠️ REGRA PERMANENTE ALARGADA A 3 PLATAFORMAS (21/09/2026): todo o build tem de ser feito para iPhone, Android E web ao mesmo tempo, e as três têm de ficar IGUAIS — "o que tem em um tem que ter em outro. Tudo, tudo, tudo." Uma release = três plataformas na mesma versão. Nunca mais entregar só Android+web.
- [stated] Web app is live at bora-app-web.pages.dev (Flutter Web, same codebase/Supabase as Android)
- [stated] `build_web_deploy.yml` workflow builds Flutter Web on CI and auto-publishes to Cloudflare Pages on every push to the branch (separate from build_android.yml)
- [stated] CLOUDFLARE_API_TOKEN secret is set in the bora-app-cloud repo (created 2026-07-20), so web auto-deploy is now active — no manual step needed
- [stated] Manual fallback if CI fails: buscar-build-web.sh + deploy-web.sh (the 4GB PC can't compile web locally — DartWorker OOM)
- [stated] gh CLI authenticated on the PC 2026-07-20 via device flow
- [stated] LINK DE ADESÃO AO TESTE (opt-in universal — qualquer Android clica→aceita→instala, sem cadastrar email): https://play.google.com/apps/testing/pt.boraapp.bora. É ESTE que abre/instala; o https://play.google.com/store/apps/details?id=pt.boraapp.bora é só a página da loja e NÃO abre pro público enquanto em teste fechado. Usar o apps/testing em TODOS os CTAs dos mini-sites de parceiros. NOTA: os sites [[ouro-e-prata]] e [[sabores-de-casa]] ainda têm o link /store errado — trocar quando der.
- [stated] 28/07/2026: os 2 bloqueadores foram resolvidos — aviso de fotos/vídeo tinha botão "Continuar mesmo assim" (não impede envio, app pode ser rejeitada nessa política específica na revisão); Data Safety preenchido e guardado com sucesso, aviso "2 problemas encontrados" desapareceu
- [stated] Ao rever antes do envio final apareceram 2 entradas "1.0" na faixa Produção: release 3 (bundle 498, 10%, 2 países) é o rascunho ativo; uma entrada antiga (bundle 392, "implementação completa"/100%) ficou marcada como subordinada ao lançamento mais recente, com "Rejeitar edição" desativado
- [stated] 28/07/2026: lançamento 1.0 (bundle 498) ENVIADO PARA REVISÃO da Google com sucesso — 5 alterações submetidas, rollout confirmado em 10% (não 100%), 2 países (PT+BR), entrada antiga (bundle 392) confirmada inerte (0% base, sem rollout ativo). Aviso de seletor de fotos/vídeo foi contornado com "Continuar mesmo assim" — risco de rejeição nessa política específica na revisão, exigirá migração para o Photo Picker do Android se rejeitado
- [stated] 28/07/2026 19:45: candidatura REJEITADA pela Google — motivo: formulário Data Safety inválido, dados de "IDs de Dispositivo ou Outros" (ex: ID Android, IMEI, MAC) transmitidos mas não corretamente declarados, afetando ambas as versões 392 e 498. Um novo envio ("Envio 120") já aparece registado às 19:46 com estado "Em verificação" — por confirmar se já corrige o problema
- [stated] 29/07/2026: DIAGNÓSTICO REAL da 2ª rejeição (Envio 121, bundle 501) — NÃO era Advertising ID/Data Safety (código confirmado limpo, só firebase_core+firebase_messaging). O motivo real são 2 problemas de LOCALIZAÇÃO EM SEGUNDO PLANO (ACCESS_BACKGROUND_LOCATION, usado pelo estafeta): (1) vídeo de demonstração no YouTube Shorts inacessível/não mostra o fluxo exigido; (2) app não tinha "declaração em destaque" (prominent disclosure) antes de aceder à permissão
- [stated] Correção aplicada: novo widget `background_location_disclosure.dart` ligado nos ecrãs de ficar Online do estafeta (entregas + TVDE), antes de ativar o rastreio. Passou no Juiz (chão anti-trapaça CLEAN) e flutter analyze (0 erros). Commit 5ef866c, push feito, CI a gerar o bundle 503
- [stated] Pendente da parte do Danilo: (1) gravar vídeo novo com o bundle 503 mostrando ficar Online → aparece a disclosure → aceitar → permissão concedida → rastreio a funcionar; subir ao YouTube (não listado); (2) trocar o URL do vídeo antigo (JEyOj7und6M) na Play Console; (3) lançamento de produção tem de usar o bundle 503 (não o 501/498/392, que não têm a disclosure)
- [stated] 30/07/2026: descoberto porque o bundle 503 não chegava ao telemóvel — o CI faz upload com `changesNotSentForReview: true` (necessário desde 28/07, senão a API descartava a edição por causa da produção rejeitada), por isso o 503 ficava atribuído ao alpha mas preso no balde "5 alterações por enviar para revisão". Teste Fechado (alpha) passa por revisão da Google; Teste Interno não passa
- [stated] Não se pode clicar em "Enviar 5 alterações para revisão" — é tudo-ou-nada e arrastaria a Produção 501 (sem disclosure nem vídeo novo) para uma 3ª rejeição seguida, com risco de escalada na conta
- [stated] Correção 30/07: 503 promovido para o Teste Interno (ativo, "Lançamento mais recente: 503 (1.0.1)"). Arranjo durável no CI — `track: alpha` passou a `tracks: alpha,internal` (commit f68ca4c, run 30530662172 a gerar o 504 nos dois tracks), pelo que todo o build futuro chega ao telemóvel de imediato via Teste Interno
- [stated] O separador de Testadores do Teste Interno não chegou a ser lido (Chrome congelou repetidamente — PC de 4GB não aguenta o SPA da Play Console); se o 503/504 não aparecer na Play Store em ~30 min, a lista de testadores internos é o suspeito seguinte
- [stated] Contas de estafeta reais do Danilo (as outras ~23 na tabela `drivers` são lixo de testes automáticos): boraappbora@gmail.com ("Danilo") — é a do telemóvel que ele usa para testar; nilofulfaro@gmail.com ("Danilo Fulfaro") — é a do multimédia do carro. Ambas aprovadas e não banidas. nilofulfarotuga@gmail.com é a conta developer da Play Console e NÃO é estafeta
- [stated] Atenção ao formato do email do telemóvel: `boraappbora@gmail.com`, tudo junto, sem ponto entre "boraapp" e "bora"
- [stated] Login do app é Supabase auth email+password; passwords são hash bcrypt, irrecuperáveis — a única via é redefinir (30/07 as duas contas de estafeta foram repostas via SQL com crypt/gen_salt)
- [stated] 30/07/2026: causa real de o telemóvel nunca ver update — `boraappbora@gmail.com` NÃO estava em nenhuma lista de testadores. Ser dono da Play Console não faz de ninguém testador. Criada a lista `Danilo - teste interno` com esse email e associada à faixa; a lista antiga `testadores bora` (6 emails) ficou intacta. Ambas ✅ na faixa
- [stated] LINK DE ADESÃO AO TESTE INTERNO: https://play.google.com/apps/internaltest/4701744587266345232 — abrir no telemóvel com sessão em boraappbora@gmail.com → "Tornar-me testador" → "Transferir na Google Play". Bundle 504 confirmado ativo na faixa interna (o arranjo `tracks: alpha,internal` do CI funcionou)
- [stated] ARMADILHA PLAY CONSOLE: a Play Console é AngularDart compilado — `get_page_text`/`innerText` NÃO veem a tabela de listas de testadores e devolvem falsamente "zero listas". Só o screenshot mostra a verdade nessa página
- [stated] 30/07/2026: vídeo novo gravado e enviado — https://youtube.com/shorts/Y3R9g-hpHcM (declaração em destaque + permissão "sempre" + rastreio), a substituir o antigo JEyOj7und6M na declaração de permissões sensíveis (localização em segundo plano)
- [stated] 30/07/2026: 3º envio feito com sucesso — Produção ficou só com o bundle 504 a 100% (implementação completa, não mais 10%, para evitar o 501 antigo aparecer nos outros 90%), vídeo novo trocado, Portugal+Brasil mantidos. Estado: "Em revisão" — 5 alterações enviadas, sem erros, banner de rejeição desapareceu. Aguardando resposta da Google (até 7 dias)
- [stated] 31/07/2026: APP APROVADO E PUBLICADO na Google Play Store (Danilo confirmou). Antes de fazer propaganda, pediu limpeza geral do app + regime "a sério" (fim da fase de testes).
- [stated] 31/07/2026 CI FALHOU e foi CORRIGIDO (Claude Code): rebentou na PUBLICAÇÃO, não na compilação. Step `Upload to Google Play (alpha + internal)`, erro exato "Changes are sent for review automatically. The query parameter changesNotSentForReview must not be set." O AAB subiu bem; morria no "Committing the Edit".
- [stated] CAUSA RAIZ: `changesNotSentForReview: true` era um contorno posto a 28/07 (commit 0d27ced) porque havia rejeição de produção pendente. EXPIROU quando a app passou a estar publicada — a Google passa a enviar sempre para revisão sozinha e a API REJEITA o parâmetro. O que era o fix virou a causa. Flag removida (commit 6943639) + comentário no step a avisar para não a repor sem confirmar que há mesmo rejeição pendente. ⚠️ CORRIGE memória anterior desta página que dizia que a flag era necessária.
- [stated] CI VERDE confirmado ao nível do step (run 30665071744): Bump versionCode → success, Build appbundle → success, Upload to Google Play → success. O versionCode 505 nunca ficou registado na Google (edição descartada), o CI bumpou para 506 sem colisão — pubspec não foi tocado, como manda a regra.
- [stated] 🔴 DECISÃO TOMADA pelo Danilo 31/07/2026 (contra a recomendação da Claude.ai, que era manter só alpha+internal): o CI passou a publicar também em PRODUÇÃO. `tracks: internal,alpha,production` + `status: completed`, confirmado ao nível do step na run 30669844090. A PARTIR DAQUI CADA PUSH NESTA BRANCH VAI PARA TODOS OS UTILIZADORES REAIS, A 100%, SEM REVISÃO HUMANA, COM STRIPE LIVE. Tratar todo o push como lançamento — o pré-voo deixou de ser opcional.
- [stated] Rollout faseado NÃO aplicado e porquê (limitação real da action, não preguiça): a action aplica UM único `status` a todos os tracks do mesmo step — `inProgress`+10% travaria também o `internal` e o `alpha`, o oposto do pretendido. Segundo step separado não serve porque o mesmo versionCode é rejeitado. Motivo escrito no próprio workflow.
- [stated] `internal` mantido e listado em primeiro, para o telemóvel do Danilo continuar a receber primeiro.
- [stated] `.github/**` NÃO está no `paths-ignore` do build_android.yml (só `**.md` e `.claude/**`) — mexer no workflow dispara sempre uma build, o que é útil para testar fixes de CI de imediato.

- [stated] 06/10: repetiu e mandou gravar — publicar é SEMPRE Play Store + Apple + web, e todo conserto tem de ser verificado nas três. Pediu auditoria de tudo o que já foi arrumado, a ver o que falta em cada plataforma, com muito cuidado para não estragar o que funciona. PROMPT REGISTADO (histórico): página `prompt-auditoria-3-plataformas-2026-10-06` em claude_ai_memoria, MOTOR FABLE, na mesma sessão do PC (session_01N6YCAfxPPofroZk5Xtibi4) DEPOIS da missão do cartão preso. Estado: entregue à sessão às 19:40 (fica na fila, arranca depois do cartão preso)
