# ESPEC — casa-manutencao-2026-10-30

Lê isto primeiro em cada sessão desta missão. Acrescenta cada decisão nova com data.

## Objetivo
Categoria nova "Casa" (Casa & Manutenção, faz-tudo) no Bora: o cliente pede uma tarefa de preço
fixo do catálogo ou um orçamento com fotos (até 3 profissionais respondem, o cliente escolhe); o
profissional recebe ofertas por rotação, orça, faz o trabalho (a caminho, cheguei, iniciar, fotos
antes/depois, concluir) e recebe no acerto semanal; o admin aprova ofício a ofício e gere tudo.
Modelo: TaskRabbit (preço fixo) + Airtasker (orçamento). Nunca pagar por contacto.

## Quem vai usar
Clientes da Guarda (app PT-PT), profissionais de ofícios sem título (app PT-PT), o Danilo no
painel admin (PT-BR).

## Fronteiras (o que NÃO se toca)
- Zonas protegidas: dispatch_engine, pricing_service.dart, finalizePurchase, bora_tokens,
  stripe-webhook, RLS de orders/wallets/ledger. Nenhuma tabela existente de dinheiro é alterada.
- Cartão e MB Way: só PROPOSTA (função de pagamento e ramo do webhook em docs/propostas). Nada de
  deploy de funções de pagamento.
- Preços, comissões, promoção dos 5 primeiros: nascem como PROPOSTA em platform_settings (casa_*)
  e no catálogo; o servidor recusa pedidos reais de preço fixo e o acerto recusa calcular comissão
  enquanto `casa_valores_autorizados.autorizado` não for true (só muda com o "autorizo" datado do
  Danilo, pela função admin_casa_autorizar_valores, que regista o texto e a data).
- Categoria nasce DESLIGADA (`casa_enabled=false`).
- Não publicar: ramo próprio, sem push para o ramo de produção.
- Árvore principal do PC e o worktree das gorjetas: não se tocam.

## Decisões já tomadas (Danilo 30/10 21:38, "1 2 3 4 5 eu aceito as suas sugestões")
1. Fase 1 só ofícios sem título: montagem de móveis, pendurar/fixar, pequenas reparações,
   torneira/autoclismo/sifão à vista, jardinagem e quintal, pequenas mudanças com carrinha.
   Fase 2 (eletricidade, gás, pladur/alvenaria, pintura): estrutura pronta mas desligada; só abre
   com documento DGEG/IMPIC aprovado pelo admin.
2. Comissão 15% ao profissional só em serviço concluído; 2 meses sem comissão aos 5 primeiros
   profissionais; o cliente não paga taxa extra. Preços dos fixos = pontos de partida da proposta,
   editáveis no painel, válidos só depois do "autorizo".
3. Dinheiro em mão até max_cash_amount_cents (40 €); acima só cartão/MB Way, retido até o cliente
   confirmar ou 24 h.
4. Telefone do cliente só depois de aceite e pago; chat e botão de ligar só a partir daí.
5. Ladrilho: "Casa".
Também: cancelamento por escalões (tempos nas definições), garantia de refazer, avaliação só de
quem pagou, pedido de orçamento grátis com até 3 respostas, valor extra só com consentimento.

## Decisões técnicas desta sessão (30/10, Claude Code)
- Papel técnico `handyman`; tabelas com prefixo `casa_`; nome que a pessoa lê: "Casa e manutenção".
- Definições em platform_settings com prefixo `casa_` (como cleaning_*/carwash_*), categoria 'casa'.
- "Aceite e pago" (decisão 4): cartão/MB Way = pagamento retido; dinheiro = trabalho aceite
  (no dinheiro não há pré-pagamento). A partir daí o telefone e o chat aparecem.
- Pedidos de teste (`is_test`) dos testadores correm mesmo com valores por autorizar, para as provas.
- 31/10: a tranca bloqueou a chave `casa_stripe_enabled`; não existe. Cartão/MB Way na Casa = só
  proposta (docs/propostas). `casa_config().pagamento_cartao` devolve sempre false nesta fase.

## CONTRATO DO SERVIDOR (31/10 00:40) — nomes fixos; a app chama só isto

