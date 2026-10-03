# OPUS — 16/09/2026 — Bora na App Store de Portugal (missão `ios-portugal-2026-09-16`)
> Motor Opus 5 · porta Claude Code + Chrome do PC · sessão `ios-portugal-16-09` · e2e_log fluxo `ios-portugal-2026-09-16` (ids 1829–1867).
> Sem dados pessoais neste ficheiro (repo público). Documentos, capturas e números: só em `C:\Users\danil\_PRIVADO\apple-dsa-2026-09-16\`.

## RESUMO PARA O DANILO

Danilo, a Bora não está em Portugal porque a Apple recusou a verificação dos teus dados de comerciante no dia 13 à noite — aquele e-mail não era confirmação, era reprovação, e a API já mostra "verificação falhou" em todos os países da União Europeia. Eu fui ver o que foi enviado no dia 8: o documento de morada foi um extrato do banco que escreve o teu nome sem o "da" e o formulário não tinha o "1.º andar", enquanto o teu título de residência tem o nome e a morada certos; no dia 13 o formulário ganhou o andar, mas não foi documento novo, o telefone foi por verificação manual e a conta não tem banco nem formulário fiscal, que a Apple exige a todo comerciante. Hoje tirei a certidão de domicílio fiscal nas Finanças (obrigado por entrar), em dois idiomas e com o teu nome completo e a morada exatamente como no formulário, e abri um caso por escrito no suporte da Apple, número 102965371739, a pedir o motivo exato, um link seguro para mandar o documento, a verificação do telefone por SMS e a correção do código postal da inscrição. Deixei um vigia na VPS que olha a loja de hora em hora e te avisa no Telegram no minuto em que a Bora aparecer em Portugal. Falta de ti só duas coisas, quando puderes: clicar em Guardar no questionário de impostos que está aberto no Chrome do Bora e colar o IBAN na conta bancária. A senha reposta no dia 13 foi feita deste PC, não é invasão. Quando a Apple responder, o Claude segue o guião que deixei escrito.

## Acessos usados nesta sessão
- App Store Connect e developer.apple.com: sessão já aberta no Chrome do PC (perfil Bora, conta `boraappbora@gmail.com`).
- Portal das Finanças: sessão aberta pelo Danilo no perfil pessoal do Chrome (regra LOGIN NO NAVEGADOR).
- Gmail `boraappbora@gmail.com` (MCP), Supabase (MCP), VPS por SSH (chave do PC).
- Criado nesta sessão: caso Apple **102965371739**; script `/opt/data/scripts/vigia-apple-pt.sh` + cron na VPS; certidão da AT (privada); pasta `C:\Users\danil\_PRIVADO\apple-dsa-2026-09-16\`.

## O que NÃO foi feito
- O Danilo ainda não clicou em Guardar no questionário fiscal nem colou o IBAN (Bloco 5 ficou aberto; passos no CONTINUAR).
- O formulário de comerciante não foi reenviado (está trancado "Em revisão"; a correcção vai pelo caso escrito) — e é o certo.
- Bloco 8 (Portugal aberto) não aconteceu: continua fechado.
- O vigia da VPS não lê o Gmail (não há ferramenta lá); os emails da Apple lêem-se nas sessões do Claude Code.
- `account.apple.com` (dispositivos) não foi aberto: exige senha + 2FA; a origem da reposição foi provada por outro caminho.
- Comprovativo de início de actividade da AT não encontrado no menu (opcional).

## Tradução do que a Apple escreveu (texto corrido)
E-mail de 8 de setembro, 20:57 UTC, "Recebemos os seus dados de contacto de comerciante": obrigado por fornecer os dados de contacto de comerciante para o Regulamento dos Serviços Digitais; vamos verificar a informação e voltamos ao contacto em breve; seguem nome, telefone, e-mail e morada tal como foram enviados, sem número DUNS.

E-mail de 13 de setembro, 22:12 UTC, "Ação necessária: atualize os seus dados de contacto de comerciante no App Store Connect": não conseguimos verificar os seus dados de contacto de comerciante para o cumprimento do Regulamento dos Serviços Digitais; por favor volte a enviar dados de contacto válidos o mais depressa possível, para que a sua app continue disponível na União Europeia. Sem motivo, sem pedido de documento, sem link.

E-mail de 13 de setembro, 22:33 UTC: o mesmo texto do primeiro "recebemos", agora com a morada em duas linhas (número 14 e "1 andar").

E-mail de 16 de setembro, 16:48 UTC, "Obrigado por enviar o seu pedido de suporte": recebemos o seu pedido de suporte e responderemos o mais depressa possível; o número do seu caso é 102965371739; Apple Developer Program Support.

Página oficial da Apple (DSA): os comerciantes individuais dão morada, telefone e e-mail; todos os comerciantes dão os dados da conta de pagamento se ainda não estiverem no App Store Connect e certificam que só oferecem produtos e serviços conformes com a lei da UE; o e-mail e o telefone validam-se por código (verificação manual só se o número não receber códigos); é preciso carregar um documento atual que prove o nome e a morada do negócio (registos comerciais ou legais); no fim revê-se e confirma-se.

## Tradução do que foi enviado à Apple (caso 102965371739)
Assunto: a verificação de comerciante do DSA falhou — peço o motivo exacto, um sítio seguro para enviar o documento, a verificação do telefone por SMS e a correcção do código postal da inscrição. Corpo: apresento-me como programador individual com a equipa e a app identificadas; digo que a app foi aprovada a 12 de setembro e está no ar no Brasil, mas que nos 27 países da UE, incluindo Portugal, a disponibilidade diz "não é possível vender" e a API devolve "verificação de comerciante falhou"; conto a cronologia dos três e-mails; explico o que acho que correu mal (o extrato bancário com o nome sem "da" e sem o andar no primeiro envio, o telefone por verificação manual, o código postal errado na inscrição); digo que tenho uma certidão da Autoridade Tributária emitida hoje, bilingue e com código de validação, com o nome completo e o domicílio fiscal exactamente iguais aos dados de comerciante, mais o título de residência; afirmo que sou comerciante e não quero mudar o estatuto; e peço quatro coisas: o item exacto que falhou, juntar o documento ou um link seguro (e o telefone por SMS), corrigir o código postal da inscrição, e confirmar se os dados de pagamento são obrigatórios. Texto integral em `.claude/.ai/provas/ios-portugal-2026-09-16/mensagem-suporte-apple.md`.

## Bloco a bloco, com a prova

**Bloco 0.** Plano no e2e_log (id 1829). RAM 846 MB (portão leve 400). Outras janelas: fluxos activos de outras pastas; sem lock no repo. Prompt copiado para `Desktop\Bora\prompts\PROMPT_IOS_PORTUGAL_2026-09-16.md`. Pasta privada criada.

**Bloco 1 — retrato medido (ids 1831–1839).** Lookup 12:32 UTC: pt 0, br 1, es/fr/us/de/it 0; página PT 404, BR 200. API `appAvailabilityV2`: BRA `AVAILABLE`; PRT `available=true` + `TRADER_STATUS_VERIFICATION_FAILED + CANNOT_SELL`; 26 UE iguais; 146 fora da UE `CANNOT_SELL`. Versão 1.0 `READY_FOR_SALE`/`READY_FOR_DISTRIBUTION`, `releaseType MANUAL`, `USES_THIRD_PARTY_CONTENT`, 12+, só pt-PT, URLs de privacidade/suporte/marketing todas 200. Negócios: apps pagas "Informações do utilizador pendentes", sem conta bancária, formulário fiscal dos EUA em falta, DSA "Em revisão" 13/09 sem botão. App: "identificou-se como comerciante" (o Editar só troca comerciante/não comerciante — cancelado). Preço e disponibilidade: Disponível 1 / Não é possível vender 1 / Não disponível 173. Inscrição: código postal 6300-035, programa activo até 09/2027, renovação automática desligada, acordos aceites. Gmail: 23 threads da Apple desde 07/09, nenhuma nova depois de 13/09 22:33 até ao caso de hoje. Segurança: a reposição da palavra-passe de 13/09 saiu do perfil Bora do Chrome deste PC (histórico: falha de login 05:44, logout, código por e-mail 05:49, reposta 05:51, de volta 05:54); Claude Code estava rejeitado pelo limite semanal nessa hora.

**Bloco 2 — causa (ids 1849–1852).** Ficheiros de 08/09 nas Transferências (duas fotos do título de residência 20:53 UTC, extrato bancário PDF 20:56 UTC, e-mail "recebemos" 20:57) + registo de diálogos de ficheiro do Windows (últimos usos 08/09 20:53 e 20:56; nada a 13/09). Veredictos: documento — inconsistência confirmada (nome sem "da"; formulário sem andar); dados de pagamento — lacuna real, causa por provar; código postal — por provar; telefone manual — plausível; fila — descartada como causa; idioma do documento "Português (Brasil)" — nova pista. Art. 30 do DSA lido no EUR-Lex; 12 tópicos do fórum lidos.

**Bloco 4 — correcção preparada (ids 1854–1858).** Certidão de Domicílio Fiscal emitida e obtida (PDF 128 907 bytes, bilingue, hash no e2e_log) — privada. Morada do reenvio de 13/09 = certidão = título de residência; nome igual à inscrição. Conta bancária: diálogo de 3 passos explorado (país → titular → IBAN), cancelado sem gravar; questionário fiscal dos EUA = 2 perguntas (Não/Não) e Guardar, deixado aberto. Telefone: fica para o caso (formulário trancado). Mensagem ao suporte escrita em inglês + tradução.

**Bloco 5 — sentada (id 1859).** Telegram 17:32 com o passo 1 (Guardar no questionário); o Danilo entrou no Portal das Finanças por si; até ao fecho não clicou. Não se esperou.

**Bloco 6 — caso escrito (ids 1860, 1861, 1864).** Formulário trancado → sem reenvio. Caso enviado por `developer.apple.com/contact` → App Setup → Availability and Pricing → Email: **Case ID 102965371739**; e-mail automático recebido 16:48 UTC. O formulário não aceita anexos: a certidão segue quando a Apple mandar o link seguro.

**Bloco 3 — regras cruzadas (ids 1862, 1863).** `ios/REGRAS-APPLE-PORTUGAL.md` escrito: o que trava PT, o que tira a app da UE, o que morde na próxima versão (logos de terceiros de volta — `ios_hide_nonpartner_logos=false` medido; 20 apps "Bora" no BR / 11 em PT; denunciar e bloquear presentes na build 115; apagar conta; TVDE/farmácia; perguntas etárias novas obrigatórias desde setembro/2026; Xcode 26; só pt-PT). Contas demo provadas: login 200 ×3 (client/driver/partner, logout `scope=local`), pedido em rollback como cliente demo (1 linha, `driverAccepted` pela caixa fechada, taxa de pedido pequeno 1,39, 0 sobras).

**Bloco 7 — vigia (ids 1865, 1866).** `/opt/data/scripts/vigia-apple-pt.sh` na VPS, cron `7 * * * *`, teste às 16:56 UTC lido de volta no log do Telegram; desliga-se sozinho ao avisar. CONTINUAR escrito em `.claude/.ai/inbox/CONTINUAR-ios-portugal-2026-09-16.md`.

**Bloco 8.** Não correu (Portugal fechado). Fica no CONTINUAR.

## Achado de passagem — NIF já estava no repo público
A varredura antes do commit apanhou o NIF em `ios/LANCAMENTO-IOS-ESTADO.md` (linha antiga da 1.ª sessão, commit `172a2734`), e ele existe também em `ios/CHECKLIST-APPLE.md` e `ios/NOTAS-AO-REVISOR.md`. Retirei-o do ESTADO nesta missão; os outros dois ficheiros não foram tocados (o NIF está publicado nas páginas legais do site por opção do Danilo, mas a regra da casa é não o ter no repo — fica como pendência para uma limpeza à parte, que exige decidir se as notas ao revisor precisam dele).

## ⚠️ Dinheiro / zonas protegidas
Nada aplicado. Nenhuma zona protegida tocada; `platform_settings` só lido. A prova em rollback não deixou linhas.

## Proposta para o painel admin (não construído nesta missão)
Cartão "Loja iOS" no painel com: lookup PT/BR de hora a hora (o vigia já mede), estado do DSA lido dos e-mails, e um aviso quando `ios_hide_nonpartner_logos` estiver a `false` antes de uma submissão. Proposta só; sem feature nesta missão.

## PARA O DANILO (só o que só tu podes fazer)
1. No Chrome do Bora está aberto o "Questionário de impostos dos EUA" com Não/Não marcado: clica em **Guardar**.
2. Depois, na mesma página (Negócios), a conta bancária: eu preencho o titular e a morada, tu colas o **IBAN** e clicas Guardar. Diz-me quando quiseres e faço na hora.
3. Quando a Apple responder ao caso 102965371739 (e-mail ao boraappbora), o Claude segue o CONTINUAR; se pedirem o documento, ele já está pronto.
