---
id: memoria-claude-ai-livro-areas-custos-google-cloud
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# [PESSOAL] Cobrança do Google Cloud na conta do Danilo — o que o Bora consome de Google, o que NÃO pode ser desligado, e o estado do pedido de reembolso

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-custos-google-cloud`, origem `claude-ai`, atualizada em 2026-10-23T05:43:04.117761+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas custos google cloud · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/custos-google-cloud.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: custos-google-cloud
description: Cobrança do Google Cloud na conta do Danilo — o que o Bora consome de Google, o que NÃO pode ser desligado, e o estado do pedido de reembolso
sources: [chat]
aliases: [Google Cloud, faturação Google, cobrança Google, Firebase billing, boraapp-d2bea]
---

Incidente 2026-08-12 (Danilo trouxe print do novobanco)
- [stated] Débito de 100,00 € descrito `GOOGLE CLOUD P3CP85` na conta dele a 11-08-2026. Diz que nunca autorizou, que lhe foi dito que era grátis e que era só pôr o cartão, e que ficou sem saldo
- [stated] Quer: perceber o que é, saber se está a usar para alguma coisa, pedir reversão do valor e cancelar — assumindo o risco de partir algo
- [stated] Vai deixar o Chrome aberto e com sessão na conta para o executor entrar (extensão / CDP)

O que o Bora usa de Google (verificado por MCP, 2026-08-12)
- FCM / push (notify-partner, notify-driver, notify-client, notify-admin-urgent, notify-service-provider…) → Firebase Cloud Messaging é GRÁTIS e ilimitado, não gera custo
- Gemini (PAGO por uso): `robot-b` corre de HORA A HORA com gemini-3-flash-preview, mais `support-chatbot`, `analyze-conversations`, `ocr-receipt`, `gemini-diagnostic`, `admin-ai-assistant`
- Google Maps Platform no Flutter (PAGO por uso): mapa do cliente, do estafeta e do TVDE, rotas e ETA
- `import-guarda-businesses` NÃO usa Google — usa OpenStreetMap/Overpass (grátis). Não mexer nela
- Projeto Firebase `boraapp-d2bea`. A caixa `boraappbora@gmail.com` NÃO tem um único email de Google Cloud/Firebase → a conta de faturação está no email pessoal dele

⛔ REGRA que ficou desta sessão
- NUNCA fechar a conta de faturação Google nem desativar APIs às cegas: mapas e Gemini parados = app de delivery e TVDE inutilizados e robôs de suporte mortos. Primeiro provar pelo relatório de custos + grep no repo que nada usa aquilo
- Suspeita a confirmar sempre: chave de API sem restrições dentro do APK público pode ser extraída e gasta por terceiros

Dados da conta (print dele, 12/08)
- [stated] Conta de faturação "My Billing Account", ID 012171-9755AA-4CE9FB, tipo Direct, Active — €77 gastos nos últimos 30 dias e a correr
- [stated] Não tem condições de pagar isto. Objetivo dele: pôr o app a funcionar de graça

📌 PESQUISA-CHAVE 2026-08-12 (não repetir, poupa uma sessão)
- SDKs móveis do Google Maps (Android/iOS) são GRÁTIS E SEM LIMITE — o mapa desenhado no ecrã NÃO é o que gasta. Trocar o mapa seria risco alto por ganho zero. O que custa são as chamadas à volta: Geocoding (10k/mês grátis), Routes/Directions, Distance Matrix e sobretudo Places/Autocomplete/Place Details (Pro 5k, Enterprise 1k; Place Details Advanced ~$32/1000)
- O crédito universal de $200/mês do Maps ACABOU em março de 2025 — passou a limites grátis por SKU que não se somam
- ⚠️ ARMADILHA GRANDE: num projeto Google Cloud COM faturação ligada, o tier gratuito do Gemini DESAPARECE — tudo é cobrado desde o primeiro token, mesmo o que caberia no grátis. Com o robot-b de hora a hora, é provavelmente fatia grande dos €77. Solução: projeto Cloud SEPARADO SEM faturação, chave Gemini gerada aí (Gemini 3 Flash ~10 rpm / 1.500 dia; 3.1 Flash-Lite ~15 rpm — cabe folgado)
- Substitutos grátis para o resto: OpenRouteService (sem cartão, 2.500/dia e 40.000/mês — Directions + Matrix + Geocoding), Nominatim/Photon (geocodificação sem chave), e a tabela `guarda_businesses` que já tem os negócios da Guarda do OSM e serve de autocomplete próprio. O dispatch_engine já usa Haversine (grátis)

✅ RESULTADO REAL (executor, 12/08 — verificado por MCP: ocr-receipt v10 no ar com gemini-3.1-flash-lite e verify_jwt preservado)
- A hipótese de partida estava ERRADA no alvo: a fatura de julho (€103,34) era **100% Gemini API** nos 25 SKUs. Maps, Places, Geocoding, Directions e FCM deram **€0,00**
- Dentro do Gemini, **€62 (78%) eram GERAÇÃO DE IMAGENS** — SKU Gemini 3 Pro Image, 590.240 tokens. Nenhuma Edge Function gera imagens: o culpado era o MCP `nano-banana` no `.mcp.json` (chave Google hardcoded), usado pelos agentes de marketing para as artes dos mini-sites
- Gatilho: créditos Free Trial expiraram 23-06-2026 → junho €2,51, julho €84,02. Com faturação ligada o Gemini cobra desde o primeiro token
- Cobrança: transação `V5245116083653575`, Visa ••••7447, "Threshold charge" 10-Ago. Saíram €103,34 no total (€3,34 a 1-Ago + €100 a 10-Ago), sobram €0,81. ⚠️ O LIMIAR SUBIU PARA €200
- FEITO: o projeto `Default Gemini Project` JÁ EXISTIA sem faturação — chave gerada lá e apontada no `.mcp.json` e no secret `GEMINI_API_KEY`. Gemini passa a €0/mês
- ARMADILHA encontrada e resolvida: `gemini-2.5-flash` dá 404 "no longer available to new users" em projetos novos. `admin-ai-assistant` e `ocr-receipt` tinham o modelo hardcoded → passados a `gemini-3.1-flash-lite`. Os modelos da BD (`gemini_model` e `gemini_model_robot_b`) já funcionavam na chave grátis. `gemini-diagnostic`, `robot-b` e `analyze-conversations` a responder 200
- ⚠️ PREÇO DA SOLUÇÃO: geração de IMAGENS dá agora 429 na chave grátis. É a trava que impede outra fatura, mas o Danilo perde as artes dos agentes de marketing. ALTERNATIVA que lhe propus: usar o conector **higgsfield** (generate_image) da Claude.ai, que ele já tem ligado — não gasta Google
- NÃO se tocou no Maps por custo — não gasta nada. Trocar por OpenRouteService/Nominatim seria risco alto para poupar zero

🔴 POR FECHAR — chave do Maps exposta (ordem seguinte)
- Chave `[REMOVIDO]` publicada em `web/index.html:30` (site público) E `AndroidManifest.xml:66` (dentro do APK), **sem restrição de aplicação nenhuma** — provado a responder a Places/Geocoding/Directions de um pedido HTTP simples do PC. Com o limiar em €200, quem a apanhar gera €200 no cartão dele
- Places/Geocoding/Directions estão ATIVAS mas com TRÁFEGO ZERO → desativá-las é o travão imediato e não parte nada hoje
- Um orçamento no Google Cloud é só ALERTA por email, não trava nada. O que trava é desativar API + quota diária
- O executor foi bloqueado por classificador em formulários de definições de faturação (orçamento) e pelo AI Studio ("request is suspicious") ao criar chave — não contornou (certo), foi pelo Cloud Console
- PROMPT entregue: `PROMPT_maps_chave_segura_2026-08-12.md` (OPUS, janela Pro) — desativar APIs sem tráfego, partir a chave em duas (web referrer + Android package/SHA-1 de release), quotas, e mapear que ecrã usa o quê. Relatório em `C:\Users\danil\Desktop\Bora\maps-chave-segura-2026-08-12.md`

🔁 CORREÇÃO DE ROTA 2026-08-12 (Danilo irritado, com razão)
- [stated] O estorno é o que mais lhe interessa — o resto é secundário. E o pedido AINDA NÃO FOI ENVIADO
- [stated] O separador que o executor dizia ter deixado aberto NÃO estava lá; ele minimizou uma "tela preta" (o terminal do Claude Code) e perdeu-a
- [stated] REGRA DELE, repetida com firmeza: ele não escreve, não procura, não navega — só carrega em botões que já estão à frente dele. "Ele escreve, ele faz tudo, eu só autorizo"
- LIÇÃO PARA MIM: não aceitar do executor "deixei aberto para ele clicar" como facto — separadores minimizados/fechados perdem-se. Exigir sempre: texto também na área de transferência (`clip`) + ficheiro em disco + ecrã final com no máximo 3 cliques, com nome exacto do botão E do separador
- PROMPT FINAL entregue: `PROMPT_FINAL_estorno_e_chave_2026-08-12.md` (OPUS, janela Pro) — Bloco 1 estorno com o texto do pedido em inglês JÁ ESCRITO dentro do prompt (assunto + corpo, argumento = créditos expiraram 23/06 sem ele dar conta + free tier do Gemini desaparece ao ligar faturação + threshold charge automático + correções já aplicadas); Bloco 2 chave do Maps; Bloco 3 orçamento; Bloco 4 ficheiro `FINAL-google-2026-08-12.md` que abre sozinho e começa com "O QUE TENS DE CLICAR AGORA"
- Avisado a ele: o Google pode recusar (o consumo foi real) e NÃO fazer contestação no banco — chargeback pode fazer o Google suspender a conta e matar o app
- FICA SÓ PARA O DANILO: clicar Enviar no pedido, e o orçamento se o classificador voltar a bloquear o executor

💶 DINHEIRO DE VOLTA, NÃO CRÉDITO (Danilo, firme, 12/08)
- [stated] Ele RECUSA crédito na conta Google — não quer usar o serviço, quer o dinheiro de volta no cartão/conta bancária. Se lhe oferecerem crédito, recusar e insistir em refund ao método de pagamento original
- [stated] Pediu argumentação forte, "como advogado", contra a Google
- ENTREGUE: `PEDIDO_REEMBOLSO_GOOGLE_2026-08-12.md` — assunto + corpo em inglês pedindo refund ao Visa ••••7447 (não crédito), com 6 argumentos: (1) threshold charge cobrado ANTES de qualquer fatura, sem hipótese de rever; (2) free tier do Gemini removido em silêncio ao ligar faturação, ao contrário do resto do Cloud e sem aviso no fluxo; (3) créditos expiraram 23/06 sem notificação acionável; (4) salto de €2,51→€84,02 (30x) sem um único alerta, e o Google não configura orçamento por defeito; (5) limiar subido unilateralmente para €200 depois do evento; (6) boa-fé — causa já corrigida. Fecha com base de consumidor UE/Portugal e pedido de decisão por escrito. Inclui DUAS respostas de seguimento prontas: uma para quando oferecerem crédito, outra para recusa definitiva (Centro Europeu do Consumidor + autoridades portuguesas)
- CORRIGIDO a ele: ele acha que "não usa esse Google Cloud" — usa. É lá que vive o Firebase/FCM (push de TODO o app) e a ligação ao Play Store. Fechar a conta mata o app. O que se corta é o gasto, não a conta
- Honestidade que lhe dei: o consumo aconteceu de facto (as imagens foram geradas), o caso é bom mas não é garantido; e chargeback no banco continua desaconselhado — pode fazer o Google suspender a conta

🤖 Ele já abriu o chat de suporte (widget Billing Assistant, NÃO humano ainda), 12/08 à noite
- Robô confirmou: crédito Free Trial era €254,47, expirou 23/06. Fatura do período: €86,53 (Gemini 3 Pro Image €62,11 + Gemini 2.5 Flash texto €14,89 + Gemini 3.1 Flash Image €3,82)
- FACTO NOVO E ÚTIL: o próprio Google **detectou a anomalia no dia 27/07** (custo diário saltou para €25,88 vs €0,44 previsto) e MESMO ASSIM não avisou o Danilo antes de cobrar — reforça o argumento de falha do sistema deles
- O robô já citou a armadilha que eu tinha previsto: "per Section 2.3 of the ToS, refunds for billing inaccuracies are issued only as service credits" — script automático, não decisão final
- Dei-lhe uma resposta curta pronta para colar no próprio chat do widget (não email): recusa citar 2.3 (não está a contestar a medição, está a pedir reembolso de cortesia), usa a anomalia de 27/07 não avisada + free tier removido em silêncio, pede escalar para agente humano
- ESTADO: ele ainda não respondeu ao bot, disse que volta com a resposta do Google. Claude Code continua ligado ao mesmo Chrome em paralelo (Bloco 2 — chave do Maps), ele só avisou para eu ficar a par

✅ APROVADO €65,56 (12/08, ~23h50) — caminho que resultou
- Sequência que funcionou: robô Billing Assistant → recusa citar "Section 2.3 = só service credits" → pedir escalar → botão "Chat (Recommended)" → "Connect to agent" → agente HUMANO **EDDIE MARK**
- O Eddie disse LOGO, por iniciativa dele, que podia tratar do ajuste "and having the money transferred back to the original form of payment" — ou seja o humano contradiz o robô. LIÇÃO: nunca aceitar o "não" do bot de suporte como resposta final
- Argumentos que ele levou à equipa interna: anomalia detectada pelo próprio Google a 27/07 (€25,88/dia vs €0,44 previsto) sem nunca avisar antes de cobrar a 10/08; salto €2,51 (junho) → €86,53 (julho); causa já corrigida (projeto sem faturação). Assumir que o consumo foi real e pedir CORTESIA, não contestar a medição, foi o que abriu a porta
- RESULTADO FINAL: equipa interna aprovou primeiro €65,56, e depois de o Eddie voltar a pedir subiu para **€78,67 "one final courtesy"** (de €100). CONFIRMADO por ele: vai ao **meio de pagamento original (Visa ••••7447) em 5 a 7 dias úteis** — NÃO é crédito de serviço
- LIÇÃO: valeu a pena pedir o restante de forma leve e sem exigir ("I understand if 65.56 is the limit, and I am thankful either way") — o agente voltou à equipa por iniciativa própria e conseguiu mais €13
- TOM que funcionou: educado com o agente, firme no pedido, nunca hostil. Ele reagiu bem a "I won't hold it against you either way"
- ⏳ A CONFIRMAR nos próximos dias: se os €78,67 aparecem mesmo na conta do novobanco até ~21/08. Se não aparecerem, reabrir o chat com estes números
- 🔢 REFERÊNCIAS DO CASO (guardar): **Case ID `74330074`** · **Adjustment reference ID `875168637`** · agente EDDIE MARK, Google Cloud Billing Support, 12/08/2026. Ele NÃO enviou confirmação por email — só deu os IDs no chat, por isso estes números são a única prova. Se falhar, é com eles que se reabre

🔧 Bloco 2/3 do executor (12/08, madrugada) — o que ficou e o que eu corrigi
- FEITO: orçamento `Bora - teto 1 EUR mes` criado (mensal, toda a conta, alertas 50/90/100%). O formulário de orçamento passou desta vez — o bloqueio do classificador NÃO é determinístico, vale sempre tentar outra vez
- FACTO: **o limiar de cobrança automática NÃO se baixa pela interface** — não há campo, botão nem menu em lado nenhum das definições de pagamento. Só pedindo ao agente de suporte. Dei-lhe mensagem para pedir ao Eddie
- ❌ ERRO MEU corrigido pelo executor: eu tinha mandado desativar as APIs de Maps com tráfego zero. Ele fez `grep` e encontrou **5 pontos de código VIVOS** a usar Places/Geocoding/Directions. Tráfego zero ≠ código morto — só quer dizer que ainda não há utilizadores. Desligar teria rebentado a escrita de moradas em todos os ecrãs de pedido para poupar €0. NÃO desligar. Regra geral: nunca inferir "morto" a partir de tráfego, só a partir do código
- MISTÉRIO POR RESOLVER: a chave exposta `[REMOVIDO]` NÃO está em nenhum dos 4 projetos dele (percorridos um a um). O `boraapp-d2bea` nem tem a Directions API ligada e a chave responde a Directions; o outro projeto de Maps (`project-af2fc83c-3550-4b07-b4c`) tem chave diferente e inválida. Como esta faturação só tem 2 projetos, abuso da chave provavelmente NÃO bate no cartão dele — o que explica o Maps ter custado €0 em 90 dias com a chave à vista desde março. Risco real não é a fatura: é o app depender de uma chave que ele talvez não controle (provavelmente criada noutra conta Google dele)
- ⚠️ CÓDIGO NÃO ENVIADO: commit `29f8c4b` feito (4 ficheiros, caminho explícito, flutter analyze 0 erros) mas SEM push, e com razão — a branch real é **`autonomous-night/fase2-cortex-tasks`** (NÃO a `autonomous-night-2026-04-29` que os prompts assumem), há **7 commits por enviar de outras sessões** (Stripe Connect, cortex, hardening) por rever, e `tvde-payment` está modificado (zona vermelha). Push dispararia build para a Play e deploy do web. Fica para quando o Danilo quiser rever commit a commit

🛑 SPEND CAPS — o travão a sério (achado 12/08 via o próprio agente Google, corrigido pelo executor 13/08)
- O Eddie recusou baixar o limiar de €200 (diz que o sistema define sozinho para reduzir frequência de transações), MAS apontou para **spend caps**, que é melhor
- DIFERENÇA QUE IMPORTA: orçamento = só alerta por email, não trava nada. **Spend cap = PÁRA mesmo os pedidos NOVOS daquele serviço nesse projeto** ao passar dos 100%, sem apagar recursos e sem tocar noutros serviços. Fica assim até ser levantado à mão; a 1 do mês seguinte zera sozinho
- ❌ **ERRO MEU, corrigido com prova dupla pelo executor: spend caps NÃO cobrem Maps.** Só existem **4 serviços elegíveis** — Gemini API, Vertex AI / Agent Platform, Cloud Run e Cloud Run functions. A documentação lista 4 e o menu do console mostrou os mesmos 4 ("All services (4)"). Não é permissão em falta nem preview inacessível: o produto não cobre Maps/Places/Geocoding/Directions. O agente do suporte generalizou e eu repeti sem verificar
- FEITO 13/08: **`Bora - cap Gemini API`** (projeto BoraApp, €1/mês, avisos 50/80/100) e **`Bora - cap Vertex AI`** (€1/mês). O Vertex não estava na ordem — iniciativa certa do executor, porque é o OUTRO caminho para chamar os mesmos modelos Gemini, e cobre também Agent Platform e Antigravity. Cloud Run/Functions não levaram cap: o Bora usa Edge Functions do Supabase e essas APIs nem estão ativadas
- ⚠️ VIGIAR: o cap do Gemini nasceu já a **66% (€0,66/€1,00)** — é o consumo de agosto ANTES da migração para o projeto sem faturação. Se disparar até 31/08 não é avaria, é a rede a funcionar. Zera a 1 de setembro
- BOTÃO DE EMERGÊNCIA se o app parar: `console.cloud.google.com/billing/012171-9755AA-4CE9FB/budgets` → nome do cap → **`Lift spend cap`** → `Confirm`. Pode demorar **até 1 hora** a recuperar. Levantado no mesmo mês, não volta a disparar nesse mês
- LIMITAÇÕES ditas pelo próprio Google: enforcement usa custos ESTIMADOS e não é instantâneo, logo pequenos excessos ainda são cobrados; usa custo bruto sem créditos; um cap = um projeto + um serviço; só mensal a começar no dia 1; e está em **Preview**, fornecido "como está"
- Contexto de 2026: desde 1/4/2026 cada conta Gemini tem um cap mensal obrigatório por tier (~$250 Tier 1) que não se desliga. Houve uma vaga pública de faturas enormes por chaves Gemini expostas — e o Google reembolsou alguns casos. Isto explica porque o suporte foi flexível com ele

🔴 ÚNICO BURACO QUE SOBRA — chave do Maps
- A chave `[REMOVIDO]` continua exposta em `web/index.html:30` e `AndroidManifest.xml:66`, sem restrição de aplicação e **sem travão financeiro possível** (Maps não é elegível para spend cap)
- Atenuantes reais: não está em nenhum dos 2 projetos ligados a esta faturação, e o Maps custou €0,00 em 90 dias — logo abuso provavelmente NÃO bate no cartão dele
- Opções que restam, para uma ordem futura: limites de quota DIÁRIOS por API + partir a chave em duas (web com HTTP referrer, Android com package `pt.boraapp.bora` + SHA-1 de release). Partir a chave obriga a mexer em código e a novo build

Prompts anteriores desta linha (histórico)
- `PROMPT_google_cloud_100eur_2026-08-12.md` → substituído por `PROMPT_google_cloud_custo_zero_2026-08-12.md` (OPUS), que foi o executado

⚠️ NOVO INCIDENTE 2026-08-19 — pagamento RECUSADO
- [stated] Email da Google (colado por ele): pagamento recusado no Visa ••••7447, conta 012171-9755AA-4CE9FB, a 19/08, motivo "fundos insuficientes". O email NÃO diz o valor
- [stated] Ele interpretou como "o banco recusou o reembolso" — é o CONTRÁRIO: é a Google a tentar COBRAR outra vez. Reembolso não é recusado por falta de saldo. Corrigido a ele
- Contexto: sobravam €0,81 no cartão depois dos €100 de 10/08, e os €78,67 aprovados (5-7 dias úteis desde 12/08) caem entre 19 e 21/08 — pode ainda não ter entrado
- 🔁 CONFIRMADO OUTRA VEZ POR MCP (19/08): o Gmail ligado à Claude.ai é `boraappbora@gmail.com` e NÃO tem um único email de faturação Google. NÃO voltar a gastar chamadas a procurar aqui — a faturação vive no email pessoal dele, só se vê pelo Cloud Console
- Ramificação que lhe dei: valor pequeno (uns euros = consumo de agosto antes da migração) → pagar à mão em Payment overview; valor perto de €78,67 ou €100 → é re-cobrança do reembolso, NÃO pagar e reabrir o chat com Case `74330074` / adjustment `875168637`
- Página certa: `console.cloud.google.com/billing/012171-9755AA-4CE9FB/payment` (Payment overview mostra o valor em dívida e tem "Make a payment")
- ✅ RESOLVIDO no mesmo dia (print dele, 19/08 20:46): a página Payment overview mostra **"You have a credit −€16,86 · No balance due"** — NÃO deve nada, não há nada a pagar. Postpay com os €100 de limiar todos disponíveis, último pagamento 10/08 de €100. O email de recusa era inofensivo: não sobrou dívida
- [stated] Ele leu os €16,86 como dívida e disse que não queria pagar — é o contrário, é crédito a favor dele. Corrigido
- 💶 REEMBOLSO ENTREGUE (email Google, 19/08): os **€78,67 foram entregues ao Visa ••••7447**. [stated] Ainda NÃO apareceu na conta dele — falta o tempo do banco (dias úteis). Se não aparecer até fim da semana seguinte, reabrir com Case `74330074`
- 🔢 ID do perfil de pagamentos: **3826-4937-6767** (guardar junto do Case ID)
- Transações na conta (print 19/08 21:09): Jun 1-30 **€3,09** · Jul 1-31 **€103,34** · Aug 1-19 **−€16,86** (negativo = crédito, ou seja **agosto teve gasto zero** — a migração para o projeto sem faturação funcionou)
- ⚠️ ACHADO NOVO: em "How you pay" o Visa ••••7447 (val. 11/28) está marcado a VERMELHO **"Transaction declined"** e **não há backup**. Pode travar o refund do crédito (a Google devolve ao meio de pagamento original). Correção: `Manage payment methods` → atualizar validade/CVV do cartão
- CAMINHO PARA OS €16,86 (dado a ele 19/08): já não há motivo para esperar — clicar **`Request a refund`** na mesma página de Payment overview, destino Visa ••••7447. Risco honesto avisado: crédito de cortesia pode ser dado como não-reembolsável; se der erro, voltar ao chat de suporte com o Case `74330074`
- ✅ FEITO 19/08 ~21h20: ele clicou em `Request a refund` e SUBMETEU. O diálogo dizia "€16,86 is available for refund", destino Visa ••••7447, e a seguir **"Your request has been received — we'll review this request for a refund of €16,86 to Visa ••••7447 and notify you when it's approved"**. Não pediu motivo nem justificação: é literalmente 2 cliques (Request a refund → Submit)
- LIÇÃO: o crédito ERA reembolsável apesar do aviso do diálogo ("promo and adjustable credits aren't refundable") — o medo de ser recusado no formulário não se confirmou. Não desencorajar da próxima
- ⏳ AGORA há DOIS valores a caminho do Visa ••••7447: €78,67 (já entregue pela Google, à espera do banco) e €16,86 (pedido submetido, à espera de aprovação). Total €95,53 dos €100. Vigiar o extrato; se algum falhar, Case `74330074`
- ⚠️ ATENÇÃO (aprendida à força, 19/08): ele estava a olhar para o ecrã e não encontrava o link. Descrever SEMPRE pela posição relativa e pelo vizinho ("linha azul à esquerda, por cima da caixa Transactions; o da direita é Make a payment"), nunca só pelo nome do botão

🛑 31/08 — o cap de €1 do Gemini bateu (é ele que trava a geração de imagens)
- O projeto Gemini (765097014497) devolve "Spend cap breached" e a API não gera nada: é o `Bora - cap Gemini API` de €1/mês criado a 13/08 a fazer o trabalho dele. Sem levantar/subir esse cap, o [[bora-studio-agentes]] não gera imagens sozinho e as artes têm de ser feitas à mão pela janela do Gemini
- [stated] Decisão de dinheiro que fica com o Danilo, ainda por tomar. Recomendei subir o cap para 10-20 €/mês (cada imagem custa cêntimos). Caminho: `console.cloud.google.com/billing/012171-9755AA-4CE9FB/budgets` → o cap → levantar ou editar o valor
- [stated] A chave Gemini que ele usou a 31/08 passou pelo chat — trocar por uma nova quando o trabalho fechar

💳 05/09 — SUBSCRITO O GOOGLE AI PLUS (compromisso novo, mensal)
- [stated] Ele subscreveu o **Google AI Plus** na conta dele: €0,49 no 1.º mês, depois **€4,99/mês**. Confirmado por mim no Chrome dele (o botão "Atualizar" desapareceu do Gemini e a ferramenta de vídeo passou a aparecer)
- O que isto desbloqueia de uma vez: **Veo** (geração de vídeo dentro do Gemini web, pelo agente de clique) e **Nano Banana Pro** + limites de uso maiores para imagem — ou seja, a trava do cap de €1 deixa de mandar no dia a dia das artes e da fábrica do filme
- Preços de referência vistos na página (PT): Plus €0,49 → €4,99/mês · Pro €2,19 → €21,99/mês · Ultra a partir de €99,99/mês
- ⏳ RENOVA SOZINHO. Ele foi avisado para decidir antes do fim do 1.º mês (~05/10) se cancela. O plano foi comprado como PONTE: se o [[bora-studio-agentes]] provar que faz reels que passam o fiscal de vídeo, ele cancela e volta a custar zero
- O cap `Bora - cap Gemini API` de €1/mês FICA como está — não foi alterado

💳 08/10 — GEMINI PAGO PARA O BORA ASSISTENTE (decisão dele)
- [stated] Pagou e ativou a faturação no projeto **bora-juiz** (gen-lang-client-0518472552), conta de faturação nova …C767 com crédito de teste de 300 USD; as chaves do bora-juiz passaram a "Nível 1" (pago). Razão: a chave grátis rebentava com uso real e o nível grátis não é permitido para utilizadores na Europa
- Supera a estratégia de 12/08 de "projeto Gemini sem faturação" para o Bora Assistente; os outros projetos (Default Gemini Project, em-dia) continuam no nível grátis

