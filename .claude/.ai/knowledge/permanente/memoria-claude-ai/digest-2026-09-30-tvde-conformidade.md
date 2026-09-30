---
id: memoria-claude-ai-digest-2026-09-30-tvde-conformidade
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-30
zona: verde
confianca: alta
estado: atual
---

# TVDE: conformidade Lei 59/2026 pronta atrás de interruptores (30/09)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-30-tvde-conformidade`, origem `claude-code`, atualizada em 2026-09-30T11:28:13.346089+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 30 tvde conformidade · memoria claude.ai · claude_ai_memoria

O TVDE do Bora está tecnicamente preparado para a Lei 45/2018 na versão da Lei 59/2026 (em vigor 01/09/2026), tudo atrás de interruptores DESLIGADOS: o mestre é platform_settings.tvde_compliance_enforce=false, e com ele desligado a app funciona exatamente como antes (provado com uma corrida em dinheiro de ponta a ponta em rollback: 5/4/1 euros). Há 14 tabelas novas com RLS (operadores, veículos, motorista-carro, tempos de serviço, queixas, eventos de conformidade, SOS, acesso de fiscalização, verificação do teto de 25 por cento, relatório AMT, faturas, checklist), regras no servidor (bloqueio art. 14, 10 horas art. 13, só pagamento eletrónico art. 15.7, preferências fala-português e mobilidade reduzida) e um portão de uma linha no despacho (tvde_driver_offer_allowed) que devolve sempre true com o mestre desligado. No painel admin há a secção "Conformidade TVDE (IMT/AMT)" com 12 separadores; a página pública das entidades fiscalizadoras é app.boraguarda.com/fiscalizacao.html?c=CODIGO (o código gera-se no admin). O cliente vê preço discriminado, queixas com Livro de Reclamações, operador da plataforma, cartão do motorista com CMTVDE, SOS e "Resumo da viagem" (nunca "fatura"). O motorista tem a área Conformidade e o contador de horas. Como se usa: a ordem exata dos interruptores no dia da licença está em .claude/.ai/reports/tvde-interruptores-dia-da-licenca-2026-09-30.md. O que falta: empresa, licença IMT, operadores e carros reais, faturação certificada (hoje stub), especificação do IMT (não publicada) e preço fixo fechado (obrigatório, art. 15.6, mexe em dinheiro, espera o "vai"). Achados graves para o Danilo: 116 corridas TVDE feitas sem licença (63 em dinheiro); o plano de empresa única Bora + operador TVDE colide com os arts. 12.5 e 20.11; avaliar o passageiro passou a ser OBRIGATÓRIO (19.2 c), por isso tvde_driver_rates_client_disabled nunca se liga; 5 corridas passaram o teto de 25 por cento (balcão, ida-e-volta incompleta, paragens). Relatório completo: .claude/.ai/reports/tvde-conformidade-2026-09-30.md, commit 75143a93.
