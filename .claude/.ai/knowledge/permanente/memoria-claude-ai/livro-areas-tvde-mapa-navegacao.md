---
id: memoria-claude-ai-livro-areas-tvde-mapa-navegacao
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Mapa/navegação do motorista e o que o CLIENTE vê durante a corrida (carro, ETA, avaliação) — causas achadas e estado; complemento de [[tvde-vertical]]

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-tvde-mapa-navegacao`, origem `claude-ai`, atualizada em 2026-10-23T05:35:02.538387+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas tvde mapa navegacao · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/tvde-mapa-navegacao.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: tvde-mapa-navegacao
description: Mapa/navegação do motorista e o que o CLIENTE vê durante a corrida (carro, ETA, avaliação) — causas achadas e estado; complemento de [[tvde-vertical]]
sources: [chat]
aliases: [mapa do motorista, mapa trava, ETA do cliente, cliente não vê o carro, avaliação travada, navegação TVDE]
---

⛔ O CLIENTE NÃO VIA NADA DO MOTORISTA (05/09) — outra vez RLS, como em 02/08
- A policy de SELECT de `public.drivers` só tem `is_admin()` e `user_id = auth.uid()`. Não existe policy nenhuma para o CLIENTE. `tvde_ride_tracking_screen.dart:528` faz `.from('drivers').select(...)` e vem SEMPRE vazio, com o erro morto num `catch (_) {}` mudo
- Um problema, sete sintomas: sem carro no mapa, sem nome, sem matrícula, sem foto, sem estrelas, sem telefone — e sem posição do motorista também não há ETA nenhum
- Os dados estavam TODOS certos na base (Hyundai Ioniq 5, Azul, CH-90-PX, foto, 5,00 com 7 avaliações). Nunca foi falta de dados
- NÃO se pode abrir a RLS de `drivers` ao cliente: essa tabela tem IBAN, NIF, número e foto do documento, morada e conta Stripe
- ✅ FEITO por MCP (migration tvde_ride_driver_card_cliente_ve_o_carro_2026_09_05): `tvde_ride_driver_card(p_ride_id)` SECURITY DEFINER, espelho do `tvde_ride_passenger_card` que já existia do lado do motorista. Devolve só o público — name, photo_url, phone, avg_rating, ratings_count, vehicle_make_model, vehicle_color, license_plate, lat, lng, heading, speed_kmh, location_updated_at. Posição por join tolerante `driver_id IN (d.user_id, d.id)` em driver_locations, fallback drivers.lat/lng. Só o cliente daquela corrida ou o admin; estranho apanha `not_ride_client`. PROVADO com JWT dos dois lados
- Falta só o Flutter chamar a RPC em vez do `.from('drivers')` — vai no prompt

🐞 A AVALIAÇÃO PRENDIA O CLIENTE (05/09)
- `tvde_rate_screen.dart` usa `BoraPrimaryButton(loading: store.busy)` e `bora_primary_button.dart:33` faz `onPressed: loading ? null : onPressed`. O `store.busy` é um flag GLOBAL único do TvdeStore — qualquer outra operação do store a correr mata o botão de enviar
- O "Agora não" é um TextButton sem essa dependência: foi por isso que funcionou e o outro não, exactamente como o cliente descreveu
- REGRA a fixar no PADRAO_BORA.md: um botão nunca depende de um estado global de ocupado, depende do seu próprio pedido; e nenhum ecrã de fim de fluxo existe sem saída sempre viva

[stated] REGRA DO DANILO — ETA mostrado ao CLIENTE (05/09)
- Ele quer mostrar MENOS tempo que o real: 20% a menos; exemplo dele, 10 minutos passam a mostrar 8
- Chaves criadas por MCP (categoria eta): tvde_eta_client_discount_pct=20, tvde_eta_client_discount_max_min=2, tvde_eta_client_floor_min=1, tvde_eta_arriving_push_min=2; e tvde_driver_card_poll_seconds=4 (categoria tvde)
- O tecto de 2 minutos no corte foi DECISÃO MINHA: a regra dele é ambígua em viagens longas ("menos 20% e até menos 2 minutos" dá 8 nos dois sentidos aos 10 min). Fica em setting, ele corrige numa palavra
- AVISO honesto que lhe dei: o mercado faz o CONTRÁRIO — as apps de entrega põem folga PARA MAIS de propósito, e nas análises de avaliações negativas de Uber/Bolt/Lyft/Grab de 2026 a queixa nº1 sobre chegada é precisamente esta (preferem ver 15 min e o carro chegar, do que ver 3 e esperar 10). O Uber deixa cancelar sem multa 5 min depois do ETA prometido
- Alternativa honesta que resolve o objectivo real dele (cliente já à porta) e vai no mesmo prompt: push "o motorista está quase a chegar" a 2 minutos de distância, com carro e matrícula

Marcador do carro no mapa do cliente
- Hoje é `BitmapDescriptor.defaultMarkerWithHue(hueOrange)`, um pino de alfinete. Não há asset de carro no projecto
- Danilo quer um carrinho AZUL. Desenhar em código como já se faz a seta verde do motorista (`_createArrowIcon()`), rodado pelo `heading` que a RPC nova devolve

PROMPT entregue (OPUS, PROMPT_tvde_cliente_ve_carro_eta_avaliacao_mapa_2026-09-05.md) — ✅ CORREU E FECHOU a 05/09
- Commit 80cc1e2, os três trabalhos do CI verdes (golden, web, Android), web no ar. VERIFIQUEI eu por MCP e no repo em vez de aceitar a palavra do executor: o `.from('drivers')` desapareceu, a RPC nova é chamada, o GPS do ecrã passou a `bestForNavigation` + filtro 3 m, geolocator em 14.0.2, 11 chaves editáveis no painel
- A causa A SÉRIO do mapa a travar não era a câmara nem estava no meu diagnóstico: o ecrã só recebia posição a cada 50 m (`LocationAccuracy.medium` + `distanceFilter: 50`). Achou-a o Claude Code
- ⚠️ LIÇÃO MINHA: chamei os pacotes de "velhos" lendo `^2.6.0` no pubspec, mas o `^` quer dizer "no mínimo" e o `pubspec.lock` está no .gitignore — o instalado já era o 2.18.0. Nunca concluir versão real a partir do pubspec do repo
- ⚠️ ARMADILHA a não "arrumar": geolocator ficou fixo em `14.0.2` SEM o `^` de propósito — o lock não viaja, o CI resolve do zero, e com `^` apanha a 14.0.3, que dá conflito com o flutter_secure_storage e parte o build
- SUBSTITUI e apaga o PROMPT_mapa_navegacao_motorista_2026-09-05.md (esse já não existe)
- Blocos: cliente vê o carro (RPC nova + carrinho azul + cartão com matrícula em destaque); ETA vivo + regra dos 20% + push de chegada; avaliação sem busy global + varredura de TODOS os botões presos a busy global; mapa do motorista (recalcular só por desvio, rota que se apaga atrás do carro, câmara contínua, tirar as ~12 notificações/s deste ecrã, ler as chaves + whitelist no painel admin, subir pacotes); e o estudo do Nav SDK sem migrar nada
- 🔑 COMO PROVAR SEM ELE CONDUZIR (ele perguntou se dava para testar já no PC): navegador com `flutter run -d chrome` prova cartão do motorista, ETA e avaliação (pagamento em teste sempre em dinheiro); e o EMULADOR Android reproduz um ficheiro GPX/KML e "conduz" o telemóvel — duas rotas na Guarda, uma certa e outra com desvio de propósito, provam a câmara a seguir e o recálculo. Telemóvel por USB só para capturas finais, confirmar com `adb devices`

💰 DEFEITO ABERTO E COM DINHEIRO PELO MEIO — as paragens não entram na rota (verificado por mim, 05/09)
- `tvde_stop_fee_cents`=200 ao cliente, `tvde_stop_driver_cents`=100 ao motorista, `tvde_max_stops`=2. O `DirectionsService.fetchRoute` já aceita `waypoints`, mas em todo o `lib/` só `driver_map_screen.dart:1024` (mapa das ENTREGAS) os passa. O ecrã de corrida do TVDE carrega `_stops` e nunca os usa
- Ou seja: cobra-se 2€ por uma paragem que o mapa ignora, e o motorista tem de se lembrar sozinho onde é
- Outros abertos que confirmei no repo: duas streams de GPS abertas ao mesmo tempo na corrida (`tvde_ride_active_screen.dart:256` e `tvde_driver_home_screen.dart:496`); o manifest pede `FOREGROUND_SERVICE_LOCATION` mas o serviço declarado só tem `dataSync|remoteMessaging`, logo o Android pode estrangular o GPS se ele minimizar a app; o cliente interpola o carro em LINHA RECTA (corta esquinas) e `heading`/`speed_kmh`/`location_updated_at` da RPC nova não são usados para nada; e o botão preso ao `busy` global ainda em 21 ecrãs

PROMPT SEGUINTE (OPUS, PROMPT_tvde_paragens_carro_suave_botoes_2026-09-05.md) — ✅ CORREU E FECHOU a 05/09
- Paragens na rota nos dois mapas com o tempo parado a contar (18 testes), sinal velho em função pura testada (15 testes), stream de GPS duplicada morta, teste-guarda dos botões de 16 infractores a ZERO no lib/ inteiro. 450 testes verdes, três trabalhos do CI passaram, pacote publicado verificado por dentro
- O executor recusou DUAS coisas da minha ordem, e bem: acrescentar `location` ao serviço em primeiro plano teria feito a app do PARCEIRO rebentar (o serviço é partilhado com a loja e o plugin arranca todos os tipos de uma vez); e dos 21 ecrãs que contei só 10 tinham mesmo o defeito — os 9 do admin já usavam estado local. Em troca achou 5 no ecrã da limpeza, incluindo o "Recusar" de uma oferta que expira
- Achado grave: "Pagar agora" da limpeza e o botão do pacote estavam SEM trava nenhuma contra duplo toque (os métodos de pagamento nunca ligavam o busy global). No MB Way eram dois pedidos no banco. Já têm guarda própria
- ✅ OS 3 "BURACOS DE IDEMPOTÊNCIA" QUE ELE DEIXOU EM ABERTO JÁ ESTÃO FECHADOS NO AR (verifiquei eu por MCP a 05/09): tvde-plan-payment v9 leva chave de idempotência no pacote (cartão e MB Way) E no plano (mesmo buraco, pior no MB Way porque nasce com confirm:true); cleaning-checkout v6 tem duas travas no `reverse` (pergunta à Stripe se já há estorno + chave fixa por reserva); e `create_cleaning_booking` nunca esteve desprotegida — tem chave, advisory lock, janela de 15 min e apanha unique_violation
- ❌ ERRO MEU corrigido: disse-lhe "49 chaves sem categoria, 13 de dinheiro". FALSO — só havia UMA em 248, e nem estava invisível (o painel agrupa as sem categoria em "other" e mostra-as). Arrumada por MCP (migration platform_settings_categoria_partner_auto_dispatch_2026_09_05): `partner_auto_dispatch_after_minutes` → categoria dispatch + descrição; continua READ-ONLY porque o `_isEditable` do painel filtra por NOME de chave, não por categoria. Zero sem categoria agora
- ⚠️ LIÇÃO QUE JÁ SE REPETIU 3x: o repositório está atrás do que corre em produção. Os três alarmes de dinheiro vieram de ler o repo; o ar mostrava zero. Ler SEMPRE o que está no ar antes de reportar ou mandar corrigir
- Fica em dívida: a corrida ponta a ponta (provei por comando que não há telemóvel por USB nem emulador instalado) e o Android 15, que mata o serviço em primeiro plano ao fim de 6 h/dia — um turno de 8 h bate nisso
- Fecha tudo o acima + a dívida de prova (corrida ponta a ponta no navegador com duas contas, pagamento sempre em dinheiro porque o Stripe é real)
- 🔒 TRAVA que pus nos ecrãs de dinheiro: antes de tirar o `busy` global de um botão que paga/estorna/adere, tem de provar que a chamada é idempotente — esse travão pode ser, sem querer, a única coisa a impedir cobrança a dobrar. Se não conseguir provar, não toca e explica
[stated] REGRA DO DANILO — RASTREIO EM TEMPO REAL IGUAL À UBER (07/10)
- Cliente toca no motorista/estafeta → vê a localização EXATA dele em tempo real, a mover-se suave como na Uber — em TODAS as categorias (TVDE principalmente, entregas, favores), não só no TVDE
- E no sentido contrário: quando o condutor está a chegar, vê o pontinho do cliente em tempo real, igual à Uber
- Método que ele mandou: "vai a fundo, vê como a Uber faz, copia e cola"
- Na frente do mapa/rastreio, erro achado pelo caminho é para CONSERTAR já, tudo ao padrão dos concorrentes (exceção à regra geral de só reportar; mexer em valores de dinheiro continua proibido)
- Adendo enviado como Bloco E da missão da noite de 07/10
[stated] REGRA DO DANILO — CARTÃO DA CORRIDA DO MOTORISTA POR FASES (11/10): o painel de baixo do ecrã da corrida tem de subir com facilidade para ver toda a informação (hoje fica minimizado, custa a subir e fica fininho) e a informação não pode vir toda junta — indo buscar o passageiro mostra só a morada da recolha ("indo buscar em…"); depois de iniciar, frase clara de que vai levar ao destino e só a morada do destino. Copiar como os grandes fazem (Uber/Bolt)