Papel técnico `handyman`. Categoria nas notificações e no gancho de abrir trabalho: `casa`.
Tipos de aviso: `casa_offer` (oferta/convite, toque persistente, só dados) e `casa_status`.
Data do aviso: {type, title, body, bookingId (= id do pedido), kind}.
Baldes privados: `handyman-documents` (caminho `<uid>/<tag>_<ms>.<ext>`) e `casa-fotos`
(caminho `<uid>/<pedido_id>/<tipo>_<ms>.jpg`). Edge de avisos: `notify-handyman`.
Erros: RAISE EXCEPTION com código curto em minúsculas (ex. `casa_desligada`, `valores_por_autorizar`,
`dinheiro_acima_do_limite`, `sem_permissao`, `estado_invalido`, `pagamento_cartao_indisponivel`,
`foto_depois_em_falta`, `limite_fotos`, `orcamentos_completos`, `nao_e_profissional`,
`antecedencia_minima`, `morada_em_falta`). A app mostra texto PT-PT por código.

### JSON do pedido (`pedido`)
{id, servico_id, servico_nome, oficio, oficio_nome, modo ('fixo'|'hora'|'orcamento'), quantidade,
 descricao, respostas{}, morada{street,city,postal,lat,lng}, scheduled_at, duracao_min, estado,
 payment_method, payment_status, preco_cents, extras_cents, total_cents, ganho_cents (só pro/admin),
 comissao_cents (só admin), is_test, created_at, accepted_at, on_the_way_at, arrived_at, started_at,
 done_at, confirmed_at, cancelled_at, cancelled_by, cancel_reason, cancel_fee_cents, rating_cliente,
 comentario_cliente, rating_profissional, refazer_pedido_em, garantia_ate,
 pode_contactar (bool: aceite e pago — cartão/MB Way retido, ou dinheiro aceite),
 fotos[{id,tipo,storage_path,created_at}], extras[{id,valor_cents,motivo,estado,created_at}],
 orcamentos[{id,preco_cents,inclui,materiais,materiais_incluidos,prazo,duracao_min,estado,expira_em,created_at,
             profissional{id,name,photo_url,rating_avg,ratings_count,jobs_done,selos[]}}] (cliente/admin),
 profissional{id,name,photo_url,rating_avg,ratings_count,jobs_done,selos[],phone (só se pode_contactar)},
 cliente{nome, phone (só se pode_contactar)} (só para o profissional/admin)}
Estados: aguarda_pagamento, procura, orcamentos, aceite, a_caminho, chegou, em_curso, concluido,
confirmado, disputa, cancelado, expirado. Selos: 'documentos_verificados','seguro','dgeg','impic'.

### Cliente (authenticated)
- casa_config() → {visivel, enabled, valores_autorizados, pagamento_cartao (false nesta fase),
  max_cash_cents, max_fotos, min_lead_hours, cancel_free_hours, cancel_half_hours, garantia_dias,
  quote_max_pros, oficios[{codigo,nome,descricao,fase,ativo}], servicos[{id,oficio,nome,descricao,modo,
  preco_cents,unidade('tarefa'|'movel'|'hora'),min_quantidade,max_quantidade,duracao_min,
  perguntas[{id,texto,tipo('texto'|'escolha'),opcoes[]}]}]}  (também anon: visivel = enabled)
- casa_criar_pedido(p_servico_id uuid, p_quantidade numeric, p_descricao text, p_respostas jsonb,
  p_address_street text, p_address_city text, p_address_postal text, p_lat double precision,
  p_lng double precision, p_scheduled_at timestamptz, p_payment_method text, p_idempotency_key text) → pedido
  (orçamento: p_payment_method ignorado; escolhe-se ao aceitar o orçamento)
- casa_adicionar_foto(p_pedido_id uuid, p_tipo text, p_storage_path text) → {id}
  (cliente: 'problema'; profissional: 'antes','depois','extra')
