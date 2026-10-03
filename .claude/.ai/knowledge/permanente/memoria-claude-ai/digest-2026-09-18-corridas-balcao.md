---
id: memoria-claude-ai-digest-2026-09-18-corridas-balcao
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-18
zona: verde
confianca: alta
estado: atual
---

# Corridas de balcão (parte Flutter) — feito e o que falta

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-18-corridas-balcao`, origem `claude-code`, atualizada em 2026-09-18T14:29:54.429257+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 18 corridas balcao · memoria claude.ai · claude_ai_memoria

Missão central-corridas-balcao-2026-09-18 (parte Flutter, motor Sonnet 5/Claude Code — o motor pedido era glm-5.2/OpenCode mas a regra "porta unica" 16/09 manda executar pelo Claude Code). Servidor já tinha tudo pronto (RPC admin_tvde_create_counter_ride, colunas tvde_rides.source/agreed_fare_cents/agreed_driver_earn_cents, users.is_counter_client, tvde_client_places) — confirmei por SQL antes de codar, não escrevi SQL nenhum.
FEITO: (1) lado motorista — TvdeRide ganhou source/agreedFareCents/agreedDriverEarnCents + getters isCounterRide/netDriverEarnCents; TvdeFareView.of() checa agreed_fare_cents PRIMEIRO (nunca recalcula); ganho em grande trocado em 6 pontos (oferta, corrida ativa, fila, fim de corrida); selo azul "Cliente sem aplicação — liga-lhe" (nunca laranja, a oferta já está no limiar da regra 1-laranja/ecrã) desde a oferta até ao fim. (2) admin PT-BR: ecrã novo "Corridas de Balcão" (criar via RPC com busca de cliente por telefone + moradas guardadas + AddressAutocompleteField, ao vivo+histórico, reatribuir via admin_tvde_reassign_ride, cancelar via tvde_cancel_ride p_actor=cliente) e "Agenda de Clientes de Balcão" (moradas CRUD completo via tvde_client_places_admin_all; lista de clientes só-leitura). (3) testes: flutter analyze 0 erros; 165/165 testes TVDE verdes (33 novos, incluindo regressão sobre o texto-fonte dos 3 ecrãs do motorista — apanhou 2 pontos esquecidos no tvde_ride_active_screen.dart linhas 1409/1440); anti_trapaca.py --base HEAD CLEAN. Commit 91eb1534 (push confirmado por HTTP 200 na API do GitHub).
NÃO FEITO / GAPS DE SERVIDOR (para SQL/MCP, fora do meu âmbito): (a) admin_tvde_rides_list não devolve source/agreed_* e junta client_name/phone por auth.users (cliente de balcão nunca tem conta lá) — contornei com 2 SELECTs extra no Flutter, mas o ideal é estender a RPC e trocar o join para public.users (como tvde_ride_passenger_card já faz certo); (b) falta RPC admin_create_counter_client/update/delete — hoje só existe criar cliente como efeito colateral de criar corrida; (c) falta Edge Function para OCR de contacto solto (a ocr-receipt dos Favores está acoplada a uma encomenda). PENDENTE: prova visual em emulador Android NÃO foi feita (PC 4GB, risco de OOM) — coberta só por analyze+testes, dito claramente no relatório. Relatório completo: .claude/.ai/reports/central-corridas-balcao-2026-09-18.md
