---
id: estado-atual-consolidado
tipo: conceito
origem: [auto-gerado por _tools/consolidador.py]
ultima_confirmacao: 2026-09-13
zona: verde
confianca: auto
estado: atual
---

# ESTADO ATUAL CONSOLIDADO — o que ja sabemos

> **AUTO-GERADO** por `_tools/consolidador.py` em **2026-09-13 22:33**. Nao editar a mao.
> Fontes: 27 licoes vigentes · 0 itens em aberto · 25 regras · memoria claude.ai: ok (4 paginas). Toggle: ok.
> Se esta pagina tiver mais de 24h, trata-a como possivelmente desatualizada.

## 0. MEMORIA DA CLAUDE.AI — regras-do-danilo manda em tudo
_Fonte: public.claude_ai_memoria (ok (4 paginas)). Antes de decidir, le a tabela inteira via MCP (ou cortex_buscar "regras do danilo")._

- **regras-do-danilo** (2026-09-13): AGENTE DE CLIQUE (28/08, repetiu chateado): ele NÃO faz nada à mão em painéis web. Tem agente de clique no PC e dá permissão total. Painel externo (Cloudflare, Supabase, Stripe, Google, Meta, Apple) = o EXECUTOR entra e faz; se sobrar autorização que só ele pode dar, o executor deixa a página aberta e ele só carrega no botão. Nunca dar caminho de menus. Passo-a-passo de painel para ele fazer = errado, vai no prompt para o executor. RESPOSTAS: o mais curtas e diretas possível ("como pra criança de 5 anos"), português claro, sem jargão; corrige firme verbosidade, repetição ou sugestão que lhe exija trabalho manual. Não é de terminal nem de ler diffs. NUNCA dizer quando dormir/parar nem presumir a hora dele. Passos só dele: lista didática, mínimo de cliques. NÃO vale mandá-lo procurar e clicar um ficheiro no PC, nem com caminho exato — os .ps1 abrem no Bloco de Notas. Passo local com administrador: o executor dispara a elevação (Start-Process -Verb RunAs) e ele só carrega em Sim. MENSAGENS NOUTRA LÍNGUA: mensagem RECEBIDA em inglês → traduzir sempre o que a pessoa disse ANTES de qualquer resposta; mensagem redigida para ele ENVIAR → cartão só com o inglês, tradução ANTES do cartão, em texto normal corrido (ele OUVE as mensagens). "NÃO ME MANDES LER" (01/08): não revê listas nem decide itens técnicos — o motor lê, analisa e decide; ele só ouve "foi feito isto, e é bom por isto". Nada de aprovação de migrations/propostas/ficheiros; a barreira automática (dinheiro real volta pelo Telegram) é a rede de segurança. FORMATO PROMPTS: prompt de missão nova sempre como ficheiro copiável, nunca texto solto. Continuação de sessão aberta: texto literal para colar, sem ficheiro nem ritual. Todo prompt para Claude Code começa com ⚠️ MODO PROTECÇÃO TOTAL ⚠️, invoca o orquestrador CEO-AI em .claude/skills/ceo-ai/, indica MOTOR + PORTA no topo, diz em letras claras "abre SESSÃO NOVA no Claude Code na pasta X" (bora-app-cloud = app Bora e VPS/redes; guarda-fc-site = site do clube;…
- **estado-2026-09-13** (2026-09-13): FEITO/BOM: A Bora foi APROVADA pela Apple a 12/09 11:23 UTC (build 115, Apple ID 6809954739, pt.boraapp.bora, PT+BR), lançamento automático na App Store; ios_hide_nonpartner_logos voltou a false a 13/09 (logos dos mercados de volta no iPhone). VPS paga a 13/09 (21,51 €/mês, vence ~dia 10 de cada mês; 19 dias de janela antes de perder dados). Grupos do Facebook automáticos a correr (fluxo redes-grupos-auto, 49 passos entre 08 e 13/09). min_order_cents=1500 (pedido mínimo 15 € nos mercados desde 09/09). Guarda FC: site no ar com atualização automática na nuvem; pago 1.550 € de 1.950 €, faltam 400 € (~24/09); jogo Guarda FC–Camacha 13/09 11h em casa. INCIDENTES 11-12/09 (arranjados pelo ChatGPT, POR AUDITAR): (1) pedido Goola Açaí ae711470 de 11/09 19:19, MB Way 16,16 €, só entregue às 20:57 (1h38) — pedido de parceiro ficou em 'preparing' sem chamar estafeta. (2) envio de encomenda bba0f503 de 12/09 17:12, 7,07 € MB Way, atribuído ao Valdemir, cancelado às 17:31 "sem culpa da cliente —…
- **digest-2026-09-13-janela-1** (2026-09-13): Estado às 22:00 (a janela ainda está a correr o autoteste; versão final segue no fecho). Feito com prova: 17 migrações de produção de 09 a 13/09 espelhadas no repo com timestamp e SQL iguais (md5 23/23). Auditoria das migrações do ChatGPT de 12/09: CHECK dos 10 estados confirmado; auto-dispatch de parceiro e order_status_events a funcionar; dois…
- **digest-2026-09-13-janela-3** (2026-09-13): O que funciona agora. A VPS voltou a 13/09 e ficou de pé: o Motor Bora arrancava antes da bridge docker e ficava só em 127.0.0.1, por isso todas as rondas dos agentes davam Connection error; o unit passou a arrancar depois do docker e uma tarefa de teste inserida em despacho com origem claude-ai fechou feita em 13 segundos. A ponte do contentor…
## 1. ARMADILHAS — nao repetir estes erros

- **Cron que injeta ordem na fila a cada sinal = spam por construção** — um agente de análise/aprendizagem (evolution-engine ou qualquer futuro · "meta-agente") nunca dispara ordem nova na fila via cron. Desenho correto, reativo: · (1) cada missão já fecha com relatório em inbox/ (convenção "Saída padrão") — o próximo passo _(licao-spam-ordens-autoreferencial)_
- **dropdown de autocomplete atrás do teclado num bottom-sheet: fix no widget partilhado, não por ecrã** — Bottom-sheet com campo de texto + lista por baixo → SEMPRE: · showModalBottomSheet(isScrollControlled: true, ...), · envolver o conteúdo em Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)), _(licao-autocomplete-teclado)_
- **um serviço/widget criado mas com ZERO chamadores é "casca sem fio", não é "feito"** — Antes de dar por feita uma feature que introduz um serviço/widget/RPC novo, **procura os call · sites**: git grep NomeDoNovo (ou o equivalente). Zero chamadores = não está feito, é casca. · Uma peça só entrega valor quando algo a INVOCA num caminho que o utilizador percorre. Declara _(licao-casca-sem-fio)_
- **antes de semear dados, lê as CHECK constraints da tabela (valores enumerados)** — Antes de INSERT de dados-semente em colunas que "cheiram a enum" (zona, shape, status, tipo, · reason), consulta as constraints: · SELECT conname, pg_get_constraintdef(oid) _(licao-check-constraint-antes-de-semear)_
- **restaurants tem DUAS colunas de dono (user_ e user_id); ler/gravar sempre AMBAS** — Enquanto as duas colunas coexistirem: · 1. Todo insert/update de restaurants grava o dono nas DUAS (user_ E user_id). · 2. Toda RPC nova que filtra por dono lê AMBAS: WHERE user_ = auth.uid() OR user_id = auth.uid(). _(licao-dual-owner-column)_
- **EXCEPTION WHEN OTHERS THEN NULL numa função = falha invisível permanente** — Nunca EXCEPTION WHEN OTHERS THEN NULL em código que faz efeito colateral (notificar, · cobrar, escrever). Se a intenção é "não rebentar a transação principal por causa de uma · notificação falhada", então CAPTURA e REGISTA — não descartes: _(licao-exception-when-others-null)_
- **is_online = true sem TTL = dispatch para mortos (presença precisa de cron de expiração)** — Toda presença/online-status precisa de TTL por heartbeat: um cron que expira quem não bate · o coração há X minutos. · UPDATE drivers SET is_online = false _(licao-heartbeat-fantasma)_
- **notificação enviada pelo canal/type errado = entregue mas o app não a roteia (nada aparece)** — Cada público (cliente / estafeta / parceiro / profissional) precisa de um canal ou de um · type que o SEU app saiba rotear. Reutilizar a função de outro público só funciona se o · type for genuinamente respeitado ponta-a-ponta (servidor emite → app roteia por esse type). _(licao-notify-canal-errado)_
- **um parser que às vezes devolve 0 bytes faz o orquestrador diagnosticar a causa errada** — Um parser/adaptador nunca pode devolver 0 bytes. Se não sabe o que dizer, diz o que · aconteceu: EXECUTOR-PAROU: subtype=... turns=... custo=.... Silêncio é lido como outra coisa · "SAIDA-VAZIA" não é uma causa — é um sintoma de várias (timeout de relógio, teto de _(licao-parser-mudo)_
- **RPC RETURNS <tabela> (tipo composto) devolve uma row de NULLs quando vazia, não NULL** — No servidor: para "0 ou 1 resultado", preferir RETURNS SETOF <tabela> (devolve 0 linhas · quando vazio, que o cliente vê como lista vazia) OU RETURN NULL explícito quando o `SELECT · INTO não encontra (IF NOT FOUND THEN RETURN NULL; END IF;`). _(licao-rpc-composite-null-row)_
- **Robustez do loop autónomo — 5 causas-raiz confirmadas numa só semana (2026-07-13)** — ao ler stdin de um processo filho via pipe/SSH no Windows, usar · System.IO.StreamReader sobre [Console]::OpenStandardInput() (lê o pipe redirecionado · diretamente), nunca ReadLine() puro — e sempre envolver a leitura remota com timeout N do _(licao-robustez-loop-autonomo-2026-07-13)_
- **Não enfraquecer asserções para fingir "verde" (o Juiz apanha por git diff)** — consertar o CÓDIGO sob teste; a asserção só se fortalece, nunca se · enfraquece/apaga/skipa. Numa tarefa de conserto, o código sob teste tem de mudar — senão é · conserto-fantasma (PHANTOM_FIX, também REJEITA). _(licao-asserts-weakened)_
- **Getter com context.watch não pode ser chamado em callbacks (Flutter/Provider)** — em getters/helpers que também são usados em callbacks, usar · context.read<T>(); reservar context.watch<T>() só para o corpo do build. · Evidência: fix aplicado em _(licao-context-watch-getter)_
- _(+1 nao couberam no teto desta seccao)_

