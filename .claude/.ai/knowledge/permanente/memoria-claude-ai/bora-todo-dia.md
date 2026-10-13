---
id: memoria-claude-ai-bora-todo-dia
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-13
zona: verde
confianca: alta
estado: atual
---

# Bora Todo Dia — 5 novidades para o cliente abrir a app todos os dias (n.º 1: check-in diário)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `bora-todo-dia`, origem `claude-code`, atualizada em 2026-10-13T10:25:18.021447+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: bora todo dia · memoria claude.ai · claude_ai_memoria

Bora Todo Dia: o Danilo quer que os clientes abram a app todos os dias, não só quando precisam de pedido. São 5 novidades, uma por semana. Esta página guarda o estado de cada uma.

NOVIDADE N.º 1 — CHECK-IN DIÁRIO (missão de 13/10/2026, Claude Code no PC).
Regras fixadas pelo Danilo a 13/10: ciclo de 7 dias, tokens por dia 5, 5, 10, 10, 15, 15, 40 (semana completa = 100 tokens = 0,50 €). Falhou um dia de calendário (hora de Lisboa) volta ao Dia 1; depois do Dia 7 começa outro ciclo no Dia 1; um check-in por dia; só clientes com telemóvel; tokens com validade de 60 dias; sem roletas nem sorteios (jogo de fortuna em Portugal). Lembretes por push: às 11h a quem ainda não fez o de hoje; às 20h só a quem fez ontem e ainda não fez hoje; no máximo 2 por pessoa por dia; horas e interruptores no painel.

O QUE ESTÁ NO AR (commits f405bc28, 1f7bf305, ecdd0dcd, push às 11:01 de 13/10): o cartão "Check-in diário" na home do cliente (PT-PT, verde, Inter; 7 dias, dia de hoje destacado, botão Fazer check-in, tokens a entrar, "Volta amanhã para ganhar X tokens"; sem telemóvel pede para confirmar e abre o ecrã de completar perfil) e a página "Check-in diário" no painel admin, secção Clientes (ligar/desligar, os 7 valores e a validade com motivo, lembretes 11h/20h, quem está em que dia, custo por dia/semana/mês em €, dar e tirar tokens com registo, CSV). O cartão ESCONDE-SE sozinho enquanto o servidor não tiver as funções — hoje não aparece a ninguém.

O QUE FALTA NO SERVIDOR (nada disto está aplicado):
1) Migração SEM dinheiro supabase/migrations/20261013060000_checkin_diario_base.sql (tabela daily_checkins, tabela de lembretes, definições checkin_*, client_checkin_status, lembretes por pg_cron de hora a hora, leituras do painel). A bora-tranca recusou-a duas vezes no PC (1.ª por ler token_value_cents_x100 e gravar a validade; 2.ª na caixa). PEDIDO À CLAUDE.AI: aplicar pelo conector, tal como está no repo (a ordem do Danilo de 13/10 cobre esta parte). Aplicá-la sozinha não liga nada.
2) Parte de DINHEIRO, em .claude/.ai/missoes/bora-todo-dia-checkin-2026-10-13/proposta-credito-checkin.md: a função client_daily_checkin (grava o check-in e põe os tokens em bora_tokens na mesma transação) e os valores checkin_rewards e checkin_token_expiry_days. ESPERA O "VAI" DO DANILO. Aplicada esta, o check-in liga-se sozinho para todos, sem nova versão da app. Prova a correr logo a seguir: prova-producao-depois-do-vai.md (tudo revertido).
Prova local (PGlite, Postgres no PC com base falsa e o índice único real de bora_tokens): 62 de 62. Verificador de contexto limpo: aceite com ressalvas, ressalvas de código corrigidas.

DECISÕES QUE SÃO DO DANILO:
a) Nenhum cliente aceitou promoções (marketing_opt_in = 0). Com o interruptor "só quem aceitou promoções" ligado (regra RGPD de 23/09, igual à reativação), os lembretes não chegam a ninguém. Desligar é decisão legal dele.
b) Não existe confirmação de telemóvel por SMS na Bora. "Telemóvel confirmado" é um número português válido gravado no perfil. Há 7 números repetidos em 17 contas; uma conta falsa ganharia 0,50 € por semana. Exigir número único ou SMS é decisão dele.
c) O lembrete das 20h vai também a quem fez o Dia 7 ontem ("Não percas a tua sequência de 7 dias!"), porque a regra dele diz "fizeram check-in ontem". Nesse caso não há nada a perder (o ciclo recomeça). Se preferir, muda-se para Dia 1 a 6.
d) source_order_id ficou checkin-AAAA-MM-DD-<id da pessoa>, e não checkin-AAAA-MM-DD: bora_tokens tem um índice único por (source_order_id, papel) e o segundo cliente do dia dava erro. Mesmo padrão do BEMVINDO.

NOVIDADES N.º 2 a 5: ainda por definir pelo Danilo.
