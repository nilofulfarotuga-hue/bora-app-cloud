# CONTINUAR — ios-portugal-2026-09-16 (Bora na App Store de Portugal)
> Escrito a 16/09/2026 ~18:00 Lisboa. Ponto exacto onde a missão ficou e o que fazer a cada resposta da Apple.
> Sem dados pessoais aqui. Documentos e capturas: `C:\Users\danil\_PRIVADO\apple-dsa-2026-09-16\` (fora do repo).

## Onde ficou
- App aprovada (12/09), no ar só no Brasil. Portugal e os outros 26 da UE: `TRADER_STATUS_VERIFICATION_FAILED + CANNOT_SELL` (API, 16/09).
- Formulário de comerciante: submetido 08/09, **reprovado 13/09 22:12 UTC**, reenviado 13/09 22:33, "Em revisão" trancado (sem botão).
- Causa provada (e2e_log 1849–1852): o documento de morada de 08/09 (extracto bancário) tinha o nome **sem o "da"** e o formulário não tinha o andar; o reenvio corrigiu o andar mas não levou documento novo; telefone por verificação manual; sem dados de pagamento; código postal da inscrição 6300-035 ≠ 6300-610.
- Documento certo já existe: **Certidão de Domicílio Fiscal da AT, 16/09/2026, bilingue**, nome completo + morada iguais ao formulário (pasta privada, md5 `063ECB0C1FE52F3E0E3B7334F4A82FD0`).
- **Caso escrito aberto na Apple: Case ID 102965371739** (16/09 16:47 UTC; email automático recebido 16:48 UTC). Texto em `.claude/.ai/provas/ios-portugal-2026-09-16/mensagem-suporte-apple.md`.
- Vigia na VPS: `/opt/data/scripts/vigia-apple-pt.sh`, cron `7 * * * *` (root), grita no Telegram quando `lookup?country=pt` der 1 e desliga-se sozinho (`/opt/data/vigia-apple-pt.done`). Log: `/opt/data/vigia-apple-pt.log`. **Não lê o Gmail** (a VPS não tem ferramenta de email): os emails da Apple lêem-se com o Gmail MCP (`boraappbora@gmail.com`) em sessão do Claude Code.
- Pendente do Danilo (sentada, ver Telegram de 17:32): (1) clicar **Guardar** no "Questionário de impostos dos EUA" (Não/Não já marcado, App Store Connect → Negócios, Chrome perfil Bora); (2) conta bancária: o agente preenche titular/morada (Particular, Portugal, morada dos documentos) e ele cola o IBAN e clica Guardar. Ambos opcionais para a verificação mas pedidos pela página da Apple ("all traders") e pelo art. 30(1)(c).

## O que fazer quando a Apple responder (ler o email POR INTEIRO antes de decidir)
1. **Pede documento / manda link seguro** → carregar a certidão da AT (pasta privada) e, se pedirem identificação, a frente e o verso do título de residência (mesma pasta). Nome e morada no formulário têm de ficar **letra a letra** como na certidão: "Danilo Fulfaro da Silva" · "Rua do Torreão 14" · "1 andar" · Guarda · 6300-610 · Portugal. Telefone: **código SMS**, nunca verificação manual. Responder ao caso com "documento enviado" (sem números no repo).
2. **Reprovada outra vez** ("we weren't able to verify…") → NÃO reenviar às cegas. Responder no caso 102965371739 a pedir o motivo exacto (item a item) e o link seguro; só depois reenviar UMA vez com o documento novo e os dados iguais à certidão. Registar no e2e_log (`fluxo ios-portugal-2026-09-16`, passo `apple-resposta-<data>`).
3. **Diz que faltam dados de pagamento** → fazer a sentada: questionário fiscal (Guardar) + conta bancária (IBAN colado pelo Danilo) e responder ao caso.
4. **Verificada / Portugal abriu** (vigia grita, ou email "trader contact information verified") → Bloco 8: provar `lookup?country=pt` = 1 e página 200; confirmar na página da app os dados de comerciante e o texto pt-PT; `/baixar` do bora-site: o botão do iPhone tem de abrir em Portugal (link sem país `https://apps.apple.com/app/id6809954739`) — mudar só se for preciso e publicar com `deploy-cloudflare.sh`, provar HTTP 200; Telegram ao Danilo com o link; bloco -19 em `ios/LANCAMENTO-IOS-ESTADO.md`; digest.
5. **Pede para corrigir a morada da inscrição** → é a Apple que corrige (6300-035 → 6300-610); confirmar depois com `getTeams` (developer.apple.com, sessão do Chrome).
6. **Silêncio > 7 dias úteis** → responder no mesmo caso (não abrir outro) a pedir ponto de situação; o fórum mostra revisões de 2–4 semanas.

## Regras que não se quebram nesta continuação
- Nunca declarar "não comerciante"; nunca tirar a app de venda, mexer no Brasil, criar versão nova ou reenviar a app para revisão.
- Nunca mudar senha/email/dispositivos da Conta Apple; nunca pagar.
- Nunca escrever IBAN/NIF/números de documentos: são do Danilo; e nunca os pôr no repo, no vault ou no Córtex.
- Antes de qualquer build nova para a UE: `ios_hide_nonpartner_logos` a `true` (hoje `false`) e as perguntas novas de classificação etária respondidas (ver `ios/REGRAS-APPLE-PORTUGAL.md` parte iii).
