---
id: memoria-claude-ai-digest-2026-09-13-janela-1
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-13
zona: verde
confianca: alta
estado: atual
---

# Janela 1 FABLE 13/09 — resultado

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-13-janela-1`, origem `claude-code`, atualizada em 2026-09-13T21:00:32.70879+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 13 janela 1 · memoria claude.ai · claude_ai_memoria

Estado às 22:00 (a janela ainda está a correr o autoteste; versão final segue no fecho). Feito com prova: 17 migrações de produção de 09 a 13/09 espelhadas no repo com timestamp e SQL iguais (md5 23/23). Auditoria das migrações do ChatGPT de 12/09: CHECK dos 10 estados confirmado; auto-dispatch de parceiro e order_status_events a funcionar; dois bugs reais apanhados e corrigidos em produção — a cliente com crédito de 5 € não conseguia pedir corrida (FK do crédito), e nenhum pedido das contas demo nascia desde 12/09 (guarda nova exigia driver_id). Crédito promocional passa a ser descontado no fecho da corrida e devolvido em qualquer cancelamento. Talão do não-parceiro: uma só função no servidor (finalizar_talao_nao_parceiro) fecha talão, totais, acerto do estafeta e estado; o Flutter deixou de escrever colunas financeiras e mostra o erro real em PT-PT; admin corrige o valor com motivo e auditoria; provado com pedido real de teste em dinheiro (36e6812a: onTheWay, entregue, tokens, ganhos, ledger) e cartão/MB Way em rollback. Vina Cá: plano antigo cancelado; os +2 € eram 1 €/km acima dos 10 km do plano; agora 5,00 € fixos até 15 km só para ela, motorista ganha o normal (provado em rollback com os dois JWT). Site /baixar publicado por wrangler com botão da App Store no iPhone e QR das duas lojas; App Store aberta no Brasil, Portugal fechado até o Danilo declarar o estatuto de comerciante (DSA) na App Store Connect; renovação Apple manual em 09/2027. Skill protocolo-missao-bora criada e ligada; PADRAO_BORA auditado contra as 4 regras de 10/09. Erro meu apanhado antes do push: o merge de produção tinha partido da produção antiga e deixava de fora o PR do Codex de 12/09 — corrigido com merge de origin/autonomous por cima (24e5a737); portão do CI corrigido (o tee escondia o exit do drive). Em curso: autoteste dos 3 perfis no emulador local (Java 25 e Flutter 3.47 do PC atrasaram: JDK 17 portátil + NDK instalado à mão) e depois o push a autonomous-night-2026-04-29 (CI faz o bump para 604). Provas: e2e_log fluxo fable-13-09 (1688 a 1721), relatório .claude/.ai/reports/FABLE-2026-09-13.md.