- casa_meus_pedidos() → [pedido] · casa_pedido(p_pedido_id uuid) → pedido (cliente, profissional atribuído ou admin)
- casa_aceitar_orcamento(p_orcamento_id uuid, p_payment_method text) → pedido
- casa_responder_extra(p_extra_id uuid, p_aceitar boolean) → pedido
- casa_confirmar_conclusao(p_pedido_id uuid) → pedido
- casa_pedir_refazer(p_pedido_id uuid, p_motivo text) → pedido
- casa_avaliar(p_pedido_id uuid, p_nota integer, p_comentario text) → {ok}
- casa_cancelar_simulacao(p_pedido_id uuid) → {cancel_fee_cents, escalao('gratis'|'metade'|'total')}
- casa_cancelar(p_pedido_id uuid, p_motivo text) → {ok, cancel_fee_cents}
- casa_enviar_mensagem(p_pedido_id uuid, p_texto text) → {id}
- casa_mensagens(p_pedido_id uuid) → [{id,sender_role,message,created_at}] (só com pode_contactar)

### Profissional (authenticated)
- casa_candidatura(p_name text, p_phone text, p_email text, p_photo_url text, p_bio text, p_nif text,
  p_base_address text, p_base_lat double precision, p_base_lng double precision, p_service_radius_km numeric,
  p_has_van boolean, p_has_tools boolean, p_oficios text[],
  p_disponibilidade jsonb [{weekday 0-6 (0=domingo), start 'HH:MM', end 'HH:MM'}]) → perfil (como casa_meu_perfil)
- casa_registar_documento(p_tipo text, p_oficio text, p_storage_path text, p_numero text, p_validade date) → {id}
  tipos: cartao_cidadao, seguro_acidentes, seguro_rc, dgeg_eletricidade, dgeg_gas, impic, outro (também serve para reenviar)
- casa_meu_perfil() → null se não for profissional; senão {perfil{id,name,phone,email,photo_url,bio,nif,
  base_address,base_lat,base_lng,service_radius_km,has_van,has_tools,approval_status,rejection_reason,
  is_active,rating_avg,ratings_count,jobs_done,sem_comissao_ate}, oficios[{codigo,nome,fase,documento_exigido,
  estado,ligado,motivo}], documentos[{id,tipo,oficio,estado,validade,motivo,created_at}],
  disponibilidade[{weekday,start,end}], aceita_papel, comissao_pct, valores_autorizados}
- casa_definir_disponibilidade(p_slots jsonb) → {ok} · casa_ligar_oficio(p_oficio text, p_ligado boolean) → {ok}
  (ligar/desligar o papel inteiro: definir_preferencia_papel('handyman', bool), que já existe)
- casa_minhas_ofertas() → [{pedido_id, tipo('oferta'|'convite_orcamento'), oficio, oficio_nome, servico_nome,
  modo, quantidade, descricao, respostas, localidade, distancia_km, scheduled_at, duracao_min,
  ganho_cents (null no orçamento), total_cents, expira_em, fotos[storage_path], orcamentos_recebidos, ja_orcei}]
- casa_aceitar_oferta(p_pedido_id uuid) → pedido · casa_recusar_oferta(p_pedido_id uuid) → {ok}
- casa_enviar_orcamento(p_pedido_id uuid, p_preco_cents integer, p_inclui text, p_materiais text,
  p_materiais_incluidos boolean, p_prazo text, p_duracao_min integer) → {id}
- casa_retirar_orcamento(p_orcamento_id uuid) → {ok}
- casa_meus_trabalhos() → [pedido] (atribuídos a mim: ativos primeiro, depois histórico)
- casa_avancar(p_pedido_id uuid, p_para text) → pedido (a_caminho | chegou | em_curso | concluido;
  concluir exige pelo menos 1 foto 'depois')
- casa_pedir_extra(p_pedido_id uuid, p_valor_cents integer, p_motivo text) → {id}
- casa_avaliar_cliente(p_pedido_id uuid, p_nota integer) → {ok}
- casa_desistir(p_pedido_id uuid, p_motivo text) → {ok} (devolve à rotação)
- casa_meus_ganhos() → {semana{inicio,fim,trabalhos,bruto_cents,comissao_cents,ganho_cents,
  recebido_em_mao_cents,a_receber_cents}, acertos[{id,week_start_at,week_end_at,total_jobs,net_payout_cents,
  direction,status,paid_at}], trabalhos[{id,servico_nome,confirmed_at,total_cents,comissao_cents,ganho_cents,payment_method}]}

