---
id: memoria-claude-ai-livro-areas-bora-app-parte3
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Bora App multi-vertical platform — architecture, verticals, business rules, and protected zones (parte 3 de 4)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-bora-app-parte3`, origem `claude-ai`, atualizada em 2026-10-23T05:42:55.316693+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas bora app parte3 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/bora-app.md, parte 3 de 4), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

- [stated] ✅ CAUSA RAIZ REAL (Claude Code, confirmada): era o bloco `notification` no payload FCM do `notify-admin-urgent`. Com bloco `notification`, o Android desenha pelo tray, o `_firebaseMessagingBackgroundHandler` do Flutter NÃO corre e a notificação persistente nunca é postada — efémera com a app fechada, NADA com a app aberta noutro ecrã. Exatamente o mesmo bug já corrigido no `notify-service-provider` v3 a 28/07; o `notify-admin-urgent` ficou de fora dessa limpeza.
- [stated] FEITO: `notify-admin-urgent` v15 DATA-ONLY deployed, Dart alinhado a ler title/body do `data`, canal `bora_admin_urgent` com `Importance.max`. Prova do servidor: disparo real d20986b3…, token não limpo (FCM aceitou).
- [stated] ⚠️ NÃO FECHADO: falta o SCREENSHOT no telemóvel. `adb devices` deu lista vazia em 4 tentativas — o telemóvel do Danilo não estava ligado por USB. Regra dele: sem prova no telemóvel não está feito.
- [stated] ⚠️ JANELA DE RISCO enquanto o Danilo não instalar o build novo: a Edge já é data-only mas o APK dele é antigo → o push admin aparece como "🔴 Bora Admin" com corpo VAZIO. Resolve-se instalando a atualização.
- [stated] Agravante de arquitetura: o painel admin é um ECRÃ DENTRO do app do cliente (cliente → perfil → painel administrativo). Logo o push admin chega ao mesmo app do cliente e tem de funcionar com o app fechado / noutro ecrã. Se o handler do cliente filtrar por tipo, `type: 'admin_generic'` pode estar a ser ignorado.
- [stated] A Edge manda bloco `notification` + `data` (não é data-only como o notify-partner v21 que funciona) — o handler de segundo plano do Flutter não corre, fica tudo entregue ao tray do Android, que depende do canal existir.

Auditoria de notificações — o que sobrou (2026-07-31, Claude Code)
- [stated] Corrigidos 2 canais fantasma: `bora_partner_ratings` não existia em lado nenhum e `bora_orders` só nascia on-demand — ambos caíam no fallback do Manifest e tocavam com o som do canal de OFERTAS.
- [stated] 5 Edge Functions com o MESMO bug do bloco `notification`, LISTADAS mas NÃO convertidas (decisão certa do Claude Code — cada uma exige alteração emparelhada no Dart + teste no telemóvel, e converter 5 às cegas numa app que agora publica direto para todos trocaria 1 bug conhecido por 5 regressões): `notify-cleaner`, `notify-tvde-client`, `notify-purchase-finalized`, `notify-admin-reimbursement`, `notify-partner-low-rating`. Fila para próximas sessões, uma de cada vez com prova no telemóvel.
- [stated] ARMADILHA a respeitar antes de mexer nisso: `notify-service-provider` LOCAL diverge do DEPLOYED — fazer deploy do local sobrescreveria a versão boa (v3) por uma antiga. Ver sempre o deployed primeiro (`get_edge_function`), nunca assumir que o repo é a verdade.
- [stated] Web confirmado saudável: `build_web_deploy.yml` corre a cada push, site 200, `version.json` com o código do dia.
- [stated] LIÇÃO DE GIT registada (custou uma run falhada): `git add <ficheiro>` leva o FICHEIRO INTEIRO, não só as linhas do agente. O Claude Code arrastou trabalho por committar de outro executor no `lib/main.dart` (rotas de `ResetPasswordScreen.routeName` sem o ficheiro que as define) → CI falhou com "Member not found: 'routeName'". A lição antiga só cobria `git add -A`. Recuperou sem destruir o WIP alheio: stash → revert do ficheiro → reaplicar só a sua alteração → commit → devolver WIP → `pull --rebase --autostash` (nunca `--force`).

Comissão de parceiro — regra confirmada e bug de repasse corrigido (2026-08-05, Claude.ai via MCP)
- [stated] REGRA CONFIRMADA por Danilo (vale para TODOS os parceiros): Bora cobra 10% ao parceiro sobre tudo o que ele vende; o cliente paga 5% de taxa de serviço + 5% embutido escondido no preço do produto (produto de €10 aparece a €10,50) + €2,50 de entrega. Se em algum sítio não estiver assim, corrigir.
- [stated] EXCEÇÃO POR LOJA: quem suporta os 10% pode variar de loja para loja. Por defeito sai do parceiro; nalgumas lojas (caso do [[mister-kebab]]) Danilo não cobra à loja e os 10% passam para o cliente.
- [stated] FEITO por MCP (migration partner_commission_billing_2026_08_05): coluna `restaurants.partner_commission_billing` ('partner' default | 'client'), com CHECK e COMMENT a explicar a fórmula de carregamento do catálogo em cada caso. NÃO muda a fórmula de repasse — só regista o acordo e serve o painel admin.
- [stated] BUG REAL DE DINHEIRO encontrado e corrigido (migration fix_partner_ledger_hidden_markup_2026_08_05, backup da função antiga em `public.bkp_fn_post_order_to_ledger_20260805`): `post_order_to_ledger` pagava ao parceiro `subtotal × 0,90` — com o 0,90 escrito à mão (ignorava platform_settings) e aplicando os 10% POR CIMA do preço que já trazia os 5% escondidos, o que devolvia ao parceiro parte do markup oculto. Agora: `store_base = subtotal / (1 + partner_hidden_markup_pct)` e `restaurante = store_base × (1 − partner_visible_commission_pct)`, ambos lidos de platform_settings. Corrigido também: a loja passou a ser identificada por `NEW.restaurant_id` em vez de casar pelo NOME (`restaurants.name = vendor_name`), que era frágil.
- [stated] Fórmula de carregamento de catálogo: parceiro normal → preço no app = balcão × 1,05; parceiro em que o cliente paga a comissão → **balcão × 1,15** (regra literal do Danilo: 10% + 5%). NÃO usar ÷0,90 ×1,05 — ele rejeitou expressamente essa variante em 2026-08-05, mesmo custando ~1,3% ao parceiro no repasse.
- [stated] PENDENTE (regra painel admin): o painel ainda não mostra nem edita `partner_commission_billing`, e o ecrã financeiro do parceiro deve passar a explicar o repasse com a fórmula nova.
- [stated] SEGUNDO BUG DA MESMA FAMÍLIA, encontrado pelo executor e corrigido por MCP (migrations `fix_financial_split_and_rounding_2026_08_05` + `ledger_use_partner_store_share_2026_08_05`, backup em `public.bkp_fn_financial_split_20260805`): existia uma SEGUNDA função a repartir o dinheiro do parceiro — `apply_order_financial_split`, que escreve em `order_financials`/`order_financial_transactions` — e essa ainda tinha `× 0.90` escrito à mão. Para o mesmo pedido de €20 dava loja €18,00/plataforma €2,00 contra €17,15/€2,85 do ledger: duas contabilidades a discordar. Criada a função única `public.partner_store_share(subtotal)` (subtotal × (1−comissão) ÷ (1+markup oculto), com UM só arredondamento) e as duas funções passaram a usá-la. Confirmado por MCP: €20 → loja €17,14 / Bora €2,86; Menu Kebab a €9,22 → loja €7,90 (o balcão exato).
- [stated] LIÇÃO: quando se corrigir regra de dinheiro, procurar SEMPRE todas as funções que repartem o mesmo valor — havia duas e a primeira correção só apanhou uma.
- [stated] MÉTODO CERTO DE EXTRAIR CATÁLOGO (Danilo corrigiu-me em 2026-08-05, depois de eu ter mandado o executor buscar o HTML público e trazer só 18 itens de 47): NUNCA fazer fetch da página pública — dá catálogo truncado (Uber devolveu 18 itens, Glovo 5). O caminho que já usámos na Auchan e no Intermarché: o Danilo deixa a página do Uber/Glovo ABERTA no Chrome do PC dele, com sessão iniciada, e o executor liga-se a esse Chrome (Playwright headed / CDP) e navega como se fosse fazer um pedido, clicando produto a produto. Daí saem os endpoints internos `getStoreV1` (secções) e `getCatalogPresentationV2` (produtos por secção, preço em cêntimos, imageUrl), e abrindo cada produto saem as opções/customizações. Scripts já existentes no repo: `scripts/uber_eats_probe.js`, `scripts/uber_eats_intermarche_crawler.js`, `scripts/glovo_grocery_crawler.js`, `scripts/glovo_apply_rebuild.js`.
- [stated] A extensão Claude in Chrome tem ubereats.com BLOQUEADO — por isso é Playwright, não a extensão.

Ambiente errado: Claude Code na NUVEM vs no PC (2026-08-05)
- [stated] SINTOMA a reconhecer depressa: o executor responde que está em `/home/user/bora_app` (Linux), numa branch tipo `claude/build-lista-XXXX`, sem `.claude/skills/ceo-ai/`, sem `C:\Users\danil\Downloads`, sem Chrome/Playwright/robocopy, sem `bora-site/.env` nem `CLOUDFLARE_API_TOKEN`, e sem saber que projeto Supabase usar. Isso é o Claude Code na NUVEM, não o do PC do Danilo.
- [stated] DECISÃO tomada nesse caso: PARAR e reabrir no Claude Code do terminal do PC. Não aceitar a alternativa de fazer só a parte de código com esqueleto de site e placeholders — isso devolveria trabalho manual ao Danilo (preencher imagens à mão), que é exatamente a regra que ele mais repete, e ainda ficaria numa branch fora da nossa.
- [stated] Todo prompt que dependa de ficheiros do PC, do Chrome com sessão dele, de tokens locais ou da branch `autonomous-night-2026-04-29` só corre no Claude Code do PC. Vale dizer isso no topo do prompt para o executor detetar o ambiente errado logo no início em vez de a meio.

Padrão reutilizável para lojas coming_soon + técnicas de scraping (2026-08-05, sessão Mr Kebab)
- [stated] PADRÃO CartStore.vendorBlocksAddToCart: getter único e documentado para decidir se uma loja coming_soon trava o carrinho; os pontos de bloqueio no Flutter leem DAQUI em vez de espalhar `if (restaurant.comingSoon)` por vários ficheiros. Usar o mesmo padrão nos próximos parceiros em coming_soon.
- [stated] TÉCNICA para tirar fotos do Facebook sem o modal de login tapar tudo: recolher os URLs fbcdn e abrir cada imagem directamente no separador (não screenshot do feed) — remover os overlays do DOM remove também o conteúdo por baixo.
- [stated] LIÇÃO de cache: depois de publicar no Cloudflare Pages, o Chrome pode mostrar a versão antiga por cache — confirmar sempre comparando os bytes do ficheiro em disco com os do site ao vivo, ou tirar screenshot com a cache desligada.

Pendente — catálogo Intermarché peixaria (2026-08-11)
- [stated] Danilo quer acrescentar itens da secção de peixaria/marisco do Intermarché ao catálogo (referência: Caracol Confecionado 1kg, etiqueta Intermarché 5,99€) — pediu pra fazer depois, não agora.

🔒 ALERTA DE SEGURANÇA SUPABASE RESOLVIDO POR MCP (2026-08-11, email do Supabase reencaminhado pelo Danilo)
- Alerta dizia "tabela de acesso público — qualquer pessoa com o URL pode ler, editar e apagar". Verificado por MCP (get_advisors): 607 avisos no total, mas só 5 tabelas em nível ERROR com `rls_disabled_in_public` — TODAS backups pontuais do Mr Kebab de 05/08: `bkp_mrkebab_pre_fotos_20260805`, `bkp_mrkebab_pre_crawler_20260805`, `bkp_mrkebab_precos_20260805`, `bkp_mrkebab_opcoes_20260805`, `bkp_mrkebab_opcoes_v2_20260805`. Não eram dados de cliente ao vivo
- FECHADO por mim via MCP (migration `fechar_rls_backups_mrkebab_expostos`): RLS ativado nas 5, sem políticas → só a service_role lhes acede. Confirmado por SELECT em pg_tables: rowsecurity=true nas 5. Nenhuma delas é lida pela app, logo zero risco de partir nada
- FICA POR TRATAR (nível mais baixo, não urgente): 4 views `socio_kpi_*` marcadas SECURITY DEFINER (ERROR), 51 tabelas com RLS ligado mas sem política nenhuma (INFO — a maioria backups), 387+151 funções SECURITY DEFINER executáveis por authenticated/anon (WARN — a rever, já houve limpeza destas em junho), 8 funções com search_path mutável, e a proteção contra palavras-passe vazadas desligada no Auth
- LIÇÃO: correr `get_advisors` de vez em quando, sobretudo depois de criar tabelas de backup — os backups são a fonte repetida destes alertas

🔒 SEGUNDO ALERTA RLS, fora da limpeza de 11/08 (2026-08-14, achado+fechado via MCP): `bkp_fn_post_order_to_ledger_20260805` e `bkp_fn_financial_split_20260805` (backups de função da correção de comissão de 05/08) estavam com RLS desligado, expostas a anon/authenticated. Zero funções as referenciam (confirmado por MCP). FECHADO (migration `fechar_rls_backups_fn_financeiro_expostos`): RLS ativado, sem políticas, mesmo padrão da limpeza de 11/08.

Estafeta nunca era chamado — drivers.id vs drivers.user_id (2026-08-16, Claude.ai via MCP)
- [stated] Sintoma do Danilo: pedido da cliente Isabel Rebelo (Auchan, 12,09€, dinheiro) chamava sempre o telemóvel dele e nunca o do Valdemir; pediu para pôr o pedido no Valdemir automático, sem ele ter de aceitar.
- CAUSA RAIZ (achada por MCP): `notify-driver` lia `drivers.fcm_token` por `drivers.id` e, no fallback, procurava `driver_push_tokens.user_id = <drivers.id>`. Só funciona para quem tem id == user_id (as 2 contas do Danilo). Valdemir Vasconcelos (drivers.id `e1d81564-91f6-40b4-bf1e-f2710e44c368`, user_id `e355fde0-b634-48ba-bce1-e2a4466c4cc2`) e Erika devolviam sempre `no_fcm_token` → push nunca saía, apesar de terem token activo em driver_push_tokens.
- FEITO por MCP: (1) `drivers.fcm_token` preenchido a partir do token activo mais recente de `driver_push_tokens` (Valdemir + Erika); (2) `notify-driver` v33 deployed (deploy nº 35, verify_jwt=false mantido) — aceita driverId como drivers.id OU drivers.user_id e o fallback procura pelos dois, com log de diagnóstico no no_fcm_token.
- FEITO por MCP: pedido `4db5882d-41b6-4079-bfb5-f4b517baa9cd` reatribuído do Danilo para o Valdemir sem oferta (assigned_driver_id + driver_phone), status driverAccepted mantido. Seguro contra o cron: `bora_dispatch_maintenance` só toca em status='callingDriver' AND assigned_driver_id IS NULL.
- REGRA APURADA (não esquecer): `orders.assigned_driver_id` tem de levar **drivers.id**, não user_id — a RLS `orders_update_driver` só aceita drivers.id; com user_id o estafeta VÊ o pedido mas não consegue avançá-lo (recolhido/entregue). A RLS de SELECT aceita os dois, o que esconde o erro.
- ⚠️ POR VERIFICAR, mesma família de bug: `fn_award_tokens_on_delivery` (tem comentário explícito "driver_id continua UUID em drivers.user_id"), `fn_credit_driver_on_delivery` e `apply_driver_cash_settlement` usam `assigned_driver_id` como se fosse user_id. Com estafeta em que id <> user_id, tokens e saldo podem ir para a chave errada — conferir quando o Valdemir entregar o 1.º pedido.
- [stated] PENDENTE painel admin: não há botão para reatribuir pedido a outro estafeta — foi preciso SQL. Danilo quer isso no painel.

