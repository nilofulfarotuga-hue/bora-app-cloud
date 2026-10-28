---
id: memoria-claude-ai-prompt-talao-confirmar-loja-saldo-2026-10-28
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-28
zona: verde
confianca: alta
estado: atual
---

# PROMPT 28/10 — Confirmar do talão, nome da loja, dinheiro a cobrar com saldo/tokens, reembolso no cancelamento (100% saldo ou meio original) — POR COLAR: Claude Code do PC sem sessão (precisa de voltar a entrar)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-talao-confirmar-loja-saldo-2026-10-28`, origem `claude-ai`, atualizada em 2026-10-28T18:30:48.97564+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt talao confirmar loja saldo 2026 10 28 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️

MOTOR: Opus 5.5 (o desta sessão) · PORTA: Claude Code no PC do Danilo (ambiente "Este computador", pasta do repo bora-app-cloud, ramo autonomous-night-2026-04-29)
MISSÃO: talao-auchan-divan-2026-10-28 (e2e_log: fluxo `talao-auchan-divan-2026-10-28`, um passo por bloco)
ORQUESTRADOR: entra pelo CEO-AI (`.claude/skills/ceo-ai/`) e segue a skill `protocolo-missao-bora`. Esquadrão pequeno: líder + estafeta/app + admin (paridade) + juiz.

AUTORIZAÇÃO (texto literal do Danilo, 28/10/2026 17:51): "Investiga tudo. Conserta as coisas que tá errado. Eu não quero ter dor de cabeça."
Vale para consertar os erros desta missão (repor o comportamento certo). NÃO vale para mudar preços, taxas, comissões nem para mexer no dinheiro de clientes antigos — isso fica com o Claude.ai e o Danilo.

CARTA DE AUTONOMIA: decides sozinho, nunca terminas o turno à espera, saltas o que estiver bloqueado (regista em docs/TRANCAS.md) e segues, reportas pelo Telegram, e no fim crias tu a continuação se faltar algo (cortex_nova_ordem). Erro que encontres fora do que está aqui: REPORTA no e2e_log e no relatório, não corrijas calado.

ARRANQUE: lê `erros-aprendidos`, `regras-do-danilo`, `livro-indice` e o digest mais recente (claude_ai_memoria), o business_rules e a página do livro `livro-areas-talao-nao-parceiro`. Antes de mexer no código, vê o estado local do PC: há trabalho pronto e ainda NÃO publicado (ramo/worktree `consertos-boom-2026-10-27` em C:\BoraLocal\wt-consertos-boom-27-10, missão `melhorias-paridade-2026-10-26` commit 940dfe6c, `nome-cliente-e-valor-caixa-2026-10-25`, `sem-margem-nao-parceiro-2026-10-25`). Trabalha por cima do que vai ser publicado, sem perder nada disso. `git add` só por caminho, nada de WIP de outras sessões.

O QUE ACONTECEU (hoje, 17:23–17:51, pedido f293752c-29d6-4278-a013-825cb1d4674a, Auchan, cliente Divan, a dinheiro, estafeta = o Danilo):
1. No ecrã "Foto do talão + valor pago" ele tirou a foto, escreveu o valor e carregou em Confirmar várias vezes: nada acontecia e não saía da folha. Prova: entre as 17:40 e as 17:43 nenhum pedido do telemóvel dele chegou ao servidor (nem `upload-receipt` nem a RPC) — edge_logs.
2. No cartão do pedido aparecia só a morada da recolha ("Centro Comercial La Vie, Av. dos Bombeiros…") sem "Auchan". O estafeta não sabe em que loja comprar.
3. O Claude.ai destravou o pedido pelo servidor (talão 7,88 € gravado em order_receipts_v2 com foto "pendente", estado onTheWay). Ao fazê-lo copiou a fórmula da RPC e pôs o dinheiro a cobrar em 14,35 € — o cliente tinha pago 10,31 € com saldo e 0,73 € com tokens, devia 3,31 €. Já corrigido no pedido (cash_total_due = 3,31) e na RPC (ver Bloco C).