### Admin (is_admin; ecrãs em PT-BR)
- admin_casa_resumo() → {enabled, valores_autorizados{autorizado,em,texto}, profissionais_pendentes,
  oficios_pendentes, documentos_pendentes, pedidos_ativos, pedidos_procura, orcamentos_abertos, disputas,
  reembolsos_pendentes}
- admin_casa_profissionais(p_estado text default null) → [{id,user_id,name,phone,email,photo_url,
  approval_status,created_at,rating_avg,ratings_count,jobs_done,is_active,sem_comissao_ate,
  oficios[{codigo,estado,ligado}],docs_pendentes}]
- admin_casa_profissional(p_id uuid) → {perfil{todas as colunas}, oficios[], documentos[{...,storage_path}],
  disponibilidade[], pedidos[pedido], atividade_status, conformidade_em_falta[]}
- admin_casa_decidir_profissional(p_id uuid, p_acao text, p_motivo text) → {ok}  aprovar|recusar|suspender|banir|reativar
- admin_casa_decidir_oficio(p_profissional_id uuid, p_oficio text, p_acao text, p_motivo text) → {ok}  aprovar|recusar|suspender
- admin_casa_decidir_documento(p_documento_id uuid, p_acao text, p_motivo text, p_validade date) → {ok}  aprovar|recusar
- admin_casa_editar_profissional(p_id uuid, p_dados jsonb) → {ok}
  chaves: service_radius_km, has_van, has_tools, bio, base_address, base_lat, base_lng
- admin_casa_pedidos(p_estado text default null, p_limite integer default 200) → [pedido + cliente_nome + profissional_nome]
- admin_casa_pedido(p_id uuid) → pedido + eventos[{estado_de,estado_para,por_papel,detalhe,created_at}] +
  ofertas[{profissional_nome,tipo,enviada_em,expira_em,tinha_aparelho,resposta,respondida_em,ronda}] +
  mensagens[] + cliente{nome,email,phone}
- admin_casa_reatribuir(p_pedido_id uuid, p_profissional_id uuid) · admin_casa_cancelar(p_pedido_id uuid, p_motivo text)
- admin_casa_marcar_teste(p_pedido_id uuid, p_is_test boolean) · admin_casa_forcar_conclusao(p_pedido_id uuid, p_motivo text)
- admin_casa_resolver_disputa(p_pedido_id uuid, p_resolucao text ('refeito'|'sem_razao'|'reembolso_pendente'), p_nota text)
- admin_casa_orcamentos(p_estado text default null) → [{id,pedido_id,servico_nome,profissional_nome,preco_cents,
  estado,expira_em,created_at,tempo_resposta_min,ganhou}]
- admin_casa_catalogo() → {oficios[todas as colunas], servicos[todas as colunas], valores_autorizados{}}
- admin_casa_guardar_servico(p_id uuid, p_dados jsonb) → {id} (p_id null = novo; mudar preço volta a pôr valores por autorizar)
- admin_casa_guardar_oficio(p_codigo text, p_ativo boolean) → {ok}
- admin_casa_definicoes() → [{key,value,description}] · admin_casa_guardar_definicao(p_key text, p_value jsonb) → {ok}
  (mudar casa_bora_pct/casa_promo_* volta a pôr valores por autorizar; casa_enabled só pelo interruptor)
- admin_casa_autorizar_valores(p_texto text) → {ok} (o texto tem de conter "autorizo"; regista data e quem)
- admin_casa_interruptor(p_ligado boolean) → {ok}
- admin_casa_ofertas(p_pedido_id uuid default null) → [registo de ofertas]
- admin_casa_acertos(p_week_start date default null) → [acerto + profissional_nome]
- admin_casa_calcular_acertos(p_week_start date) → {criados}
- admin_casa_acerto_marcar(p_id uuid, p_status text, p_payment_method text, p_reference text) → {ok}
- admin_casa_exportar(p_tipo text ('pedidos'|'ganhos'|'profissionais'), p_de date, p_ate date) → [linhas planas]

