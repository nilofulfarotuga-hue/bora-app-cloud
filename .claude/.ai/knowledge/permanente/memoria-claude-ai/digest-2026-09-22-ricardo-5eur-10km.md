---
id: memoria-claude-ai-digest-2026-09-22-ricardo-5eur-10km
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-22
zona: verde
confianca: alta
estado: atual
---

# Preco a medida do Ricardo: 5 EUR ate 10 km, motorista 4 EUR (22/09/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-22-ricardo-5eur-10km`, origem `claude-ai`, atualizada em 2026-09-22T10:27:03.120384+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 22 ricardo 5eur 10km · memoria claude.ai · claude_ai_memoria

ORDEM do Danilo 22/09 (depois da 1a corrida do Ricardo pela app, que saiu a 7,00 EUR): na conta do Ricardo, corrida ate 10 km = 5,00 EUR ao cliente E 4,00 EUR ao motorista. Acima de 10 km, preco normal por km dos dois lados. Pediu expressamente para "fazer direito", porque a regra equivalente da Vina Ca nunca chegou a funcionar.

QUEM E': Ricardo Santos Rosa, 931787345, ricardosantosrosa96@gmail.com, user 80dcd4f2-d5ba-4042-88f8-198c4a109913 (conta da app criada 22/09 09:32). E' o MESMO telefone do "Ricardo" de balcao 8b497fe7 da corrida de 21/09 20:25 (Decathlon -> After), que o Danilo combinou a mao a 5/4/1 — bate certo com a regra que pediu agora. Ha outros 2 Ricardos no banco (113c059b / 960386302 e 090f2644 / 963570087) que NAO foram tocados.

A CORRIDA QUE DEU ORIGEM: eb814e4c-3f66-4521-959c-e6600522b893, 22/09 10:32, MB Way, R. Dr. Alvaro Cunhal 13 -> Decathlon Guarda. A rota do Google deu 7,50 km (linha recta 3,12 km) => 5,00 base + 2 km extra = 7,00 ao cliente e 5,60 ao motorista. NAO foi reembolsada (o Danilo disse "para a proxima vez"). O codigo NAO escolhe caminho longo: directions_service_io.dart pede ao Google sem alternatives e usa routes.first; as coordenadas da origem batem com as da corrida do dia anterior da mesma rua, logo nao e' geocodificacao trocada.

PORQUE E' QUE O DA VINA "NAO DEU CERTO": o mecanismo tvde_client_fare_overrides (13/09) so' fixava o preco do CLIENTE — o motorista continuava a ganhar pela formula da distancia. Faltava metade do que o Danilo queria. A Vina nunca fez nenhuma corrida na app depois disso (0 registos), portanto a parte do preco nunca chegou a ser testada em corrida real.

FEITO POR MCP (Claude.ai, 22/09) — 5 migrations:
1. tvde_override_ganho_motorista_2026_09_22 — coluna tvde_client_fare_overrides.driver_earn_cents (NULA por defeito) + funcao tvde_client_fixed_driver_earn_cents(client,km), irma da tvde_client_fixed_fare_cents. Backup das 2 funcoes em bkp_fn_tvde_override_20260922 (com RLS ligado a' partida, para nao repetir os alertas de backups expostos).
2. tvde_request_ride_override_ganho_motorista_2026_09_22 e 3. tvde_finish_ride_override_ganho_motorista_2026_09_22 — as duas funcoes passam a ler tambem o ganho fixo. DIFF CONFERIDO linha a linha contra o backup: 0 linhas removidas, so' as 8+9 linhas novas. A ordem no finish mantem-se: override fixo primeiro, agreed_fare/agreed_driver_earn (balcao) continuam a mandar por cima.
4. override_ricardo_10km_5eur_2026_09_22 — a linha do Ricardo (500 / 10 km / 400).
5. admin_rpc_planos_a_medida_por_cliente_2026_09_22 — RPCs admin_tvde_fare_override_list / _save / _delete, com guarda is_admin(). PAINEL ADMIN: o servidor ja aceita, FALTA O ECRA em Flutter (continua a ser SQL/MCP para criar um preco destes).

PROVADO em transaccao revertida (nada gravado):
- ecra do cliente (tvde_calculate_fare com a sessao dele): 3/7,5/10 km -> 5,00 EUR; 12 km -> 11,00 EUR.
- corrida completa 7,5 km em dinheiro: oferta ao motorista 4,00, fim 5,00 / 4,00 / Bora 1,00; saldo do motorista +1,00 (recolhe 5 em mao, deve 1 a' Bora).
- a mesma em MB Way: 5,00 / 4,00 / Bora 1,00, settle -4,00 (Bora deve 4 ao motorista, porque o cliente pagou online).
- 12 km: 11,00 / 8,80 — volta ao normal dos dois lados.
- cliente normal (Martim Cruz) 7,5 km: 7,00 / 5,60 — intacto.
- Vina Ca 7,5 km: 5,00 ao cliente e 5,60 ao motorista — a regra dela ficou exactamente como estava (coluna nova a NULL).

PONTA SOLTA avisada ao Danilo: em corrida paga por cartao/MB Way cobra-se o est_fare no inicio (5,00) e o valor final e' recalculado pela distancia REAL no fim. Se a rota passar dos 10 km, o fim fecha ao preco normal e fica uma diferenca que ninguem cobra. Nao e' novo nem e' so' do Ricardo, mas com preco fixo ficou mais visivel.

ADENDO 22/09 (ordem seguinte do Danilo, "faz o mesmo para a Vivi"): a Vina Ca passou a ter a MESMA regra do Ricardo, so' que ate 15 km — 5,00 EUR ao cliente e 4,00 EUR ao motorista, acima de 15 km preco normal dos dois lados. O tecto ja' era 15 km desde 13/09; o que faltava mesmo era o ganho do motorista. Gravado pela RPC nova admin_tvde_fare_override_save (primeira utilizacao real, serviu de prova de que a RPC do painel funciona).
CONFIRMADO pelo Danilo as 11:26 de 22/09 ("a Vina nao esta com plano nenhum, vai ficar desse jeito ai"): motorista a 4,00 EUR fica, e ela NAO tem nem volta a ter plano de corridas — so' o preco fixo por corrida. Os 4,50 do plano pre-pago antigo ficam so' como historico.
VERIFICADO: a subscricao 'especial' dela (a20782f7, 8 corridas, 04/09 a 13/09) esta' active=false e tvde_preview_coverage devolve no_subscription — logo o ramo do override corre mesmo. Se tivesse ficado um plano activo, o override era SALTADO (o codigo so' o aplica com NOT v_covered) e voltava o erro dos "2 euros a mais".
PROVA (transaccao revertida): ecra dela 9 e 15 km -> 5,00; 16 km -> 15,00. Corrida casa (Av. Cidade de Safed 14) -> Vale de Estrela a 9 km em dinheiro: 5,00 / 4,00 / Bora 1,00, saldo do motorista +1,00.
DISTANCIA: Guarda -> Vale de Estrela sao ~7 km de estrada (linha recta da casa dela ~5,6 km), portanto a viagem dela cabe com folga nos 15 km.
