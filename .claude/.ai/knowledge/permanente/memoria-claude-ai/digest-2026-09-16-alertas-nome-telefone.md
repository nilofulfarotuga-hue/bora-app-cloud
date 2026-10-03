---
id: memoria-claude-ai-digest-2026-09-16-alertas-nome-telefone
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-16
zona: verde
confianca: alta
estado: atual
---

# Claude.ai 16/09 — avisos do Telegram passam a trazer nome e telefone do cliente na 1.ª linha

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-16-alertas-nome-telefone`, origem `claude-ai`, atualizada em 2026-09-16T17:36:04.850976+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 16 alertas nome telefone · memoria claude.ai · claude_ai_memoria

QUEIXA DO DANILO (16/09 ~18:20): no Telegram só chegava "tem pedido", sem o nome da pessoa. CASO QUE A DISPAROU: reserva TVDE #025b7f53 de uma cliente nova (conta criada 5 min antes, a partir do navegador do Instagram num iPhone), marcada para sex 18/09 07:31, Largo de São Pedro → Action Guarda, 5 EUR, dinheiro; aceite em 6 s pelo próprio Danilo como motorista e cancelada pela cliente 23 s depois de marcar; taxa 0; o motivo não fica registado porque a app não pergunta o motivo quando o cliente cancela uma reserva.
CAUSA DO NOME EM FALTA: (1) os avisos de pedido de delivery nunca levaram nome nem telefone; (2) cada reserva TVDE em dinheiro gerava DOIS avisos no Telegram — o do trigger notify_new_tvde_ride_admin (com nome, perdido no meio da linha) e um 2.º do tvde_schedule_ride, sem nome; (3) todas as mensagens começavam por "Ação pendente — Bora Admin", que é o que aparece na pré-visualização.
FEITO por MCP (migration alerta_telegram_nome_telefone_primeiro_2026_09_16): helpers _alerta_quem e _alerta_quando + construtores _alerta_txt_tvde, _alerta_txt_pedido, _alerta_txt_limpeza, _alerta_txt_lavagem (EXECUTE só postgres/service_role — devolvem nome e telefone). Triggers notify_new_tvde_ride_admin, notify_new_order_admin, _trg_cleaning_notify_admin_new e notify_new_carwash_admin com texto em linhas (1.ª linha = o quê + NOME + TELEFONE) e rede de segurança: se o texto falhar, o aviso sai na mesma com texto curto. notify_admin_urgent_push: resumo com várias linhas → a 1.ª linha vira o título do Telegram/push; resumos de uma linha (cadastro, marcação, mesa) ficam exatamente iguais. tvde_schedule_ride: removido o 2.º aviso por corte cirúrgico no texto da função viva (resto e permissões intactos). Reservas TVDE passam a event_type tvde_reservation_new com link /admin/tvde/reservas.
PROVADO: textos gerados sobre linhas reais (reserva, corrida já, pedido Goola, limpeza, lavagem); ponta a ponta em transação revertida (tvde_schedule_ride com a conta do Danilo) → 1 aviso só, título "RESERVA TVDE — nome · telefone"; zero lixo no banco. Confirmado também que trg_notify_new_appointment_admin (marcações, 14/09) está instalado e ativo.
ARMADILHAS: estas funções só existem assim em produção — migration antiga do repo que recrie tvde_schedule_ride ou os triggers de aviso repõe o aviso duplicado e sem nome. tvde_reservation_mark_paid ("RESERVA PAGA", cartão/MB Way) continua sem nome, de propósito (caminho de pagamento). POR CORRIGIR: quando o cliente cancela uma reserva já aceite, o motorista recebe 2 pushes (reservation_cancelled + ride_cancelled); e a app não pede motivo ao cliente ao cancelar reserva.
