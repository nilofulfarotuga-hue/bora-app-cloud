---
id: memoria-claude-ai-digest-2026-09-16-claude-ai-ios-portugal
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-17
zona: verde
confianca: alta
estado: atual
---

# Claude.ai 16/09 — Bora fora da App Store de Portugal: a verificação de comerciante FALHOU a 13/09; prompt ios-portugal entregue

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-16-claude-ai-ios-portugal`, origem `claude-ai`, atualizada em 2026-09-17T11:03:41.490388+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 16 claude ai ios portugal · memoria claude.ai · claude_ai_memoria

Conversa da Claude.ai a 16/09. O Danilo diz que há mais de uma semana tenta lançar a Bora no iPhone em Portugal e não consegue; acha que pôs algum dado errado; pediu ao Claude Code uma investigação a fundo, com leitura de todas as regras da Apple e prova da causa.
APURADO (Gmail + e2e_log + ios/LANCAMENTO-IOS-ESTADO.md): a Apple aprovou a Bora a 12/09 11:23 UTC e ela está no ar só no Brasil desde 12/09. Portugal fechado por TRADER_STATUS_NOT_PROVIDED (estado de comerciante DSA por verificar).
CORRIGE OS DIGESTS DE 13/09: o email da Apple de 13/09 22:12 UTC (23:12 Lisboa) não foi confirmação, foi REPROVAÇÃO — a Apple não conseguiu verificar os dados de comerciante e pediu reenvio. O reenvio de 13/09 22:33 UTC (Danilo com o ChatGPT) levou os mesmos dados de 08/09 (nome, telefone, email boraappbora, R. do Torreão 14, 6300-610), só com 1 andar a mais — o email mostra 141 andar colado, a confirmar se ficou número errado. Sem resposta da Apple até 16/09.
PISTAS A PROVAR: documento da verificação manual pode não provar nome e morada; a página oficial da Apple exige dados de pagamento a todos os comerciantes e a conta não tem conta bancária nem formulário fiscal (acordo de apps pagas pendente); a inscrição do programa tem o código postal 6300-035 errado; telefone só por verificação manual.
POR CONFIRMAR: quem repôs a palavra-passe da Conta Apple a 13/09 05:51 UTC. RISCO: logos de terceiros voltaram ao iPhone a 13/09, depois da aprovação.
PRIVACIDADE: o repo bora-app-cloud é PÚBLICO e .claude/.ai/provas e reports vão para o GitHub — documentos pessoais e IBAN nunca lá.
ENTREGUE: PROMPT_IOS_PORTUGAL_2026-09-16.md, motor OPUS, porta Claude Code com Chrome, SESSÃO NOVA pasta bora-app-cloud, run_id ios-portugal-2026-09-16. Blocos: retrato medido, causa com todas as hipóteses, leitura completa das regras, correção preparada, uma sentada do Danilo, reenvio só com erro provado mais caso escrito ao suporte da Apple, vigia até Portugal abrir, fecho com skill apple-conta-e-loja. Nada disparado pela Claude.ai.

ATUALIZAÇÃO 16/09 ao fim da tarde (Claude.ai verificou o relatório do Claude Code no e2e_log 1829-1868 e no Gmail): confirmado. Causa da reprovação: a 08/09 foi o extrato do Millennium com o nome sem "da" e o formulário sem o 1.º andar; o reenvio de 13/09 corrigiu o andar mas usou o mesmo extrato; e a Apple não tem conta bancária nem questionário fiscal. A API mostra PRT com TRADER_STATUS_VERIFICATION_FAILED e o formulário de comerciante está trancado em revisão. Feito: certidão de domicílio fiscal da AT (só na pasta privada do PC); caso escrito na Apple 102965371739 com email automático recebido; vigia de hora a hora na VPS que avisa no Telegram quando a Bora aparecer em Portugal; senha de 13/09 reposta do próprio PC, sem invasão. PENDENTE DO DANILO: confirmar o questionário de impostos dos EUA (Não/Não) e colar o IBAN na conta bancária da App Store Connect. A Claude.ai prepara as duas páginas no Chrome quando ele estiver no PC — ele NÃO deve preencher o banco sozinho: o formulário vem com país EUA por defeito e a caixa "Igual à entidade jurídica" copia o código postal errado 6300-035. NIF nos ficheiros do repo: já é público no site, sem ação. Agora espera-se a resposta da Apple ao caso.

ATUALIZAÇÃO 16/09 18:40 Lisboa (Danilo no PC, guiado pela Claude.ai por fotos): questionário de impostos dos EUA guardado (Não/Não); conta bancária do Millennium BCP adicionada na App Store Connect, estado "A processar" (até 24 h). Para Portugal a Apple aceitou o IBAN + número da conta de 11 dígitos. O W-8BEN apareceu com a nacionalidade TRAVADA em Portugal (ele é brasileiro) e a morada com 6300-035 — decisão: NÃO enviar por agora (seria certificar dado falso; só serve para receber vendas nos EUA e a app é grátis; o que o DSA pede é a conta de pagamento, que já entrou). Tratar a nacionalidade com a Apple se o caso 102965371739 disser que o formulário fiscal é obrigatório. A extensão Claude in Chrome é bloqueada pelo Chrome no site appstoreconnect.apple.com — trabalho nesse site só pelo executor do Claude Code ou pelo Danilo com fotos.

ATUALIZAÇÃO 17/09 (Claude.ai): o Danilo perguntou, chateado, porque ainda não chegou nada da Apple (foto do App Store Connect com iOS 1.0 "Pronta para distribuição"). Verificado agora: Gmail boraappbora sem nada da Apple depois do email automático do caso 102965371739 (16/09 16:48 UTC), spam incluído; e2e_log sem linhas de iOS depois de 16/09 17:05 UTC. Estado igual: aprovada e à venda só no Brasil; UE fechada à espera da verificação de comerciante e da resposta humana ao caso. Explicado ao Danilo em texto simples. LACUNA: o vigia da VPS só lê a loja (lookup PT), não lê o Gmail — se a Apple responder a pedir o documento por link seguro, ninguém é avisado na hora. Oferecido um vigia de Gmail com aviso no Telegram; nada disparado.
