---
id: memoria-claude-ai-livro-areas-fecho-semanal
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Regras do Danilo para o acerto semanal do [[bora-app]] (recibos automáticos, comprovativo ao marcar pago, cobrança automática) + estado real da automação (causa raiz do email nunca sair, crons, prompt de 07/09) — ler ANTES de mexer no fecho semanal

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-fecho-semanal`, origem `claude-ai`, atualizada em 2026-10-23T05:39:25.793428+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas fecho semanal · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/fecho-semanal.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: fecho-semanal
description: Regras do Danilo para o acerto semanal do [[bora-app]] (recibos automáticos, comprovativo ao marcar pago, cobrança automática) + estado real da automação (causa raiz do email nunca sair, crons, prompt de 07/09) — ler ANTES de mexer no fecho semanal
sources: [chat]
aliases: [fecho semanal, acerto semanal, recibo semanal, fechos semanais, acertos da semana]
---

- [stated] REGRA (05/09): todo fecho de semana tem de mandar SOZINHO um recibo por email a cada estafeta e a cada parceiro, sem ele ter de pedir. O recibo leva tudo detalhado — quantas entregas/pedidos, quanto ganhou, quanto recebeu em dinheiro dos clientes, e o saldo.
- [stated] Quem DEVE à Bora paga por MB Way para o número do Danilo, e esse número tem de vir escrito no próprio recibo.
- [stated] Quem a Bora tem de pagar recebe por MB Way ou transferência, à segunda-feira.
- [stated] Ele já tem o domínio próprio (era o que faltava para os emails saírem); disse que isto já devia estar a funcionar há tempo.
- [stated] Parceiro sem contactos e dados fiscais reais não recebe recibo — tem de pedir esses dados ao dono antes do primeiro acerto. O caso [[goola-acai]] ficou RESOLVIDO a 06/09: o dono entregou tudo e a ficha da loja está completa.

Regras novas e estado real (2026-09-07, Claude.ai via MCP)
- [stated] REGRAS NOVAS (07/09): a notificação do fecho tem de abrir com UM toque o ecrã certo, já com tudo (a quem pagar e quanto, quem lhe deve e quanto), onde ele paga e marca "pago" ou "recebido" sem conferir nada. Ao marcar PAGO, o parceiro/estafeta recebe SOZINHO o comprovativo de pagamento. Quem deve à Bora recebe mensagem automática a dizer quanto e para que MB Way. Tudo automático: ele só recebe quanto tem de pagar/receber de cada pessoa. Pediu para copiar o que os grandes (Uber/Glovo/iFood) fazem.
- CAUSA RAIZ de nunca ter chegado email nenhum (nem a ele): as Edge Functions NUNCA tiveram RESEND_API_KEY (19 variáveis de ambiente, nenhuma de email). Não era o domínio nem as settings — weekly_digest_emails_enabled=true e bora_mbway_phone=931992662 estão certos. Não voltar a suspeitar disso.
- FEITO por MCP: Edge weekly-closeout-digest v5/v6 — v5 lê a chave do env e, se faltar, do vault via RPC get_resend_key (secret 'resend_api_key', só service_role); v6 idempotente: linha com email_status='sent' não reenvia salvo force:true (admin_resend_weekly_digest, botão "Reenviar digest", já manda force:true). Crons: o job 26 `run_weekly_closeout()` (activo, 00:05 UTC de segunda) fecha TODOS os tipos — chama por dentro `compute_all_cleaner_weekly_settlements`, `compute_all_provider_weekly_payouts` e `compute_all_washer_weekly_settlements`, cada uma protegida por excepção — e o digest (job 63) sai às 00:20 UTC; semana fecha domingo→segunda e sai tudo de uma vez. ⚠️ Os jobs 43, 58 e 69 (as mesmas três funções soltas, no MESMO minuto) estão DESLIGADOS DE PROPÓSITO: foram consolidados no 26 e ligá-los DUPLICA o acerto semanal de toda a gente. Verificado por MCP a 07 e 08/09 (li a função) depois de terem sido levantados como "3 acertos desligados que mexem em dinheiro" — é falso alarme, não os ligar. Telegram do admin provado vivo (3 disparos reais nesse dia).
- Semana 31/08-06/09 tratada à mão: 4 entregas, todas em dinheiro. Recibos enviados pelo Gmail do Danilo ao Goola (19,80 € a receber, MB Way 911519501), ao Valdemir (deve 23,56 €, email valdemirvasconcelos28@gmail.com) e resumo a boraappbora@gmail.com. [stated] Danilo mandou marcar: Goola PAGO (pagou ele por MB Way), Valdemir RECEBIDO e a própria conta de estafeta dele (−9,62 €, interno) RECEBIDO — feito por MCP, com auditoria. weekly_digest_log da semana 2026-08-30 = 'sent'. NUNCA reenviar essa semana com force:true (duplicaria ao Goola e ao Valdemir).
- Sistema que já existe: tabelas driver/partner/cleaner_weekly_settlements + appointment_payouts (lavagem fica FORA do weekly_closeout_compile); RPCs admin_weekly_closeout_list, admin_mark_settlement_paid (só sabe 'paid'), admin_resend_weekly_digest, partner_my_weekly_closeout; ecrã lib/screens/admin/admin_acertos_semana_screen.dart ligado ao dashboard. Defeito: a rota /admin/acertos-semana NÃO está registada em main.dart — tocar no aviso não abre nada (só existe /admin/settlements, ecrã antigo). Recomputes não tocam em acertos 'paid'/'received'. Semana = segunda 00:00 a domingo 23:59:59 Lisboa; week_start_at::date em UTC faz a semana de 31/08 aparecer como 2026-08-30 — é consistente, não "corrigir". Repo tem a v4 do digest: trazer sempre a versão deployed antes de editar.
- [stated] PROMPT REGISTADO: PROMPT_fecho_semanal_automatico_2026-09-07.md, motor OPUS, sessão nova `fecho-semanal-automatico` na pasta bora-app-cloud. Scope em 8 blocos: (0) chave do Resend pelo agente de clique no Chrome do perfil boraappbora, guardar em secrets E vault, prova com a semana 2026-08-23 (só tem o Danilo); (1) notificação abre Acertos da semana (rota, um aviso só, link clicável no Telegram); (2) ecrã ao nível Uber — Pagar/Marcar pago/Marcar recebido com 1 toque, admin_mark_settlement_paid a aceitar 'received', prévia da semana em curso, CSV; (3) comprovativo automático ao marcar pago/recebido (trigger → Edge → Resend + push data-only, com retry); (4) cobrança automática — lembretes qua/sex, Telegram dos atrasados, carry-over da dívida para a semana seguinte, tecto de bloqueio do estafeta desligado por defeito; (5) separador Acertos no app do parceiro e cartão do estafeta; (6) lavagem no compile + consolidar o fecho; (7) painel admin com autoridade total; (8) provas no emulador Android. Estado: ENTREGUE 07/09, por correr.
- [stated] DOMÍNIO DOS EMAILS (07/09): não quer registar nem configurar domínio novo agora — manda usar o domínio que já é dele (o do Bora), com um subdomínio criado pelo Cloudflare para o envio.
- [stated] COBRANÇA DE QUEM DEVE (07/09): a dívida não morre na semana em que aconteceu — passa a ser cobrada na semana seguinte e continua a ser cobrada, sozinha, até a pessoa pagar. A mensagem tem de SUBIR DE TOM a cada aviso e chegar ao ponto de dizer que a conta dela corre risco. E tem de falar diferente a um ESTAFETA e a um PARCEIRO, porque o que cada um deve e o que arrisca não é a mesma coisa.

FINAL WRITE

Estado a 2026-09-14 (Claude.ai via MCP, 00h-00h40 de Lisboa)
- ✅ CANAL DE EMAIL PROVADO VIVO: a chave já está no vault (`resend_api_key`, válida, do tipo "só enviar") e um envio real de `fecho@boraguarda.com` para boraappbora devolveu 200. Ou seja o remetente/domínio boraguarda.com está verificado e os recibos passam a sair sozinhos — a causa raiz de 07/09 está fechada. Os crons 26/63 correm às 00:05 e 00:20 UTC, que em Lisboa é 01:05 e 01:20 de segunda: entre a meia-noite e a 1h o fecho AINDA não correu e isso não é avaria.
- [stated] Ele cobrou o email ao virar a semana (00:15 de segunda) contando com ele para si como motorista, para o Valdemir, para o [[goola-acai]] e para o barbeiro da [[ouro-e-prata]].
- Até 13/09 nunca saiu um recibo automático: as linhas 'sent' das semanas 2026-08-23 e 2026-08-30 foram envios à mão pelo Gmail dele.
- ⚠️ Pedidos de DEMO entram no acerto como se fossem pessoas (semana 07-13/09 nasceu com uma linha "Estafeta Demo", email inventado) e os contadores do painel contam em UTC — ambos vão no prompt de [[painel-admin]].
- ⚠️ TABELA `payouts` É LIXO, NÃO PAGAR POR ELA (achado por mim a 14/09): um cron às 03:00 de domingo→segunda escreve linhas paralelas às *_weekly_settlements, que ficam eternamente 'pending' porque marcar pago no acerto oficial não as toca — e inventa valores sem base (linha de 10,29 € para a Sabores do Brasil, loja que nunca teve um único pedido). Fonte de verdade do fecho = partner/driver/cleaner/washer_weekly_settlements + appointment_payouts. Prometi ao Danilo pôr a correção na lista.
- Marcar pago por MCP quando ele avisa que pagou: UPDATE na linha do acerto (status/paid_at/paid_by=c9fccf85-03ee-4efc-83bf-613f211a78ff/payment_reference/notes) + INSERT em admin_audit_log — foi assim a 07/09 e a 14/09.
- Acertos de SERVIÇOS (barbearia) vivem em `appointment_payouts`, não nas tabelas de parceiro — por isso escapam a quem só olha para partner_weekly_settlements. Modelo desde 14/09: cliente paga o corte inteiro no app e o barbeiro recebe tudo menos a taxa que a Stripe cobrou nesse pagamento — os 0,50 € por marcação acabaram (ver [[ouro-e-prata]]).

FINAL WRITE

- [stated] 21/09: o número onde a Bora cobra (931992662) é o MB Way **PESSOAL** dele, e ele dá-o também aos clientes de balcão. Com isso passou do limite de transferências e deixou de conseguir receber por MB Way — foi por isso que desligou o MB Way na app nesse dia. Enquanto estafetas, parceiros e clientes lhe pagarem a esse número, volta a bater no tecto
- DISTINÇÃO a não confundir em futuras conversas (verificada no código a 21/09): o MB Way do CHECKOUT da app não passa por esse número — é um pagamento Stripe de comerciante, e o telefone que vai no pedido é o do CLIENTE, só para lhe chegar o push; o dinheiro cai no saldo da Stripe. Só a cobrança de quem deve à Bora e o que ele dá à mão é que caem no número pessoal
- [stated] 12/10: Danilo disse que já pagou à Mayra (limpeza, 27,54 €) e à conta de estafeta dele (99,36 €) da semana 05-11/10 e mandou marcar pago. Feito por MCP com auditoria (admin_audit_log), status 'paid' nas duas linhas.

