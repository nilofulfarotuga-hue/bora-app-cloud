---
id: memoria-claude-ai-prompt-auditoria-3-plataformas-2026-10-06
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-06
zona: verde
confianca: alta
estado: atual
---

# Prompt de missão: auditoria das 3 plataformas (06/10)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-auditoria-3-plataformas-2026-10-06`, origem `claude-ai`, atualizada em 2026-10-06T18:36:18.552307+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt auditoria 3 plataformas 2026 10 06 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️
MOTOR: FABLE (Opus se a quota acabar) · PORTA: Claude Code, esta mesma sessão no PC do Danilo, pasta bora-app-cloud, branch autonomous-night-2026-04-29
SÓ COMEÇA DEPOIS de fechares a missão do cartão preso (publicada e provada nas três). Uma coisa de cada vez.

Invoca o orquestrador CEO-AI em `.claude/skills/ceo-ai/`, lê o `PADRAO_BORA.md` e segue a skill `protocolo-missao-bora`. Antes de planear, consulta o Córtex (cortex_buscar "pendente", "CONTINUAR", "paridade") e a memória `claude_ai_memoria`.

# MISSÃO: auditoria-3-plataformas-2026-10-06
Ordem do Danilo: "puxa tudo o que já arrumámos e vê se está a faltar alguma coisa na app, no Android, no iPhone ou na web, e conserta — com muito cuidado para não estragar nada que está a funcionar."
Regra nova dele (gravada hoje): todo conserto e toda publicação vão às TRÊS plataformas (Play Store, Apple, web) e são PROVADOS nas três.

CARTA DE AUTONOMIA: decides sozinho, não terminas o turno à espera, saltas o que estiver bloqueado e escreves porquê, reportas pelo Telegram, crias tu a continuação (cortex_nova_ordem) se o contexto acabar. Danilo só é chamado para o fisicamente impossível, num passo só, com a página aberta à frente dele.

## REGRA DE OURO: NÃO ESTRAGAR NADA
- Antes de mexer: corre a suite toda e guarda o resultado como linha de base. Depois de cada conserto: suite toda outra vez. Teste que estava verde e ficou vermelho = desfazes o teu conserto.
- Zonas protegidas (despacho, preços, finalizePurchase, bora_tokens, stripe-webhook, RLS de orders/wallets/ledger): NÃO tocas. Se o conserto precisar delas → escreve a proposta (cortex_propor) e passa à frente.
- Dinheiro real: só proposta, nunca aplicar.
- Um commit por conserto, mensagem em português a dizer o que e porquê. Nada de "melhorar" código vizinho.
- Antes de cada envio para o servidor, ver o que viaja junto (git log origin..HEAD).
- Outro erro achado pelo caminho fora desta lista → REPORTA, não corrijas por conta própria.

## O QUE JÁ APUREI (Claude.ai, 06/10 19:40, por MCP e GitHub)
1. Os três CI estão a publicar: Android, iPhone e web verdes no último commit 91925864 (iPhone ainda a correr às 18:21 UTC). Houve uma ronda de falhas a 05/10 (4f434d3a, aedb956b, 744fe903) que já voltou a verde — confirma que nada desse dia ficou só numa plataforma.
2. Erros reais nos telemóveis (tabela debug_crash_logs, últimas 72 h):
   - "Null check operator used on a null value" ao construir `DraggableScrollableNotification` — 14 vezes, Android, versões 639 a 653, inclusive a de hoje. É o bug mais repetido. Achar a folha arrastável (provavelmente o ecrã da corrida do motorista) e corrigir.
   - "RenderFlex overflowed by 77 px" (Android 649) e "48 px" (iPhone 649) — ver se ainda existe na 653.
   - "Starting FGS with type location ... targetSDK=36 requires ..." (Android 639) — serviço de localização em primeiro plano no Android 14+; confirmar se a permissão/tipo está certo para o estafeta e o motorista.
   - "GoogleMapController ... used after the GoogleMap widget had already been disposed" (Android 644).
   Para cada um: confirma se acontece também no iPhone e na web, corrige na raiz, prova com teste.
3. Trabalho que ficou fora da produção (ramos à frente da branch principal): `tvde/reserva-agendada-2026-08-20` (35 commits, parte já foi copiada a 30/08), `festas-preview` (20), `autonomous-night/fase2-cortex-tasks` (4), `main` (1), ramos `analise-*` e `diag-*` de 30/09 e 04/10. Para cada um: lista o que lá está que NÃO está na produção e se ainda faz falta. NÃO juntes nada às cegas — só o que for claramente um conserto já provado e ainda em falta; o resto vai para o relatório.
4. Pedido de alteração aberto desde 31/07: #1 "fix(notificacoes): push admin data-only + canais fantasma + track de producao". Vê se ainda é preciso ou se já foi feito por outro caminho; se já não faz falta, fecha-o com nota.
5. Continuações por acabar em `.claude/.ai/inbox/` (lê cada uma inteira): contas-claras 20 e 21/09, fable-13-09, hora-lisboa-2026-10-06 (diferenças app/servidor no horário das lojas), missao-noite-2026-10-03 (loadCurrent do TvdeDriverStore notificar só quando muda), noite-fecho-2026-09-24 (/verificar/<token>), ronda-dinheiro-despacho-2026-10-05, tvde-oferta-fantasma (prova no emulador), tvde-oferta-sobreposta-2026-09-21, ORDEM-PENDENTE-iphone-automatico-2026-09-22, ios-portugal (já resolvido: a app está na App Store PT desde 20/09 — arquiva). Para cada uma: feito / ainda falta / já não faz sentido. O que falta e não é zona protegida nem dinheiro → fazes.

## PARIDADE DAS TRÊS PLATAFORMAS (o centro da missão)
Para cada conserto feito desde 01/09 (git log da branch + relatórios em `.claude/.ai/reports/`), confirma que funciona igual em Android, iPhone e web. Atenção aos sítios onde já houve diferença: chave do Google Maps no iPhone (xcconfig), permissões no Info.plist (Face ID, localização), Stripe só no telemóvel (guarda kIsWeb), notificações (APNs no iPhone, sem push na web), localização em segundo plano, autocompletar de moradas na web, cache da web (Cache-Control). O que estiver a faltar numa plataforma → corriges.
Autoteste: o arnês do CI que abre todos os mosaicos e ecrãs nos três perfis tem de estar verde em Android e iPhone antes de publicar.

## PUBLICAR
No fim (e não antes de a suite estar verde e igual ou melhor que a linha de base): enviar para o servidor na branch autonomous-night-2026-04-29. Confirmar que os TRÊS CI acabaram verdes: Android (Play Store), iPhone (App Store / TestFlight, com envio à Apple) e web (bora-app-web.pages.dev). Abrir a web e confirmar a versão nova. Não mexer no pubspec (o CI sobe o número sozinho).

## PAINEL ADMIN
Se algum conserto criar uma definição nova ou um estado novo, o painel admin (PT-BR) tem de o mostrar. Senão, só confirmar que nada do painel se partiu.

## RELATÓRIO (para mim, não para o Danilo)
`.claude/.ai/reports/auditoria-3-plataformas-2026-10-06.md`: o que estava em falta, o que consertaste (com prova), o que ficou proposto (zonas protegidas/dinheiro), o que decidiste não fazer e porquê, e a versão publicada em cada uma das três. Digest curto em português simples em claude_ai_memoria, página `digest-2026-10-06-auditoria-3-plataformas`. Linha no e2e_log por bloco (fluxo `auditoria-3-plataformas-2026-10-06`).

/ctx doctor
/ctx stats

