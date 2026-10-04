# Agente tvde — relatório (04/10/2026)

Ramo: `agente-tvde` (commits a40db532 + 282d4347, também empurrado para origin/agente-tvde).
CI "Analise rapida" em `analise-tvde`: run 37229754409 VERDE (analyze sem erros, 7 avisos = igual à base; +941 testes todos a passar). Run final (com o tvde-payment v18, commit 282d4347): 37230281931 VERDE.

Produção (projeto ojykpzwqrtusfeakzrna):
- Migration aplicada `tvde_ronda_auditoria` = `supabase/migrations/20261004163000_tvde_ronda_auditoria.sql` (feita com replace() sobre a definição NO AR + verificação de que o texto antigo existe).
- Edge: `tvde-payment` v18, `notify-tvde-client` v6, `notify-tvde-driver` v21 (verify_jwt=true mantido; código igual ao do ramo — conferido byte a byte no tvde-payment).
- Settings novos: `tvde_km_fator_minimo`=1.25, `tvde_procura_max_minutos`=6, `tvde_partilha_base_url`. (`tvde_plan_driver_pct`=85 já existia.)

## FEITO

1. **C1 km do telemóvel** — novo `_tvde_km_seguro(origem, destino, km)` = max(km declarados, linha reta × fator). Aplicado em `tvde_request_ride`, `tvde_schedule_ride`, `tvde_schedule_roundtrip`, `tvde_request_return_ride`; e em `tvde-payment` `charge_roundtrip` (o preço do pacote online usava os km do cliente). O evento `solicitada` guarda `km_declarado`.
   Prova: 1 km declarado em 45,03 km de linha reta → km usados 56,29, preço 5600 cêntimos (tabela de 56,3 km), motorista 4480.
2. **C3 fim da corrida** — `tvde_finish_ride`: sócio passa a pagar extra + km acima da base (como ao pedir; antes perdia os km); plano passa a cobrar os km acima do incluído (antes 0) e a % lê `tvde_plan_driver_pct` (era 0.85 cravado); corrida de plano em dinheiro entra no acerto (km acima do plano recolhidos pelo motorista). `_tvde_finish_km_part` (mudança de destino) acompanha a mesma regra. Preço fixo: continua `est_distance_km` (fechado ao pedir) + mudanças de destino.
   Prova (rollback): PLANO km 10,01 → pedido 600 / final 600, motorista 680 (85%), acerto −0,80 €; SÓCIO pedido 950 / final 950 (antes ficaria 450).
3. **A2** — `tvde_offer_to_next` (2 sítios) e `admin_tvde_drivers_list`: `o.assigned_driver_id IN (d.user_id::text, d.id::text)` (era só d.id). Prova: 2 ocorrências na definição no ar.
4. **A4/A5** — `notify-tvde-client` v6: users.fcm_token + todas as `client_push_tokens` ativas; `notify-tvde-driver` v21: todos os aparelhos (drivers.fcm_token + `driver_push_tokens` ativas) em todos os tipos de aviso, limpeza de token morto na fonte certa.
5. **Procura com fim** — `tvde_dispatch_sweep`: corrida `solicitada` (não reserva, não retida, não balcão) a procurar há mais de `tvde_procura_max_minutos` desde a 1.ª oferta → `sem_motorista` (`cancel_reason='procura_esgotada'`); os gatilhos existentes fazem o reembolso automático (se paga) e o push ao cliente (texto novo: "não encontrámos motorista a tempo… se pagaste na app, o valor é devolvido"). Prova: corrida sem motorista há 7 min → `sem_motorista / procura_esgotada`. Cron 47 a correr sem erros depois da mudança (60/60 ok).
   **Aviso de oferta velho**: `notify-tvde-driver` relê a corrida e só toca se `status='solicitada'` e `current_offer_driver_id` = o motorista (senão regista `push_falhou / oferta_ja_nao_e_deste_motorista`).
