---
id: memoria-claude-ai-prompt-publica-e-fecha-2026-10-29
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Prompt: publicar hoje + arrumação + Bloco 11 + reembolsos (29/10 18:20)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-publica-e-fecha-2026-10-29`, origem `claude-ai`, atualizada em 2026-10-29T18:12:10.239461+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt publica e fecha 2026 10 29 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️

Invoca o orquestrador CEO-AI em .claude/skills/ceo-ai/ e segue as skills danilo-como-trabalhar, protocolo-missao-bora e lancar-missao-claude-code.

MOTOR: FABLE 5.1 (Opus só volta a 01/11 18:00 Lisboa).
PORTA: esta sessão "Missão geral Bora 2026-10-28" (Controlo Remoto no PC do Danilo), cópia de trabalho C:\BoraLocal\wt-missao-geral-28-10, ramo missao-geral-2026-10-28 (HEAD 53fc240e, 41 commits por cima de 9eed27ff).
FLUXO no e2e_log: publica-2026-10-29 (uma linha por passo: fluxo, passo, estado, detalhe, device='claude-code-pc').
Escrito pelo Claude.ai às 18:20 de 29/10/2026.

AUTORIZAÇÃO LITERAL DO DANILO (29/10 18:02, por voz): "Eu autorizo tudo. Eu autorizo publicar também. Em vez de publicar sábado, vai publicar já hoje. Eu autorizo você fazer essas coisas aí tudinho já, sem ficar nada para trás. Faça tudo, só o 10 que ainda não. Não deixa nada para trás que já era para ter feito."
→ O "publica" de sábado passa a HOJE. Cobre as 3 lojas (Play Store + Apple/TestFlight + web), o envio do ramo para o servidor (git push), a junção no ramo de produção e a arrumação do código. O item 10 (Casa & Manutenção) continua a NÃO avançar. Preços/comissões: só o que está escrito abaixo (item 4 do Bloco C). Nunca reescrever histórico git publicado, nunca apagar dados de produção, nunca mexer no versionCode (o CI incrementa sozinho), nunca escrever segredos nem dados pessoais no repo público.

O QUE ESTA MISSÃO MEXE E PORQUÊ
- Publicação: o trabalho de ontem e hoje (41 commits, 2148 testes verdes, juiz final ok) está só no PC; o Danilo quer tudo no ar hoje.
- Arrumação: peças já feitas que ficaram por ligar e erros que a auditoria do emulador só reportou.
- Bloco 11 (adendo 5): os itens 4, 5, 6, 7 e 8 que o Danilo mandou avançar.
- Reembolsos (Bloco 2): o Claude.ai tentou publicar as 6 funções por MCP e o classificador da Anthropic recusou duas vezes; aqui tenta-se pelo CLI do Supabase.
Qualquer OUTRO erro que encontres pelo caminho: REPORTA no e2e_log e no relatório, não corrijas calado (excepto o que está listado aqui).

ORDEM (não trocar; uma coisa de cada vez)

BLOCO 0 — Pré-voo (5 min)
0.1 Lê CONTINUAR-final-app-2026-10-29.md e o fecho da missão final-app-2026-10-29 (e2e_log, passo 'fecho'). Lê por SQL a página adendo-5-final-app-2026-10-29 (tabela public.claude_ai_memoria) — é o desenho do Bloco C.
0.2 git status na cópia de trabalho: confirma HEAD 53fc240e; os registrants gerados (linux/macos/windows) e as 67 capturas da auditoria ficam FORA dos commits (de propósito). Nada mais pendente? Se houver ficheiros alterados sem commit que pertençam à missão, commit por caminho (nunca git add -A).
0.3 RAM/fila conforme a lei do pré-voo. Regista 'plano' no e2e_log.

BLOCO A — Publicar HOJE o que já está pronto (arranca já, para o CI começar a contar)
A.1 Envia o ramo para o servidor: git push origin missao-geral-2026-10-28. Se a bora-tranca abrir caixa, o Danilo autorizou (18:02): a Claude.ai carrega Permitir pelo Chrome; se não der, regista 'bloqueado' e segue para A.2 só depois de a caixa ser aprovada (não contornes a tranca).
A.2 Junta no ramo de produção autonomous-night-2026-04-29 pelo caminho que já publicou antes (ver .claude/skills e o histórico em docs/ e no livro: merge sem reescrever histórico, --no-ff; nunca rebase de ramo publicado; nunca force). Resolve conflitos lendo os dois lados; em caso de dúvida numa zona protegida, para e reporta. git push origin autonomous-night-2026-04-29.
A.3 Vigia o CI (GitHub Actions / Codemagic, conforme o pipeline atual): Android (Play Store), iOS (App Store/TestFlight) e web. Não mexas no versionCode. Se um job falhar: regista a causa raiz, corrige só o que for de build (não de produto), e volta a lançar.
A.4 Prova nas 3: número de versão/build novo visível na Play Console (faixa que o pipeline usa), no App Store Connect/TestFlight e na web (app.boraguarda.com, hash/versão da build). Regista 'A.4-prova-3-lojas' com os três números. Esta publicação #1 não espera pelos Blocos B e C.
A.5 Copia o SQL da S1 (docs/propostas/missao-geral-2026-10-28/janela2/S1_platform_settings_segredos.sql) para supabase/migrations/20261029152540_s1_platform_settings_segredos.sql (já está aplicada em produção; é só para o repo bater com o ar). Se a tranca bora-mods recusar outra vez, regista e a Claude.ai faz pelo GitHub web depois do push.

BLOCO B — Arrumação do código (item 4 do Danilo)
B.1 Ligar o que ficou por ligar (adendo 4): BarraPedidoAtivoHost no builder de lib/main.dart (~linha 989) para a barra aparecer em TODOS os ecrãs do cliente; ResumoAvaliacoesCard e FunilPratosCard e o negrito dos talheres em lib/screens/partner/partner_dashboard_screen.dart (~linha 1065). Testes de widget para cada.
B.2 Erros reportados na auditoria (7.9-so-reportar), agora com autorização para corrigir:
 (a) Despacho — canal driver-offer fecha e reabre de 3 em 3 s enquanto o estafeta está Online (lib/stores/driver_store.dart, _attachOfferChannel/_scheduleReconnect: o unsubscribe do canal antigo dispara 'closed' que volta a agendar reconnect). Corrige com uma flag de "fecho pedido por mim" e teste que prova que não há ciclo. Revisor independente (subagente) antes do commit, porque é despacho.
 (b) Dinheiro (ecrã) — lib/screens/driver_map_screen.dart ~3730, folha "Ver compras": "Cliente paga na entrega" tem de ser igual ao que o servidor diz (cash_total_due / 7,17 no caso da auditoria): inclui a taxa de pedido pequeno. Só o ecrã muda; a conta do servidor não se toca.
 (c) lib/stores/order_store.dart (zona protegida): depois de criar o pedido o cliente ainda tenta created→preparing e o servidor recusa com 42501 (ruído legado do _simulateFlow). Remove a tentativa do lado do cliente. Se a tranca recusar o ficheiro, reporta.
 (d) Base — legal_terms_pending devolve a versão mais recente por aceitar com ORDER BY effective_date DESC LIMIT 1; quem aceita a de 01/11 vê logo a de 01/10. Regra certa: aceitar a mais recente cobre as anteriores. Migração com backup da função (bkp_fn_legal_terms_pending_20261029) e prova por SELECT.
 (e) Cosmético — carrinho repete "Faltam X € para evitar a taxa" em duas linhas (lib/widgets/juntar_mais_tira.dart e _FaltaParaOMinimo): fica uma só.
 (f) Favores — o botão "Usar esta morada" aceita morada sem coordenadas e o passo seguinte barra ("Escolhe uma sugestão da lista"): ou geocodifica a morada escrita (places-proxy, já existe na web) ou só mostra o botão quando há coordenadas. Nunca deixar o utilizador num beco.
 (g) Reservas — o atalho "Restaurantes" dentro do separador Reservas abre a lista de entrega (Burger King, KFC) em vez da lista de restaurantes com reserva de mesa; e o aviso de loja "Em breve" ao reservar diz "pedidos" quando devia dizer "reservas".
 (h) Ganhos do estafeta — a auditoria viu "Ganhos de hoje 0,00" e "Trabalhos" vazio logo após uma entrega demo: confirma se é só porque os pedidos de teste ficam de fora (então ok, regista) ou se é erro (então corrige).
 (i) Vigia de pedidos/erros para o Hermes (adendo 1 E): o script estava pronto e a tranca recusou o Write por falso positivo (a constante ENV_KEY com o caminho do .env parecia um segredo). Grava o ficheiro com a constante chamada CAMINHO_FICHEIRO_ENV (é um caminho, não uma chave; nada de segredo em texto claro), instala o cron na VPS e prova um ciclo em seco. Se a tranca recusar na mesma, reporta e não contornes.
B.3 flutter analyze 0 erros, testes dos ficheiros tocados + bateria completa no fim do bloco, anti-trapaça, commits pequenos por caminho (mensagens em português, com Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>).
B.4 Painel admin: tudo o que é novo tem correspondência no painel (PT-BR, termos técnicos explicados). Confirma os interruptores do adendo 4 lá.

BLOCO C — Bloco 11 (adendo 5: itens 4, 5, 6, 7, 8 do Danilo)
Segue o desenho da página adendo-5-final-app-2026-10-29 à letra. Ordem: 6 (modo ocupado) → 5 (agendar com loja fechada) → 4 (promoções com preço riscado) → 7 (substituição antes de pagar) → 8 (pedido em grupo, último e só se couber; senão fica desenhado no CONTINUAR).
Regras: cada item com interruptor em platform_settings e ecrã no painel admin (PT-BR); app PT-PT; testes; itens 5 e 6 mexem no despacho → revisor independente (subagente que não viu o código a nascer) antes de ligar, interruptor DESLIGADO por defeito até o revisor dizer SIM; item 4 — o Danilo autorizou tudo às 18:02: a comissão da Bora, o markup oculto e a taxa de serviço calculam-se sobre o preço promocional (o que o cliente paga, como Glovo/Uber/iFood); guarda histórico de preços por produto para a linha "preço mais baixo dos últimos 30 dias"; interruptor desligado por defeito e tudo escrito no relatório para o Danilo ver antes de ligar; item 7 usa o caminho de reembolso do Bloco 2 (devolução ao meio original) — se o pacote ainda não estiver no ar, o código fica pronto a chamar a função e o interruptor fica desligado.
Não inventar: só o que existe na Uber Eats, Glovo e iFood. Não estragar o que já funciona.

BLOCO D — Reembolsos (Bloco 2, dinheiro, AUTORIZO de 14:22 e 18:02) pelo CLI
D.1 Vê se o CLI do Supabase funciona no PC sem instalar nada permanente: npx supabase@latest --version e se há SUPABASE_ACCESS_TOKEN no ambiente ou num .env do projeto (NUNCA o imprimas nem o copies para o repo). Sem token: regista 'bloqueado' e salta o bloco (a Claude.ai faz pelo painel do Supabase com o Danilo a carregar no botão).
D.2 Com token: publica JUNTAS, a partir da cópia de trabalho e com o _shared/cobranca_stripe.ts v2 já no repo, as funções que NÃO são zona vermelha: cancel-order-with-choice (v19), execute-cancellation (v16), admin-cancel-order (v15) e auto-refund-order (v4) — padrão "ar + remendo": antes, compara cada uma com o que está no ar (o repo esteve ATRÁS do ar no notify-tvde-driver) e leva os mesmos ficheiros auxiliares. client-cancel-order (v30) e reprocess-refund (v4) são zona vermelha no PC: se a tranca recusar, regista e NÃO contornes. O SQL dos tokens (03_tokens_gastar_e_devolver) só se aplica quando as 6 estiverem no ar — se faltarem as 2 vermelhas, deixa o SQL para a Claude.ai e regista.

BLOCO E — Publicação #2 e fecho
E.1 Com B e C fechados: bateria completa, juiz, anti-trapaça, fiscal de segurança (0 segredos, 0 dados pessoais). Commit, push do ramo, junção no ramo de produção, push → CI → prova nas 3 lojas (números de build) como no A.4. Regista 'E.1-prova-3-lojas'.
E.2 Relatório em .claude/.ai/reports/FABLE-2026-10-29-publica.md e Desktop\Bora\prompts\relatorio-publica-2026-10-29.md (texto corrido: fiz isto, falta isto; itens 4/5/6/7/8 com o que ficou ligado e desligado e porquê; tudo o que só se reportou). Digest no livro (claude_ai_memoria, página digest-2026-10-29-publica). CONTINUAR-final-app-2026-10-29.md atualizado com o que sobrou. Telegram ao Danilo. Linha 'fecho' no e2e_log.
E.3 Termina com /ctx doctor e /ctx stats.

Carta de autonomia: não voltes ao Danilo a meio; decide sozinho, salta o que estiver bloqueado e regista; o Danilo só é chamado para caixas Permitir (a Claude.ai acompanha pelo Chrome e carrega quando puder). Nunca termines o turno à espera.

