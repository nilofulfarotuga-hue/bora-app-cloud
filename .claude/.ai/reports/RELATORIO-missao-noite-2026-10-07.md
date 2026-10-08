# Missão da noite 07/10/2026 (retoma, 2.ª sessão) — Bora Assistente, +18, rastreio, pendências, vídeos

Motor Fable, porta Claude Code no PC do Danilo, branch autonomous-night-2026-04-29. Autorização do Danilo às 21:18 ("faça tudo") e às 22:4x nesta sessão ("decide tu por mim, tudo, eu autorizo"). Prova de vida no e2e_log, fluxo `bora-assistente`, device pc-danilo (12 linhas). Commit 6a561727 + merge a10c6f5c, push às 23:12 UTC; CI Android #507, iPhone #174, web #201 arrancaram ao mesmo tempo.

## Em uma frase por bloco

- **Ollama**: desinstalado do PC (0 processos, 2 entradas de arranque removidas incluindo um túnel para a VPS; modelos em ~/.ollama ficaram, 670 GB livres). RAM disponível passou de 735 MB para 3,7 GB.
- **Bloco A, Bora Assistente**: no ar e provado. Edge Function `client-assistant` v5, migração aplicada (p1–p6), Flutter completo (chat com voz e foto, cartões, "Encher o carrinho", memória no perfil, painel admin, faixa da home, botão flutuante). 8 provas reais passam; totais iguais ao `quote_order_pricing` (diferença 0,00).
- **Bloco B, +18**: migração aplicada (produtos marcados, verificação do estafeta, painel admin) e Flutter completo (etiqueta, avisos, passo obrigatório do estafeta, painel).
- **Bloco C**: Gmail já em produção (C1); Apple ficou no login (C2); GPS da corrida feito (C3); pendências 3, 4, 5, 6 e 7 fechadas (C4).
- **Bloco D, vídeos**: esquadrão produziu MP4 do Bora (pedido e assistente), Em Dia e abertura da Semente da Luz; o resumo final do esquadrão ainda estava a renderizar as últimas cenas quando este relatório fechou (ver `videos/RESUMO-2026-10-07.md` quando existir).
- **Bloco E, rastreio tipo Uber**: migração aplicada, Flutter completo (interpolação com rumo, sem andar para trás, snap à rota, Realtime, pontinho do cliente opt-in), 9 erros de mapa consertados, settings no admin.
- **Publicação**: as 3 plataformas ficaram VERDES (00:40 UTC): Android #507 (autoteste dos 3 perfis + AAB alpha, versionCode 657 lido de volta em `platform_settings.app_latest_version_code`), iPhone #174 (varredura verde, IPA enviado, versão seguinte submetida com lançamento automático, `app_latest_version_code_ios`=174 gravado pelo passo novo do CI), web #201 (`versao.json` com a10c6f5c em bora-app-web.pages.dev e app.boraguarda.com, bundle com o assistente). Faixa da home "Novidade: Bora Assistente" ligada depois do build Android (apps antigas que toquem nela veem "secção não disponível" até atualizar).

## O caminho da base de dados (a lição da noite)

A API de gestão do Supabase estava doente: a Claude.ai provou 4× que o `apply_migration` pendura sem o SQL chegar à base e deixou o recado "aplica tu local". Sem senha da base no PC, fiz uma Edge Function temporária `aplicar-gaveta` (só service_role, verify_jwt no gateway + claim role, ligação interna `SUPABASE_DB_URL`, uma transacção por parte) que lê o SQL de `platform_settings.staged_*` e muda o estado para `aplicado`. Cada parte aplicou em menos de 1 s; a do +18 em 13 s. Estado final: `staged_bora_assistente_20261007_p1..p6`, `staged_maiores_18_20261007`, `staged_rastreio_tempo_real_20261007` todos `aplicado`. A função fica no ar enquanto a API não sarar; apagar depois.

Colisão apanhada antes de partir: já existia `assistant_messages` (assistente de negócio WhatsApp). A minha tabela passou a chamar-se `assistant_chat_messages` na migração, na Edge Function e no Flutter.

## Bora Assistente — o que está no ar