## 2. LICOES VIGENTES POR CATEGORIA

- **base-de-dados/sql**
  - policies de Storage NUNCA consultam auth.users (e "funciona no bucket X" não prova autenticação) _(licao-storage-policy-auth-users)_
- **cerebro/memoria**
  - confirmar que a ferramenta existe antes de prometer o passo _(licao-confirmar-ferramenta-antes-de-prometer)_
  - num sync, auditar a FONTE, não só o destino _(licao-verificar-fonte-de-sync)_
- **geral**
  - o teste E2E NUNCA trava em silêncio: falhou → tira foto + regista + segue _(licao-teste-nunca-trava-tira-foto-e-segue)_
  - comando custom no container: master no VOLUME, instalação re-garantida _(licao-comando-custom-container-master-no-volume)_
  - mapear onde vive um guard antes de o testar _(licao-onde-vive-a-trava)_
  - antes de reexecutar, verificar o estado real (verificar > reexecutar) _(licao-verificar-estado-antes-de-reexecutar)_
- **infra/windows**
  - docker exec: escolher o user certo _(licao-docker-exec-user-hermes)_
- **orquestracao/loop**
  - "o carteiro morreu" e "o carteiro está vivo mas a tarefa não cabe no orçamento" são coisas diferentes _(licao-executor-vivo-mas-tarefa-pesada-esgota-tentativas)_
  - o classificador de zona (verde/vermelha) deve ler INTENÇÃO, não só palavras _(licao-classificador-zona-menos-sensivel-a-palavras)_
  - O loop fecha-se pelo agente que CLICA, sem custo de API _(heartbeat-sem-api-via-browser)_
  - "a ponte do loop não devolve output" (o executor nem ARRANCA para tarefas grandes) _(licao-ponte-loop-nao-devolve-output)_
  - anti_trapaca.py com base default numa branch longa = falso-positivo _(licao-anti-trapaca-base-stale)_

