---
id: memoria-claude-ai-digest-2026-10-10-reservas-num-so-sitio
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-10
zona: verde
confianca: alta
estado: atual
---

# Claude Code 10/10 — separador Reserva com tudo o que o cliente marcou

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-10-reservas-num-so-sitio`, origem `claude-code`, atualizada em 2026-10-10T08:08:53.427572+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 10 reservas num so sitio · memoria claude.ai · claude_ai_memoria

O separador "Reserva" da barra de baixo do cliente passou a juntar mesas, corridas marcadas (tvde_rides com scheduled_at), limpezas e marcações, em Próximas/Passadas/Canceladas, ordenadas pela hora marcada, com tipo, hora de Lisboa, sítio, estado e pagamento. Motivo: Ricardo (corrida marcada paga) e Divan (limpeza paga) não encontravam as reservas porque o separador só lia as mesas. Corrida que aos 20 min passa a motorista a caminho continua em Próximas até acabar. Tocar abre o ecrã de detalhe que já existia; cancelar/reembolsar ficou onde estava. Depois de marcar barbearia, limpeza ou corrida para depois há o botão "Ver nas minhas reservas" (ClientMainScreen.abrirSeparador). Painel admin: menu do cliente > "Reservas (mesas, corridas, limpezas, marcações)", só leitura. Código: lib/utils/minhas_reservas.dart (função pura juntarReservas), lib/screens/client_reservations_screen.dart, lib/screens/admin/admin_cliente_reservas_screen.dart. CleaningStore/TvdeStore ganharam bandeira de falha (myBookingsFailed/myReservationsFailed). Publicado: web 660, Android versionCode 661 (Play interno+alpha+produção), iPhone build 179 submetido (1.0.15, WAITING_FOR_REVIEW, lançamento automático). O guião .github/scripts/ios_publicar.py passou a reaproveitar a versão em READY_FOR_REVIEW (500 da Apple na corrida 177 deixava-a presa). Provas sem escrever no banco: web por interceção das leituras no Playwright (antes 659 só mesa, depois 660 os 4), Android por integration_test com stores falsos, iPhone pela varredura do simulador do CI. Falta: hora da limpeza vai pelo relógio do telemóvel (cleaning_wizard_screen.dart:522), dois ecrãs mostram hora do telemóvel e não de Lisboa, rótulo do separador ainda "Reserva" no singular. Relatório: .claude/.ai/reports/reservas-num-so-sitio-2026-10-10.md.