### Nomes Flutter fixos (para as ligações entre agentes)
- lib/models/casa_models.dart: CasaOficio, CasaServico, CasaPergunta, CasaConfig, CasaPedido, CasaFoto,
  CasaExtra, CasaOrcamento, CasaPessoaResumo, CasaOferta, CasaPerfil (fromJson de cada uma), + `casaEstadoTexto(String)`.
- Cliente: lib/stores/casa_store.dart `CasaStore` (ChangeNotifier: `bool get enabled` (= visivel),
  `Future<void> refreshSettings()`, `Future<void> refreshTracked()`); entrada `CasaCategoriaScreen`
  em lib/screens/client/casa/casa_categoria_screen.dart; lista `CasaMeusPedidosScreen`.
- Profissional: lib/stores/handyman_store.dart `HandymanStore` (espelha a API pública que o WasherStore dá a
  main.dart e a trabalho_oferta_overlay_host.dart); `HandymanHomeScreen({bool comoEntrada = false})` em
  lib/screens/handyman/handyman_home_screen.dart; `HandymanApplyScreen` (mesmo construtor que o CleanerApplyScreen)
  em lib/screens/handyman/handyman_apply_screen.dart.
- Admin: lib/screens/admin/admin_casa_screen.dart `AdminCasaScreen` (hub com separadores).

## 31/10 — retoma (missão retoma-geral-2026-10-31, bloco 1)

A sessão original parou às 07:01 presa numa janela de confirmação do apply_migration da parte 4 e foi
fechada às ~10:05. Esta retoma fechou o trabalho no mesmo ramo, sem aplicar nada em produção.

### O que está NO AR (produção ojykpzwqrtusfeakzrna)
- Aplicadas pela sessão antiga entre 06:05 e 06:52, ao contrário do plano "só ficheiros":
  20261031060526 casa_01_papel_e_tabelas, 20261031062027 casa_01b_definicoes,
  20261031064129 casa_02a_definicoes_leitura, 20261031064504 casa_02b_funcoes_base,
  20261031065206 casa_03_cliente. Verificado a 31/10: md5(array_to_string(statements, E'\n')) de
  schema_migrations = md5 dos 5 ficheiros de supabase/migrations/ (byte a byte).
- `casa_enabled` = false no ar. Nenhuma função da parte 4 nem admin_casa_* no ar; nenhum cron casa.

### O que está PENDENTE (vai para o passo PUBLICAR, por esta ordem)
1. `supabase/migrations_pendentes/casa_04_profissional_e_tarefas.sql` — 22 funções do profissional,
   crons `casa_tick` (cada minuto) e `casa_acertos_semanais` (segunda 04:20 UTC), acerto semanal.
   Revisão de 31/10 acrescentou: `meu_orcamento_id` em `casa_minhas_ofertas` (a HandymanStore lê-o para
   retirar o orçamento), recusa de aceitar oferta com o profissional suspenso, acerto e ganhos sem os
   pedidos com `reembolso_pendente`, 'casa' na lista fechada de `ofertas_prestador_log` (o
   `registar_oferta('casa', …)` da parte 2b falhava calado), e os baldes privados `handyman-documents` e
   `casa-fotos` com as regras de storage (não existiam no ar; a app já os usa) + `_casa_foto_visivel`.
2. `supabase/migrations_pendentes/casa_05_admin.sql` — as funções do painel (lista abaixo).
3. Edge Function nova `supabase/functions/notify-handyman/index.ts` (molde notify-washer v2, DATA-ONLY).
   O `_casa_notificar` (no ar) já a chama; até ser publicada, os push da Casa não saem (fica o aviso
   dentro da app).
Na aplicação, a versão da migração nasce nesse momento e o ficheiro passa para supabase/migrations/.

### Funções admin (casa_05_admin.sql) — decisões de 31/10
- Todas: `is_admin()` senão `sem_permissao` (42501); auditoria por `log_admin_action(text,text,text,jsonb)`;
  SECURITY DEFINER com search_path public; REVOKE de PUBLIC e anon, GRANT a authenticated.
