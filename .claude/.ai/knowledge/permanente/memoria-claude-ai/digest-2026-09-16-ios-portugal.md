---
id: memoria-claude-ai-digest-2026-09-16-ios-portugal
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-16
zona: verde
confianca: alta
estado: atual
---

# Claude Code Opus 16/09 — Bora fora da App Store de Portugal: verificação de comerciante reprovada, causa provada, caso aberto na Apple, vigia na VPS

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-16-ios-portugal`, origem `claude-code`, atualizada em 2026-09-16T17:02:57.882159+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 16 ios portugal · memoria claude.ai · claude_ai_memoria

O QUE SE SABE AGORA (medido 16/09). A Bora está aprovada e no ar só no Brasil. Em Portugal e nos outros 26 países da UE a API diz TRADER_STATUS_VERIFICATION_FAILED + CANNOT_SELL (a 13/09 era NOT_PROVIDED): o email da Apple de 13/09 22:12 UTC foi uma REPROVAÇÃO da verificação de comerciante, não uma confirmação; o reenvio de 13/09 22:33 está "Em revisão", trancado, sem botão. CAUSA, provada por ficheiros + registo de diálogos do Windows + emails: a 08/09 a prova de nome e morada foi um extracto bancário em que o banco escreve o nome sem o "da" e o formulário não tinha o andar (o título de residência, enviado como identificação para a verificação manual do telefone, tem tudo certo); o reenvio de 13/09 corrigiu o andar mas não levou documento novo; o telefone foi por verificação manual embora receba SMS; a conta não tem banco nem formulário fiscal (a página da Apple exige a todos os comerciantes, art. 30(1)(c) do DSA); a inscrição do programa tem 6300-035 e o certo é 6300-610. O "141 andar" do email era "14" + "1 andar" colados — o número não estava errado. O reset da palavra-passe de 13/09 saiu deste PC (perfil Bora do Chrome), não é intrusão. FEITO: Certidão de Domicílio Fiscal da AT emitida hoje (bilingue, nome completo e morada iguais ao formulário) — só na pasta privada C:\Users\danil\_PRIVADO\apple-dsa-2026-09-16 (repo é público). Caso escrito aberto na Apple Developer Support: Case ID 102965371739 (16/09 16:47 UTC, email automático 16:48) a pedir o motivo exacto, link seguro para o documento, telefone por SMS, correcção do código postal da inscrição e se os dados de pagamento são obrigatórios; o formulário de contacto não aceita anexos. Vigia na VPS (/opt/data/scripts/vigia-apple-pt.sh, cron 7 * * * *) grita no Telegram quando o lookup de PT der 1 e desliga-se sozinho; não lê o Gmail. Contas demo provadas (login 200 x3, pedido em rollback). ios/REGRAS-APPLE-PORTUGAL.md escrito; bloco -18 no ESTADO; skill nova apple-conta-e-loja; CONTINUAR em .claude/.ai/inbox/CONTINUAR-ios-portugal-2026-09-16.md. PENDENTE DO DANILO: clicar Guardar no questionário de impostos dos EUA (Não/Não já marcado, aberto no Chrome do Bora) e colar o IBAN na conta bancária (o agente preenche o resto). PROIBIDO em qualquer motor: declarar não-comerciante, tirar a app de venda, mexer no Brasil, versão nova, reenviar às cegas, mudar senha/email, pagar. Para a próxima build: ios_hide_nonpartner_logos está a false (logos de terceiros no iPhone, risco 5.2) e as perguntas etárias de redes sociais são obrigatórias desde set/2026. Relatório: .claude/.ai/reports/OPUS-2026-09-16-ios-portugal.md (cópia no vault prompts); e2e_log fluxo ios-portugal-2026-09-16 ids 1829–1867.