6. **Graça desde a aceitação** — `tvde_cancel_ride` usa `cancel_grace_seconds` contado desde o último evento `motorista_atribuido` (fallback: criação). Prova: pedido há 10 min, aceite há 30 s → taxa 0.
7. **tvde-payment refund** — o cliente só consegue reembolso de corrida `cancelada_cliente/cancelada_motorista/sem_motorista/no_show`; finalizada → 409 `ride_not_refundable`; admin continua livre.
8. **Plano de outro cliente** — `tvde_consume_subscription_ride`: REVOKE a anon/authenticated (só service_role e funções internas) + guarda interna (só o próprio, o motorista da corrida em curso desse cliente, ou admin). `tvde_preview_coverage`: sem anon, e devolve `not_authorized` a quem pergunta por outro cliente. Prova: authenticated → "permission denied"; preview de outro → `{covered:false, reason:not_authorized}`.
9. **PT-PT** — parada→paragem em `tvde_ride_tracking_screen`, `ride_mbway_waiting_dialog`, `tvde_ride_active_screen` e nos pushes do motorista; "O valor final é calculado pela distância real" → "O preço é o que viste ao pedir" (app + push). Histórico de corridas: estados carregar / erro com "Tentar de novo" / vazio, e data em hora de Lisboa (`TvdeStore.historyLoading/historyLoaded/historyFailed`). Traduções EN acrescentadas em `lib/l10n/strings_en.dart` + `tool/l10n/traducoes/pt-en-10-tvde-ptpt.json` (NÃO corri o gerador: o strings_en.dart tem 167 entradas que não estão nos JSON e o gerador apagava-as).
10. **Partilhar viagem** — tabela `tvde_partilhas` (RLS: só o dono/admin lê; sem escrita direta), gatilho que fecha o link 30 min após o fim, RPC `tvde_criar_partilha(p_ride, p_origem)` (só o cliente da corrida; reaproveita o link ativo), RPC pública `tvde_ver_partilha(p_token)` (GRANT anon; nome próprio, carro, cor, matrícula, posição, destino arredondado ~1 km + zona, ETA, estado; sem telefones nem morada de recolha; também caduca às 24 h). Página `web/viagem.html` (chave pública, Leaflet/OSM, atualiza a cada 10 s, PT-PT, marca Bora). Botão "Partilhar viagem" no ecrã da corrida do cliente (folha de partilha do sistema) e "Partilhar viagem em tempo real" dentro do SOS (só cliente). Painel admin: ícone de partilha na linha da corrida (`admin_tvde_rides_list_v2` devolve `partilhada`). Prova: anon viu `{ok:true, estado:'em_andamento', motorista:'Estafeta', destino_zona:'Guarda', …}`; outro utilizador a criar link → `not_ride_client`.

## NÃO FEITO
- Lista original `achados/02-dispatch-tvde.md` perdeu-se; dos "restantes médios/baixos" só tratei o que vinha no resumo da missão (oferta sem tempo máximo, graça, aviso velho). Nada mais confirmado para corrigir.
- Corridas de **balcão** ficam fora do tempo máximo de procura (é o Danilo/central que as gere ao telefone). Se ele quiser incluí-las, é tirar a linha `source <> 'balcao'` do sweep.
- `web/viagem.html` só fica no ar quando o web for publicado (sai com o próximo build web do ramo principal).

## PRECISA DE CONFIRMAÇÃO
Nada pendente (não foi preciso DROP).

## PEDIDOS A OUTROS AGENTES
- PEDIDO A quem gere `lib/l10n/strings_en.dart` / `tool/l10n`: o dicionário e os JSON estão dessincronizados (strings_en tem ~167 entradas que não estão em `traducoes/*.json`). Não corram `gerar_dicionario.py --write` sem antes passar essas entradas para JSON, senão perdem traduções. As minhas estão em `pt-en-10-tvde-ptpt.json`.
- PEDIDO A dinheiro-entregas / quem mexe no `stripe-webhook`: nada a mudar; o reembolso de `procura_esgotada` vai pelo caminho de sempre (`fn_tvde_ride_auto_refund_on_cancel` → `tvde-payment auto_refund_ride`).

## RISCOS
- `tvde_finish_ride` agora cobra a sócios/planos os km extra que já lhes eram mostrados ao pedir (antes saíam de borla no fim). É a regra do preço fixo, mas muda o valor final dessas corridas.
- A mudança de destino em corridas de plano/sócio que estejam a decorrer NO MOMENTO da migração e já com mudança aplicada podiam contar a diferença duas vezes — `tvde_dest_change_enabled=false` hoje, por isso sem efeito real.
- `tvde_ver_partilha` usa a última posição conhecida do motorista; se o GPS estiver parado a página avisa "posição pode estar desatualizada".