- 27 funções: as 26 que os ecrãs chamam + `admin_casa_ofertas`. Ajudantes internos: `_casa_exigir_admin`,
  `_casa_motivo` (≥ 3 letras senão `motivo_obrigatorio`), `_casa_reabrir_valores`, `_casa_nome_cliente`,
  `_casa_euro`.
- Códigos novos (o painel tem o texto PT-BR em kCasaErrosPtBr): `tem_trabalhos_ativos`,
  `profissional_ocupado`, `profissional_sem_oficio`, `validade_passada`, `usar_interruptor`,
  `chave_invalida`, `valor_invalido`, `acao_invalida`, `texto_sem_autorizo`, `documento_em_falta`;
  e dos gatilhos já no ar: `atividade_por_aprovar`, `conformidade_incompleta`.
- decidir_profissional: aprovar não aprova ofícios; suspender/banir recusa com trabalho em curso e
  passa as ofertas em aberto ao seguinte; reativar volta a 'approved' se já foi aprovado, senão
  'pending'. Promoção dos primeiros: na PRIMEIRA aprovação, se houver menos de
  `casa_promo_primeiros_n` profissionais reais já aprovados, `sem_comissao_ate` = hoje + `casa_promo_meses`
  (POR CONFIRMAR pelo Danilo se conta da aprovação; inerte até ao "autorizo", porque o acerto não corre antes).
- decidir_oficio: ofício com título (fase 2) só com o documento exigido aprovado e válido.
- reatribuir: só procura/aceite/a_caminho/chegou; recusa sobreposição com outro trabalho do mesmo
  profissional (a janela semanal não trava: o Danilo pode ter combinado por telefone).
- cancelar (admin): só marca `reembolso_pendente` quando havia pagamento retido. resolver_disputa:
  refeito | sem_razao | reembolso_pendente — o pedido volta a confirmado (ou passa por `_casa_confirmar`
  se ainda não tinha sido confirmado); com reembolso pendente fica FORA do acerto até o Danilo decidir.
- guardar_servico / guardar_definicao: mudar preço, modo, `casa_bora_pct`, `casa_promo_*` ou chave com
  "comissao" volta a pôr `casa_valores_autorizados.autorizado=false` (guarda o anterior). casa_enabled só
  pelo interruptor; casa_valores_autorizados só pelo autorizo.
- autorizar_valores: o texto tem de conter "autorizo"; grava texto, data, quem e uma fotografia dos
  valores (percentagem, promoção, preços do catálogo). Ninguém o chama agora: é o Danilo pelo painel.
- acertos: só calcular (recusa `valores_por_autorizar` sem o autorizo) e marcar estado
  (pending/paid/received/disputed + método transferencia/mbway/dinheiro + referência). Não move dinheiro.
- exportar: pedidos (criados entre as datas, Lisboa), ganhos (confirmados entre as datas), profissionais
  (todos). Sem IBAN e sem referências de pagamento.
- O texto do ficheiro não tem `fee_`/`token_`/`stripe_`/`commission_`/`pricing_` (a tranca recusa
  UPDATE em platform_settings com isso) nem as palavras de dinheiro da regra das migrações.

### Provas de 31/10
- PGlite local: as 5 partes no ar + 04 + 05 carregam; cenário completo com 78 verificações verde
  (`pglite/provar_casa.mjs`, saída em `pglite/provar_casa.saida.txt`).
- flutter analyze: 0 erros; flutter test dos 12 ficheiros da Casa e dos papéis verde depois de corrigir
  o `setState(() => _future = …)` dos separadores admin; `test/l10n_cobertura_test.dart` verde depois de
  acrescentar à mão 433 traduções da Casa a `lib/l10n/strings_en.dart`.

### Ainda por fazer (fora deste bloco)
- Funções já no ar que ainda não conhecem o papel `handyman` (o Dart está tolerante e esconde a Casa
  quando o servidor não manda): `admin_papeis_listar` (estado_handyman), `admin_candidaturas_listar`,
  `_provider_atividade_papeis`, `admin_acerto_unificado`, `admin_conformidade_legal`, `admin_ofertas_log`.
- Cartão e MB Way na Casa: só proposta (docs/propostas), `pagamento_cartao` = false.
- Provas no emulador e na web com contas demo: não feitas (PC sem RAM para emulador).