## 3. EM ABERTO / POR FECHAR



## 4. REGRAS DE NEGOCIO EM VIGOR
_Ordem: dinheiro-em-movimento > preco-de-catalogo > seguranca > resto._
_[CM]=CLAUDE.md · [BR]=business_rules.md_

- [CM] Follow: Model → Store → Screen
- [CM] NEVER use String for status
- [CM] ALWAYS use OrderStatus enum:
- [CM] created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered
- [CM] NEVER break existing working features
- [CM] ALWAYS maintain Supabase compatibility
- [BR] refund_amount NUNCA pode exceder stripe_charge_cents + wallet_applied_cents + tokens_applied_value_cents
- [BR] Agente NUNCA calcula dinheiro, refunds, créditos ou estimativas financeiras → escalar via skill HUMAN_REQUEST.
- [BR] Orders cancelados historicamente NUNCA receberam tokens em refund
- [BR] Ganhos operacionais (€3.80 + km + €0.80 + 30%) sempre payout semanal, NUNCA reembolso.
- [BR] Buffer cartão/MBWay: payment_buffer_total = fees_total + round(estimativa × errand_buffer_multiplier) (errand_buffer_multiplier=1.2). NUNCA ×1.15 (C4).
- [BR] Preços NUNCA partilhados — cada mercado guarda o seu preço real, actualizado na mesma operação do scraper.
- [BR] 4. NUNCA deixar produto sem preço. Se nenhuma das duas fontes tem preço → DELETE o produto (não importar). Não criar entradas is_available=false/price=NULL que nunca serão vendidas — poluem o catálogo.
- [BR] 7. NUNCA puxar PREÇO de Glovo como fonte primária. Glovo aplica markup próprio — usar só nome+imagem+categoria como fonte. Glovo só entra na coluna de preço quando é fallback explícito (regra 3) e o número é dividido por 1.15.
- [BR] Preço sempre PURO do site oficial. 15% markup aplicado em runtime por pricing_calculate (já existente em §27/§2.4). NUNCA guardar preço com markup embutido.
- _(+10 nao couberam no teto desta seccao)_
