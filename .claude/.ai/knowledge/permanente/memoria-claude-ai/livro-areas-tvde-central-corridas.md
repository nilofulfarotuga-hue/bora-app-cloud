---
id: memoria-claude-ai-livro-areas-tvde-central-corridas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Central de corridas do Danilo para clientes que ligam por telefone (sem app) — regra de ficar no core do Bora, fila entre os colegas da Guarda e divisão 4/1

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-tvde-central-corridas`, origem `claude-ai`, atualizada em 2026-10-23T05:36:14.453524+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas tvde central corridas · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/tvde-central-corridas.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: tvde-central-corridas
description: Central de corridas do Danilo para clientes que ligam por telefone (sem app) — regra de ficar no core do Bora, fila entre os colegas da Guarda e divisão 4/1
sources: [chat]
aliases: [corrida de balcão, central de corridas, chamar motorista por mim, cliente sem app, corrida por telefone]
---

- [stated] Tem 3 a 4 colegas motoristas na Guarda que trabalham com ele e apanham as corridas que ele não consegue fazer (está com outro cliente no carro)
- [stated] Muitos clientes dele ligam por telefone e NÃO querem instalar a aplicação — é ele que chama a corrida por eles
- [stated] DECISÃO (18/09): isto tem de nascer DENTRO do [[bora-app]] ("no core"), como corrida normal — o motorista recebe no app onde já fica online e o ganho soma tudo junto com o que vem da aplicação. Recusou a minha proposta de fazer à parte num bot de Telegram: "o povo aqui não é acostumado com o Telegram"
- [stated] Divisão combinada com os colegas: corrida de 5 € → 4 € para o motorista, 1 € para ele
- [stated] Fila: chamar um de cada vez, ~20 segundos para aceitar; se não aceitar passa ao seguinte e diz quem era da vez; quem faz a corrida volta para o fim da fila
- [stated] Só depois de alguém aceitar é que ele passa morada e dados do cliente, direto ao motorista por WhatsApp ou chamada
- [stated] COMO ELE QUER USAR: falar o mínimo possível, muitas vezes com passageiro no carro e por mensagem de voz; o sistema grava nome, telefone e morada do cliente na primeira vez e depois reconhece só por "é para tal pessoa" ou "tal endereço" (aceita print do contacto). Resposta final curta: "chamei tal pessoa, aceitou"
- [stated] EXIGÊNCIA DE VELOCIDADE (18/09, queixou-se): neste caso não pode haver demora a pensar — o cliente está à espera ao telefone; chamar o motorista depressa e responder curto
- [stated] CORRECÇÃO 18/09: fica nos **40 segundos** de oferta que já existem, não nos 20 que tinha dito ("continua com os 40 segundos")
- [stated] MOTOR ESCOLHIDO POR ELE 18/09: nada de Fable nesta missão — o trabalho de ecrãs vai para o **glm-5.2 (plano Go, porta OpenCode)**, porque está com pouco limite de Claude
- PROMPT ENTREGUE 18/09 (histórico de prompts): `PROMPT_central_corridas_balcao_GLM_2026-09-18.md` — motor glm-5.2, sessão NOVA no OpenCode na pasta bora-app-cloud; scope SÓ Flutter/painel (ecrãs do motorista com o ganho em grande e selo "cliente sem aplicação", ecrã admin de corridas de balcão, agenda de clientes com importar por print). A versão anterior para Fable/Claude Code (`PROMPT_tvde_central_corridas_balcao_2026-09-18.md`) foi substituída. Estado: entregue, ele pode colar
- ✅ FEITO POR MIM VIA MCP 18/09 (a parte de base de dados, tirada do prompt do GLM de propósito): (1) `tvde_rides.source` ('app'|'balcao'), `agreed_fare_cents`, `agreed_driver_earn_cents`; `users.is_counter_client` + `created_by_admin`; tabela `tvde_client_places` (moradas com apelido, RLS só admin); settings `tvde_balcao_default_fare_cents=500`, `tvde_balcao_default_driver_cents=400`, `tvde_fila_justa_balcao_enabled=true`. (2) RPC `admin_tvde_create_counter_ride` (SECURITY DEFINER + is_admin) — acha/cria o cliente por telefone normalizado sem duplicar, resolve apelidos de morada, e cria corrida NORMAL em dinheiro em `solicitada`, deixando o trigger `fn_tvde_dispatch_on_request` despachar como sempre. (3) `tvde_finish_ride` passa a RESPEITAR os `agreed_*` (só no ramo normal; a NULL fica byte-a-byte como antes) — era isto que apagava o preço combinado ao recalcular por km. (4) `tvde_offer_to_next` ganhou fila justa **só** em corridas de balcão (ordena por quem está há mais tempo sem corrida); corridas da app continuam pelo mais perto. (5) trigger `trg_balcao_sem_cancel_fee` isenta o cliente de balcão da taxa de cancelamento, mantendo a compensação de no-show ao motorista
- PROVA (transacção revertida, 18/09): corrida normal de 6 km = cliente 500 / motorista 400 / Bora 100, igual ao anterior; corrida de balcão combinada a 500 que andou 18 km = 500/400/100 em vez dos 1800 da tabela
- ⚠️ CORRECÇÃO 18/09 de uma nota minha VELHA: o push ao motorista quando a corrida é cancelada **já existe desde 21/08** — trigger `tr_tvde_notify_driver_on_cancel` + kind `ride_cancelled` na Edge `notify-tvde-driver` (v16), e ainda tem o cuidado de não avisar o motorista quando foi ele próprio a cancelar. A "lacuna de 21/08" está fechada; não voltar a dizer que falta
- ✅ FEITO POR MIM VIA MCP 18/09 (2.ª ronda, depois do GLM entregar): `admin_tvde_rides_list` passa a devolver `source`/`agreed_*` e a ler nome+telefone de `public.users` (o cliente de balcão não tem linha em auth.users, por isso vinha vazio), com scopes `balcao` e `balcao_live`; RPCs novas da agenda — `admin_tvde_counter_clients_list`, `admin_tvde_counter_client_save` (bloqueia telefone repetido), `admin_tvde_client_place_save`, `admin_tvde_client_place_delete`; trigger `trg_balcao_sem_pergunta_ao_cliente` mata a pergunta automática das 2h antes em reserva de cliente de balcão
- ✅ LADO FLUTTER FEITO PELO GLM 18/09: ganho em grande em 6 ecrãs do motorista + selo "Cliente sem aplicação — liga-lhe", e no painel admin os ecrãs "Corridas de Balcão" e "Agenda de Clientes de Balcão". Commit `91eb1534`, push confirmado; 165/165 testes TVDE. Sem prova visual em emulador (PC de 4 GB)
- POR FAZER: só o "importar contacto por print" (OCR do nome+telefone) — falta a Edge própria; há a `ocr-receipt` (Gemini, dos Favores) para servir de molde