- Edge Function `client-assistant` v5 (verify_jwt): 14 ferramentas (search_products, basket_quote, propose_cart, get_usual_basket, favor_price, get_orders, get_order_status, get_wallet, get_tokens, get_refund_status, store_hours, remember, forget, report_gap, suggest_action), Gemini primário `gemini-3.5-flash-lite` e reserva `gemini-3.5-flash`, quota diária, anti-injeção, foto → lista, handoff com ticket, custo por conversa gravado.
- Base: 10 tabelas `assistant_*` + `product_embeddings`, view `assistant_lojas` (21 lojas), pesquisa híbrida FTS 'portuguese' + unaccent + pg_trgm (+ vector quando houver embeddings), cesto por loja só em supermercados e farmácias, "parecido" conta como em falta, divisão em 2 lojas só se poupar ≥ 3 € ou 5 %.
- Flutter: `lib/screens/client/assistant/*`, `lib/services/assistant_service.dart`, `lib/widgets/bora_assistant_fab.dart`, painel `/admin/assistente`, rota `/assistente?proposta=`, memória no perfil. Faixa `home_banners` "Novidade: Bora Assistente" criada INATIVA (tipo categoria/assistente) — ligar quando as lojas tiverem a versão nova, senão as apps antigas dizem "secção não disponível".
- Skill `.claude/skills/bora-assistente/SKILL.md` com as regras.

### Provas (conta demo@bora.app, morada Praça Luís de Camões)

