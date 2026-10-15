---
id: memoria-claude-ai-digest-2026-10-15-tvde-pedir-nunca-trava
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-15
zona: verde
confianca: alta
estado: atual
---

# Claude Code 14-15/10 — pedir corrida nunca trava (caso Stela)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-15-tvde-pedir-nunca-trava`, origem `claude-code`, atualizada em 2026-10-15T06:01:24.232574+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 15 tvde pedir nunca trava · memoria claude.ai · claude_ai_memoria

Caso: a Stela escreveu a morada no Bora Motorista, nao tocou em sugestao, botao ficou cinzento mudo (tvde_calculate_fare nunca chamado). Feito no commit local 6da59368 (ramo autonomous-night, SEM push a pedido do Danilo). O que funciona no codigo agora: (A) o campo de morada partilhado (AddressAutocompleteField) aceita a morada escrita ao sair do campo/Enter/botao: geocode tolerante com caixa da Guarda e mostra "No mapa: ..." para confirmar; sem coordenadas diz no campo, nunca em silencio. Desligado so na folha de paragens da corrida e na pesquisa da home (la escolher faz mais que guardar). (B) pesquisa tolerante: Av.->Avenida, sem n de porta/andar; recusa cidade inteira, rua de outra cidade quando se escreveu Guarda, e resultados sem palavra do texto. (C) atalhos Casa + 3 destinos recentes por baixo da recolha e do destino. (D) botao diz o que falta (Escolhe o ponto de recolha / Escolhe o destino / A calcular o preco / A procurar a tua localizacao) e leva ao campo; tambem em Chamar a volta e Mudar destino da reserva. (E) timeouts GPS 5/30 s, morada inversa 8 s, rota 10 s; GPS negado -> "Liga a localizacao ou escreve a morada". (F) app grava pedido_travado em web_health_events; Saude da Web desarquivada (Operacao do dia) com nome/telefone/Ligar. Provas: 1238/1238 testes; +32 casos (mutacao poe-nos vermelhos); prova web real (build + conta demo + GPS recusado): Safed escrita a mao aceite, preco EUR5.00, folha de pagamento em dinheiro aberta e NAO confirmada, 0 corridas criadas. FALTA (espera o sim do Danilo): 1) aplicar a migracao 20261014190000_pedido_travado_saude_web.sql (sem ela o banco recusa pedido_travado com 400 e nao ha alarme nem nomes; a aplicacao foi recusada na sessao); 2) git push (publica Play/Apple/web) e provar as 3; 3) corrida real de teste nao foi criada (2 motoristas reais ligados, TVDE sem guarda demo); 4) Android no emulador falhou por RAM (ANR com 470 MB livres). Depois de publicar, a Stela tem de atualizar a app. Relatorio: .claude/.ai/reports/tvde-pedir-nunca-trava-2026-10-14.md. e2e_log fluxo tvde-pedir-nunca-trava-2026-10-14 (ids 3607-3618).
