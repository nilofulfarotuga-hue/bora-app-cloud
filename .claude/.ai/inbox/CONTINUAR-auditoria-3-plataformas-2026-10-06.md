# CONTINUAR — auditoria das 3 plataformas (06/10, corrida a 07/10)

Relatório: .claude/.ai/reports/auditoria-3-plataformas-2026-10-06.md. Provas: .claude/.ai/provas/auditoria-3-plataformas-2026-10-06/ (paridade.md, continuacoes.md, ramos-e-pr1.md).

Feito e publicado nesta missão: painel da corrida (chaves), câmara do mapa, GPS em fundo (regra + religar + gerações), aviso ao parceiro (servidor e Android), web sem apagar o service worker do Firebase, e-mail do suporte, GPS do iPhone em fundo, cache da zona boraguarda.com.

## Por fazer (sem dinheiro), por ordem de impacto

> **07/10 (noite):** itens 3, 4, 5, 6 e 7 FEITOS (sem commit) — provas e resumo em
> `.claude/.ai/provas/auditoria-pendencias-20261007/resumo.md`. Ficam 1, 2 e 8.

1. GPS do ecrã da corrida herda o fluxo da home. O geolocator guarda um único fluxo por app (geolocator_android 5.1.x geolocator_android.dart:169-171 e 208-211; geolocator_apple 2.3.x 156-157 e 195-197): enquanto a home TVDE ouve, o getPositionStream do ecrã da corrida devolve o fluxo da home, com as definições dela (15 s, sem as 3 m / 700 ms). Conserto proposto: no _assumirGps do TvdeRideActiveScreen, depois de a home largar (tvdeCorridaControlaGps a true e o _gps da home cancelado), voltar a subscrever uma vez para as definições da corrida valerem. Mexe na passagem do GPS entre a home e a corrida — provar com um aparelho, sem motoristas reais ligados.
2. iPhone: ligar "Time Sensitive Notifications" no App ID (portal da Apple, perfil Bora), regenerar o perfil e acrescentar com.apple.developer.usernotifications.time-sensitive ao ios/Runner/Runner.entitlements — tudo no mesmo envio, senão o build do iPhone parte. Hoje as ofertas no iPhone chegam sem som no modo Foco / A conduzir.
3. Web: som no Safari do painel do parceiro (partner_dashboard_screen.dart ~553) e da oferta TVDE (tvde_offer_screen.dart ~86) — leitor de áudio partilhado e desbloqueado no primeiro toque (o desbloqueio é por leitor; cada SoundService cria o seu).
4. Web: avisos para cliente e parceiro (hoje só o estafeta regista token na web) — botão "Ativar notificações" que regista o token no toque, e o clique no service worker a abrir o destino pelo tipo (hoje manda tudo para /#/driver).
5. app_latest_version_code_ios está a 0 (o aviso de versão nova do iPhone está desligado) — o CI não o escreve; decidir o número e quando.
6. iPhone: notificações locais com som genérico — DarwinNotificationDetails(sound: 'bora_alert.wav') nas de pedido e oferta (notification_service.dart, 11 chamadas).
7. Chat da limpeza: lib/screens/shared/cleaning_chat_screen.dart lê o CleaningChatStore dentro do dispose (o mesmo defeito corrigido no botão a 03/10) — guardar o store no initState.
8. Android em "inactive" (cortina de notificações puxada, ecrã dividido sem foco) passou a contar como fundo para o serviço de localização: liga sem serviço e religa ao voltar a tocar na app. Aceite por ser seguro; rever se der problemas.

## Só com o "vai" do Danilo (proposta prop-3b74506b no Córtex)

notify-tvde-driver stop_added com o paid_cents do vale; plano TVDE por rota; dispatch_gps_fresh_seconds_entregas de volta a 900; link partilhado de loja sem configureSession (preço no cliente); protecção do log_admin_action (NÃO pôr is_admin lá dentro).

## Com prazo

OAuth do Gmail da caça a clientes: publicar ATÉ 10/10 — ordem ordem-20261007111613-ede9.