BLOCO A — O botão Confirmar do talão que não faz nada (app do estafeta)
- Onde: `lib/screens/driver_map_screen.dart`, `_ReceiptCaptureSheetState._onSubmit` (≈ linha 4026).
- Causa provada pelo código + foto do ecrã: o campo tinha "7. 88" (com espaço). `double.tryParse` falha → mostra "Valor do talão inválido." por `ScaffoldMessenger.of(context)`, que aparece no Scaffold de TRÁS, escondido pela própria folha. O estafeta carrega e nada acontece (é o "volta ao mesmo ecrã sem dizer porquê" de 10/09, por outra causa).
- Consertar:
  a) Leitura tolerante do valor: tira espaços (normais, finos, nbsp), "€" e letras; aceita vírgula ou ponto; "7. 88", "7,88", "7.88 €", " 7,88" dão 788 cêntimos.
  b) No campo, só deixa escrever dígitos e um separador decimal, no máximo 2 casas (inputFormatters).
  c) Qualquer erro aparece DENTRO da folha (errorText do campo ou texto vermelho por cima do botão), nunca num SnackBar por trás. O mesmo para o erro da câmara em `_takePhoto`.
  d) `ReceiptUploadService.uploadReceipt` (`functions.invoke('upload-receipt')`) e `TalaoNaoParceiroService.finalizar` (rpc) não têm tempo limite: se a rede cair, roda para sempre. Põe tempo limite (30 s envio da foto, 20 s RPC) com mensagem clara e a foto guardada para tentar de novo (já existem `_talaoGuardado` e `_caminhoTalaoGuardado`).
  e) Depois do sucesso a app faz `order.cashTotalDue = null` (≈ linha 3839) e o cartão mostra o total bruto até o tempo real chegar. Usa o `cash_total_due_cents` que a RPC devolve.
  f) Procura o mesmo padrão (aviso por SnackBar dentro de folha/bottom sheet que fica escondido) nos outros ecrãs do estafeta. Os que travam compra, recolha ou entrega: consertar igual. Os outros: reportar.

BLOCO B — Nome da loja em todos os ecrãs do estafeta
- Onde: `_SingleOrderAddresses` (`driver_map_screen.dart` ≈ linha 2368) mostra só `order.pickupAddress`. O multi-paragem (`_StopRow`) já faz bem: rótulo "Recolha", nome da loja a negrito com distância, morada por baixo.
- Consertar: o pedido único fica igual ao `_StopRow` — "Recolha" + nome da loja (vendor_name) a negrito + morada; "Entrega" + nome do cliente (usa o widget `cliente_nome_destaque` da missão de 25/10 se já estiver no teu estado local) + morada.
- Verifica TODOS os sítios onde o estafeta vê a recolha (oferta, cartão do pedido, lista de compras, Favor, chat, navegação): o nome da loja tem de estar sempre lá, como na Glovo e na Uber Eats (nome da loja + morada). Não inventar nada além disso.

BLOCO C — Dinheiro a cobrar depois do talão (servidor já corrigido pelo Claude.ai, ~18:00, por MCP)
- Erro: `finalizar_talao_nao_parceiro` (ramo dinheiro) recalculava `cash_total_due` a partir do total BRUTO e apagava o desconto do saldo e dos tokens. Já aconteceu em 5 pedidos (09/09, 14/09, 24/09, 03/10 e hoje).
- Feito em produção: migração `talao_dinheiro_respeita_saldo_e_tokens_20261028` (backup da função antiga na tabela `bkp_fn_finalizar_talao_nao_parceiro_20261028`). Agora parte do `cash_total_due` que o create_order gravou e soma só as diferenças do talão (sacos, itens, peso); se der negativo regista em order_lifecycle_errors para rever no painel.
- Tarefas:
  1) Grava esta migração no repo (`supabase/migrations/`) com a definição completa tirada de `pg_get_functiondef` — a produção já está certa, não a apliques de novo.
  2) Verifica `finalize_errand_purchase` (Favores) e `finalize_storeshopping_purchase_v2` (antiga): se também recalculam o dinheiro a cobrar a partir do bruto ignorando saldo/tokens, corrige com a mesma regra (backup `bkp_fn_<nome>_20261028`, migração no repo, prova por SELECT).
  3) Prova ponta a ponta no emulador, a DINHEIRO, com pedido de teste (`is_test_order`) num mercado não-parceiro pago em parte com saldo e tokens: o valor a cobrar no ecrã do estafeta tem de ser total − saldo − tokens antes e depois do talão; e com um artigo marcado "não há", tem de descer o valor desse artigo.
  4) Painel admin (PT-BR): no detalhe do pedido tem de aparecer a conta linha a linha — total, saldo usado, tokens usados, dinheiro a cobrar, valor do talão. Se já existe (`admin_order_cash_breakdown` / `admin_get_order_payment_breakdown`), confirma que bate com estes números; se não, acrescenta.

