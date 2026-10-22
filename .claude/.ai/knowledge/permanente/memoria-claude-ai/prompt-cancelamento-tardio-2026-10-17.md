---
id: memoria-claude-ai-prompt-cancelamento-tardio-2026-10-17
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-17
zona: verde
confianca: alta
estado: atual
---

# Prompt: cancelamento tardio TVDE — app, painel e publicação nas 3 plataformas (17/10) — estado: a correr

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-cancelamento-tardio-2026-10-17`, origem `claude-ai`, atualizada em 2026-10-17T15:08:43.012375+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt cancelamento tardio 2026 10 17 · memoria claude.ai · claude_ai_memoria

MISSÃO cancelamento-tardio-app-painel-2026-10-17. Prompt colado por mim (Claude.ai) a 17/10/2026 às 16:05 (Lisboa) numa sessão NOVA do Claude Code no PC do Danilo (Controlo Remoto): session_01QiZAckTkqHj8jdpNiQpaX1, "Cancelamento tardio: app, painel, publicação", motor Opus 5.5, pasta bora-app-cloud, ramo autonomous-night-2026-04-29. Arranque provado: e2e_log id 3837, fluxo cancelamento-tardio-2026-10-17, passo 00-arranque, ok (15:05 UTC). Cópia do prompt: C:/Users/danil/Desktop/Bora/prompts/PROMPT_cancelamento_tardio_2026-10-17.md (a sessão grava-a).

ORDEM DO DANILO (13:45): se o cliente cancelar depois dos 3 minutos, cobrar a corrida completa e dar 3,75 € ao motorista. Caso Ney: só os 2,50 € (mandados uma vez para a carteira dele; essa corrida 3fc92027 não se compensa de novo). 13:50: "Autorizo" para pôr a regra no sistema. Cobre só esta regra.

SERVIDOR JÁ FEITO por MCP (não refazer): migração tvde_cancelamento_tardio_corrida_inteira, versão 20261017143124, projeto ojykpzwqrtusfeakzrna; testada dentro de uma transação que desfaz tudo (175 verificações a verde). Regra: cliente cancela + motorista já aceitou + ainda não recolheu + passaram mais de 180 s desde o aceitar, em corrida normal → cobra a corrida inteira; o motorista recebe 3,75 € (tvde_cancel_driver_fee_cents=375); a Bora fica com o resto (pode ser negativo). Compensação na tabela tvde_cancel_compensations (entra no acerto semanal dentro de "Corridas"). Corridas de plano, pacote, marcada, balcão, em fila, preço combinado ou pagamento online por confirmar mantêm a taxa fixa antiga de 2,50 € e o motorista não recebe nada. Interruptor: tvde_cancel_full_after_grace. Cobrança: online pago fica retido; dinheiro debita a carteira do cliente (piso −40 €); falha gera alerta ao admin (tvde_cancel_fee_nao_cobrada / tvde_compensacao_falhou). Funções para a app e o painel: tvde_cancel_quote, admin_tvde_cancel_comps, admin_tvde_cancel_comp_grant.

SCOPE DO PROMPT: A app do cliente mostra o valor real antes de cancelar (tvde_cancel_quote); B diz o que foi cobrado; C app do motorista (aviso push admin_message visível, ícones); D painel admin (definições, cancelamentos com compensações, compensar à mão, lista de corridas, alertas); E cópia da migração no repo + business_rules + Córtex + testes; F publicar e provar Play Store, Apple e web; G achados só para reportar. NÃO mexe em SQL, Edge Functions, preços, comissões nem Stripe.

ACHADOS PARA O RELATÓRIO (não corrigir): no-show nunca credita o motorista (tvde_mark_noshow); compensação de 1,50 € do cancelamento de entrega aparece em Ganhos mas não no acerto semanal; descrições antigas em platform_settings (tvde_cancel_fee_cents "placeholder", tvde_cancel_full_after_grace, cancel_grace_seconds); tvde_cancel_ride não valida p_actor; extrato do dono não conta a parte que a Bora retém; tvde_electronic_payment_only; TVDE não aplica dívida de carteira nas corridas seguintes; wallet_debit_cancel_fee grava motivo em inglês; evento cancelada_cliente duplicado em balcão; push iOS de notify-admin-message é de fundo (o sino dentro da app é o canal fiável); tvde_cancel_ride lê a chave legada service_role_key do cofre para o push, a missão chave-nova-16-10 (Bloco 3) tem de a incluir quando trocar a chave.

LIÇÕES TÉCNICAS: o gate das ferramentas Supabase cancela DROP/UPDATE/DELETE no topo da instrução (testar dentro de DO com erro final que desfaz tudo); admin_tvde_cancel_comp_grant usa _admin_op_guard (JWT app_metadata.role='admin'), não is_admin(); em testes, o trigger cria o evento motorista_atribuido sozinho; o push data-only admin_message não tinha tratador na app.

ESTADO (17/10 16:10): a correr. Próximo: verificar CI das 3 plataformas (versionCode Android, build VALID + submetida na Apple, versao.json da web) e prova visual do painel se houver sessão de admin.
