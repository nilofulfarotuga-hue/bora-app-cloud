---
id: memoria-claude-ai-digest-2026-09-23-ronda-fecho
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-23
zona: verde
confianca: alta
estado: atual
---

# Digest ronda-fecho-2026-09-22 (retoma cloud 23/09)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-23-ronda-fecho`, origem `claude-code-cloud (fable)`, atualizada em 2026-09-23T20:03:43.941286+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 23 ronda fecho · memoria claude.ai · claude_ai_memoria

# Digest — ronda-fecho-2026-09-22 (retoma na nuvem, 23/09/2026)

**Estado:** fechada. Commits no ramo autonomous-night-2026-04-29: 5617c00 (blocos A + D1-D3 + migrações), 6e84c90 (painel E/D4 + relatório), 3c3e9e7 (telemetria). Relatório completo: RONDA-FECHO-2026-09-22.md na raiz do repo. e2e_log: fluxo/run_id ronda-fecho-2026-09-22 (uma linha por bloco, com prova).

## O que mudou em produção (Supabase, 23/09)
- Migrações (versão real): 20260923124352 A7 sweep pagamentos; 20260923124436/124627/124644/124442 A2 (guarda de distância na volta do pacote, hold + admin_tvde_ride_release_hold, tvde_offer_to_next com GPS fresco, evento da volta da Stela corrigido -39,50→-3,50); 20260923124519 A5 (ops_tvde_* para a central sem JWT); 20260923125347 A8 (estafeta online sem push: meu_estado_push + trigger de alerta); 20260923125722 + 20260923130945 A10 (presença: GPS parado põe offline, heartbeat só re-liga com GPS vivo, cron a cada minuto, admin_drivers_for_assignment com gps_age_s); 20260923130000 A9 (Robot B nível 1 ligado; 83 sem foto + 10 preços suspeitos em needs_review; categorização em massa só proposta); 20260923131328 D3 (dados legais + autocertificação DSA obrigatórios antes de aprovar, users.marketing_opt_in, broadcast só a opt-in); 20260923132348 E/D4 (admin_pendencias_operacao, admin_driver_avisar_gps, admin_conformidade_legal, admin_dac7_export).
- Edge: execute-broadcast v7 (filtra por opt-in; fonte agora no repo). dispatch-engine NÃO redeployado (prod v61 ≠ repo v58).
- Chaves novas: tvde_roundtrip_return_max_ratio=3, tvde_roundtrip_return_max_km=30, dispatch_gps_fresh_seconds=180, dispatch_gps_offline_seconds=1800 (baixar para 180 quando o build ≥618 estiver nos telemóveis), conformidade_ativacao_obrigatoria=true, robot_b_auto_level1_enabled=true.

## App / painel (build a sair do CI)
- Estafeta: opções do produto na lista; cartão "Ativar notificações"; posição nativa em cada batida; oferta de reserva em banner compacto quando há corrida ativa.
- Cliente: ecrã "Sobre / Informação legal" (3 papéis); "Encomenda com obrigação de pagar" + aviso DL 24/2014 em 7 checkouts; vendedor (nome/NIF/morada) no recibo; opt-in de marketing separado no perfil.
- Registo de prestadores (5 formulários): nome legal, NIF, morada, IBAN, data de nascimento, autocertificação DSA (RPC provider_update_legal_fields).
- Painel PT-BR: "Pendências de operação" (/admin/pendencias) e "Conformidade legal" com CSV DAC7 (/admin/conformidade); chip "GPS parado há X min"; rotas novas /admin/reembolsos, /admin/tvde/ida-e-volta, /admin/drivers, /admin/tvde/cancelamentos, /admin/reservas/presas, /admin/configuracoes, /admin/parceiros, /admin/notificacoes.

## Regras para os outros motores
- Central/agentes sem JWT: TVDE de balcão só por ops_tvde_counter_clients_list / ops_tvde_counter_client_save / ops_tvde_create_counter_ride / ops_tvde_reservation_create (nunca alargar is_admin).
- Aprovar prestador sem dados legais é recusado pelo gatilho (conformidade_incompleta: faltam …); bora.forcar_ativacao='1' só com o Danilo.
- Volta de pacote suspeita fica retida (dispatch_hold_reason) até admin_tvde_ride_release_hold.
- dart format do SDK 3.11 não é o estilo do repo: nunca formatar ficheiros inteiros.

## Bloqueado / à espera do Danilo
- Site: docs/legal/informacao-legal.html pronto; publicar no bora-site pelo PC (wrangler) + logótipo oficial do Livro de Reclamações.
- Stripe: classificação dos pagamentos falhados (MCP sem autenticação nesta sessão).
- 💰 Saldo do Danilo em tvde_driver_balances (-104,45; eventos -82,65): proposta de ajuste +36,00 com backup e auditoria — só com o "vai" (não há RPC de ajuste).
- Fora de scope reportado: admin_tvde_counter_clients_list sem dígitos devolve todos; NIF/IBAN de parceiros legíveis por clientes na RLS de restaurants; AndroidManifest sem mailto/https em <queries>; skill CEO-AI diz 43 Edge Functions (são 78).

## Desfecho do CI (23/09, 20:05 UTC)
- Android: runs 456/458 verdes -> Google Play 1.0.3+618 e +619 (internal+alpha+production); run 459 (+620, ficha legal TVDE) passou o bump com o `-X theirs` (811cb7a) e estava a compilar o AAB. Correcao do arnes (b27986a): o botao final chama-se "Encomenda com obrigacao de pagar".
- iOS: comboio 1.0.2 fechado pela Apple (aprovada 22/09) -> nome 1.0.3 (aa42b49, so o nome). Run 137 (ad3da17, venv PEP 668): build 137 carregado, versao 1.0.3 criada com AFTER_APPROVAL e submetida (submissao de5436ac, WAITING_FOR_REVIEW 19:59Z). Entra na App Store sozinha quando a Apple aprovar; para travar, retirar a submissao no App Store Connect.
- Provas: e2e_log fluxo ronda-fecho-2026-09-22, passos f-ci-* e f-ios-*. Relatorio actualizado no repo (RONDA-FECHO-2026-09-22.md, ultimo paragrafo).