BLOCO D — Saldo e tokens nos cancelamentos (investigar, consertar, provar)
- Achado: a 03/10 o pedido Burger King `dcc8c509` (Divan) usou 5,51 € em tokens, o MB Way falhou, e o cancelamento (client-cancel-order v28) devolveu 5,51 € como SALDO LIVRE apesar de os tokens nunca terem sido gastos; 2 minutos depois os mesmos tokens foram usados no pedido `b18d2675`. O v29 (05/10) só conta tokens com `tokens_applied_count > 0` e fechou essa fuga.
- Problema que fica: `tokens_applied_count` fica 0 mesmo quando os tokens SÃO gastos (pedido f293752c: 146 tokens gastos às 17:23, contagem 0). Se o cliente cancelar um pedido em que gastou tokens, provavelmente perde-os.
- Regra a pôr: devolve-se exatamente o que se tirou, da mesma forma. Tokens gastos voltam como TOKENS (com a validade que tinham), nunca como saldo livre; tokens que não chegaram a ser gastos não se devolvem; saldo volta como saldo; MB Way/cartão como já está.
- Faz: acha onde os tokens são gastos (create_order para dinheiro, webhook para cartão/MB Way) e grava `tokens_applied_count` certo; ajusta o cancelamento para devolver tokens como tokens. Zona protegida (bora_tokens, client-cancel-order): backup antes, migração no repo, teste com pedido de teste em dinheiro e em MB Way (falhado e pago), prova por SELECT. Se a tranca recusar, regista e deixa tudo pronto no relatório com a frase "⚠️ ISTO MEXE EM DINHEIRO — está tudo pronto".
- Não mexer no saldo de nenhum cliente real (nem do Divan): isso é com o Claude.ai e o Danilo.

BLOCO E — Outros erros vistos hoje (reportar; consertar só se for simples e seguro)
- Desde pelo menos as 17:25, a cada 1–2 segundos chegam `POST /rest/v1/rpc/cortex_proposal_sync_upsert` e `cortex_list_approved_pids` com 401 (user-agent curl/8.5.0): algum script (VPS ou PC) com chave errada a martelar o servidor. Acha qual é e conserta a chave ou pára-o.
- O repositório bora-app-cloud ainda aceita leitura anónima (público). A 25/10 o Danilo decidiu que tem de ficar privado. Só reporta o estado.

FECHO
- Juiz: `python .claude/juiz/anti_trapaca.py`, `flutter analyze` limpo, `flutter test` verde, rubrica UI.
- Provas no emulador (capturas): escrever "7. 88" passa e segue para a navegação; erro aparece dentro da folha; nome da loja visível no cartão do pedido; valor a cobrar certo com saldo e tokens.
- PUBLICAÇÃO: o Danilo publica as 3 plataformas uma vez por semana; urgente só com o "publica" dele. Junta isto ao que está pronto para a próxima publicação e PÁRA à espera. Se eu (Claude.ai) colar aqui "publica", publicas nas 3 (Play Store, App Store/TestFlight, web), sem mexer no versionCode, e provas as 3 (Android, iPhone, web) com o talão e o nome da loja.
- Regista: e2e_log (um passo por bloco), digest em claude_ai_memoria (`digest-2026-10-28-talao-auchan`), este prompt no Obsidian (C:\Users\danil\Desktop\Bora) e na memória (data, sessão, scope, estado). Relatório final curto, em texto corrido: o que ficou feito, o que falta.

/ctx doctor
/ctx stats