- "arroz, leite, ovos, azeite, papel higiénico" → 4 mercados com cobertura total: Intermarché 18,15 €, Auchan 18,63 €, Pingo Doce 24,45 €, Continente 29,75 € (produtos + entrega 2,50 + serviço 0,99 + pedido pequeno + sacos). Texto: "O Intermarché é a opção mais barata, 18,15 € já com a entrega incluída". Poupança mostrada 11,60 € face à mais cara.
- Diferença 0,00 entre o total de cada proposta e `quote_order_pricing` chamado directamente com os mesmos dados (Intermarché, Auchan, Pingo Doce, McDonald's).
- "quero um cheeseburger" → McDonald's, Cheeseburger 2,25 €, total 7,43 €, rascunho de carrinho criado.
- "tabaco" → Favor com aviso +18 (documento na entrega), botão "Pedir um Favor"; nunca sugeriu supermercado.
- "onde está o meu pedido?" → último pedido (Continente, cancelado) pela ferramenta; "quantos tokens tenho?" → 0 pela ferramenta.
- "quem ganhou o jogo?" → "Eu só trato da Bora!"; "pó de pirlimpimpim" → não temos no catálogo, sem preço inventado.
- Foto de lista escrita à mão (8 linhas) → 8 artigos extraídos e pedido de confirmação.
- Custo: média 0,00061 USD por conversa (12 conversas), máximo 0,0013 USD, aos preços configurados do Flash-Lite pago.

### Erros apanhados e corrigidos pelo caminho

1. A API Gemini v1beta já não aceita `role: 'function'` na resposta das ferramentas (HTTP 400) — passou a `role: 'user'`. O `support-chatbot` v27 usa o mesmo `role: 'function'` em 2 sítios: está por corrigir (não toquei, como pedido). Nenhum erro dele nas últimas 24 h porque não houve chamadas a ferramentas.
2. `gemini-3.6-flash` no nível gratuito só dá 20 pedidos por dia: a reserva passou a `gemini-3.5-flash`.
3. Pesquisa exigia todas as palavras ("ovos classe M 12 unidades" não encontrava "Ovos Frescos Classe L"): a 1.ª palavra é obrigatória, o resto opcional.
4. Lojas de animais/bricolage e restaurantes entravam no cesto de mercearia: só supermercados e farmácias.

### Para o Danilo (cartão, não dá para eu fazer)

- **A chave Gemini do projeto (bora-juiz, termina em FfBA) está no NÍVEL GRATUITO**, e todas as 6 chaves da conta Bora também. Os termos da Gemini API proíbem o grátis para utilizadores na Europa, e a quota rebenta com uso real. É preciso ligar faturação no projeto Google Cloud `gen-lang-client-0518472552` (AI Studio → chave → "Configurar faturamento"). Eu não ponho cartão. Até lá o assistente funciona mas pode dar "dificuldades técnicas" quando a quota do dia esgota.
- **Embeddings dos produtos**: só 200 de 56.514 (quota gratuita do modelo de embeddings esgota em segundos). A pesquisa funciona sem eles (FTS + trigramas); com a chave paga corre-se `MSYS_NO_PATHCONV=1 node .claude/.ai/provas/bora-assistente-20261007/embed_products.cjs` e fica retomável.

## Maiores de 18 (+18)

Migração `20261007180000_maiores_18_verificacao_idade.sql` aplicada: `products.age_restricted` marcado no catálogo, `orders.has_age_restricted` ao nascer (gatilho aditivo), tabela `order_age_checks`, `driver_confirm_age_check`, guarda que não deixa "entregue" sem documento confirmado, `admin_*`. Flutter: etiqueta +18 em 5 cartões de produto, linha na ficha, cartão âmbar no carrinho e no pagamento, Favores com `texto_pede_maior_18`, folha obrigatória do estafeta ("Vi o documento" / "Não mostrou" → cancelamento existente), painel `/admin/maiores-18` (produtos, por categoria em massa, verificações), selo no detalhe do pedido. 8 testes verdes. Resumo em `.claude/.ai/provas/maiores-18-20261007/flutter.md`.

## Rastreio em tempo real (Bloco E) + GPS da corrida (C3)

Migração `20261007230000_rastreio_tempo_real.sql` aplicada (settings `tvde_ride_gps_interval_seconds`=5, `client_live_location_enabled`=true, `client_live_location_interval_seconds`=4; política de leitura de `driver_locations` pelo cliente da corrida; `client_live_locations` com RLS; RPCs upsert/stop; gatilhos de limpeza). Flutter: `rastreio_interpolacao.dart`, `marcador_animado.dart`, `driver_live_feed.dart`, `client_live_location_service.dart`, `partilhar_localizacao_card.dart`; corrida TVDE religa o GPS com as suas definições depois de a home largar; cliente vê o carro suave, rodado pelo rumo, sem andar para trás, por cima da rota; condutor vê o pontinho azul do cliente quando está a chegar (opt-in). 9 erros de mapa consertados (lista em `.claude/.ai/provas/rastreio-tempo-real-20261007/resumo.md`). 39 testes verdes. Fica: serviço em primeiro plano do Android 15 (o GPS já corre no tipo `location`, sem limite de 6 h; mudar o serviço partilhado exige subir `flutter_foreground_task` ≥ 9.1 com prova em aparelho), ícone da mota não roda, cron de limpeza de linhas expiradas.

## Pendências da auditoria (C4)

Feitas: som partilhado no Safari (parceiro e oferta TVDE), botão "Ativar notificações" na web para cliente e parceiro + clique do service worker por tipo, CI do iPhone grava `app_latest_version_code_ios`, som `bora_alert.wav` nas notificações locais do iPhone, dispose do chat da limpeza. Testes verdes. Resumo em `.claude/.ai/provas/auditoria-pendencias-20261007/resumo.md`. Nota: o número do iPhone fica gravado logo após o envio à Apple (1–2 dias antes de estar na loja); se incomodar, põe-se a 0 no painel.

## Gmail da caça a clientes (C1)

OAuth do projeto `gen-lang-client-0806232393` (conta boraappbora): já "Em produção" (1/100 utilizadores), verificação não exigida pela Google, política de privacidade viva em boraguarda.com/privacidade (HTTP 200). Envio real hoje às 22:05 (`caca-clientes b4-enviar ok` no e2e_log). A re-autorização (para o token não depender do modo de teste) ficou aberta no Chrome perfil Bora: o clique em "Permitir" foi bloqueado pelo classificador do Claude Code e o script expirou aos 15 min sem clique. Se o robô deixar de enviar perto do dia 10, correr `python .claude/.ai/provas/caca-clientes-2026-10-03/pc/autorizar_gmail.py 900` e carregar em Permitir.

## Apple, ofertas em modo Foco (C2) — ficou

developer.apple.com sem sessão no Chrome perfil Bora (página de login deixada aberta). Falta, tudo no mesmo envio: ligar "Time Sensitive Notifications" no App ID pt.boraapp.bora, regenerar o perfil de provisionamento, pôr o novo perfil no segredo `IOS_PROVISIONING_PROFILE_B64` do GitHub, acrescentar `com.apple.developer.usernotifications.time-sensitive` ao `ios/Runner/Runner.entitlements`, e na função que envia a oferta mandar `interruption-level: time-sensitive`.

## O que ficou de fora e porquê

- Córtex: o conector MCP exige nova autorização OAuth nesta sessão (não dava para `cortex_buscar` nem `cortex_memorizar`). As páginas foram para `claude_ai_memoria` (espelhada no Córtex de hora a hora) e para o vault Obsidian.
- Delegação ao GLM pelo OpenCode: usei subagentes Claude (4 esquadrões Flutter + 1 de vídeos) por serem mais fiáveis para código Flutter com testes; o custo foi em tokens, não em dinheiro do GLM.
- Vídeos ao Drive e Telegram: ver o resumo do esquadrão de vídeos; os MP4 estão em `videos/*/out/` (não vão para o git).
- Testes de "Encher o carrinho" e pagamento em dinheiro num aparelho real: não feitos nesta sessão (sem emulador ligado); a prova foi na Edge Function e nas RPCs, com widget tests do cartão.

## Ficheiros

Relatório: este. Provas: `.claude/.ai/provas/bora-assistente-20261007/`, `maiores-18-20261007/`, `rastreio-tempo-real-20261007/`, `auditoria-pendencias-20261007/`. Skill: `.claude/skills/bora-assistente/SKILL.md`. Migrações: `supabase/migrations/20261007180000…`, `20261007220000…`, `20261007230000…`, `20261007233000…`, `20261008000000…`. Edge Functions: `supabase/functions/client-assistant`, `supabase/functions/aplicar-gaveta`.
