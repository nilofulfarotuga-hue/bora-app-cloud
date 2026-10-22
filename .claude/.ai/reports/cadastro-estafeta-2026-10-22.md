# Cadastro do estafeta — fotos e ecrã de aprovação (22/10/2026)

> Missão `cadastro-estafeta-fotos-22-10` · run_id `cadastro-estafeta-2026-10-22`
> Motor: Opus 5.5 · Porta: Claude Code no PC do Danilo · Autorização do Danilo (22/10, 16:55):
> "tem que aparecer tudo pra mim, tudo que é pra ele tirar foto tem que aparecer".
> Não se mexeu em preços, comissões, ganhos, carteira, Stripe nem dispatch.

## Acessos usados
- Supabase por MCP (leitura, e2e_log, deploy da Edge `upload-driver-document`).
- GitHub pelo `gh` do PC (envio para `autonomous-night-2026-04-29`, vigia dos builds).
- Site app.boraguarda.com num Chromium de prova (Playwright), com 2 contas de TESTE criadas e
  encerradas nesta missão. Conta demo `demo-estafeta@bora.app` só para a prova da Edge.
- Chave do servidor do `backend/.env` do PC, só para assinar 10 minutos a imagem do comprovativo
  do SAM na captura privada (nunca escrita nem impressa).

## O que NÃO foi feito (e porquê)
1. **Função própria no servidor para o reenvio de fotos (bloco C) — recusada pela tranca.** A
   bora-tranca proíbe por código qualquer migração com escrita na tabela de estafetas. Não
   contornei. O reenvio usa a função que já existia (`driver_register_or_update`, a do próprio
   cadastro), que só preenche o que recebe. Funciona e está provado no site. A proposta da função
   dedicada (mais apertada: confirma que a foto é mesmo da pessoa) ficou guardada, **não aplicada**:
   `.claude/.ai/provas/cadastro-estafeta-2026-10-22/proposta_rpc_documentos_estafeta_NAO_APLICADA.sql`.
2. **Prova no emulador Android do PC — não feita.** O PC tinha entre 746 e 1352 MB livres; o
   emulador precisa de 3 GB. A prova Android é a do CI (autoteste dos 3 perfis no emulador com
   Play Store) + o build publicado. Toda a prova de ecrã foi feita no site real.
3. **SMS automático — não existe caminho.** O botão "Pedir documentos em falta" manda aviso na app
   + notificação. Quando o estafeta não tem notificações ligadas, o painel oferece abrir o SMS já
   escrito no telemóvel do Danilo (não é envio automático).
4. **Captura do SAM com sessão de admin — não havia sessão de admin no navegador de prova.** A
   captura usa o ecrã real do site com as linhas reais do SAM injetadas (padrão já usado neste
   projeto). Fica só na pasta privada do PC (dados pessoais), fora do git:
   `C:\Users\danil\Documents\Bora-provas-privadas\cadastro-estafeta-2026-10-22\`.

## Bloco a bloco, com prova

**Causa (confirmada):** o cadastro mandava o tipo da foto tirado do nome (`image/jpg`), o armazém
recusava, e a app engolia o erro — candidaturas chegavam sem fotos. Mais um defeito encontrado: o
servidor recusava sempre o "documento do veículo" (carta/livrete) — **nunca nenhum chegou**.

**D — Servidor (`upload-driver-document` v4, verify_jwt mantido em true)** — commit `db0a21dd`.
O tipo passa a ser lido dos primeiros bytes e sai sempre como `image/jpeg`; aceita `vehicle_doc`;
HEIC recebe uma resposta clara. Prova real (conta demo): `image/jpg` → 200, `vehicle_doc` → 200
(antes 400), HEIC → 415. Ficheiros no armazém com `image/jpeg` (`prova_edge_v4.json`).
A migração de 22/10 que abriu o `image/jpg` nos baldes ficou também no repo (`20261022155725`).

**B — Cadastro (`driver_signup_screen.dart`)** — commit `fabd0de4`.
Tipo da foto pelos bytes; HEIC do iPhone convertido para JPEG no telemóvel; cada foto tenta 3
vezes; se falhar, a candidatura **não** é enviada e o estafeta lê "Não conseguimos enviar a foto do
documento. Tenta outra vez." (a falha fica no e2e_log). **Selfie e foto do documento passam a
obrigatórias** (antes estava tudo "opcional").
Prova no site real: cadastro de teste com 4 fotos .jpg → 4 envios 200 → as 4 colunas preenchidas
e 4 ficheiros `image/jpeg` no armazém (incluindo o livrete). Tentar enviar sem a foto do documento
→ "Falta: foto do documento." e volta ao passo das fotos. Capturas `web/12-fotos.png`,
`web/31-falta-documento.png`.

**A — Ecrã de aprovação no painel (`admin_driver_approval_screen.dart`)** — commits `8c7d51ab`,
`1702a55e`. Mostra tudo o que o cadastro pede, por secções: selfie, nome e nome legal, telefone,
e-mail, nascimento com idade, morada, tipo/número/foto do documento, NIF, atividade aberta,
**comprovativo de atividade** (miniatura ou PDF, com "Aprovar comprovativo" ali mesmo), veículo em
português (Mota, Bicicleta, Carro, Carro de passageiros), matrícula, marca, cor, foto do veículo,
livrete, IBAN, MB Way, forma de receber, modo de trabalho, autocertificação DSA, termos, data da
candidatura. Cada foto abre em ecrã inteiro com zoom. Tudo o que falta aparece a vermelho
("Falta: …") na lista e na ficha. Botão **"Pedir documentos em falta"** com a frase exata que o
estafeta recebe. Contas encerradas deixam de aparecer em "Pendentes".
Prova no site real: `web/61-ficha-1.png`, `62-ficha-2.png`, `64-ficha-4.png`, `65-ampliada.png`,
`71-ficha-falta.png`, `72-dialogo-pedir.png`. Conta sem papel de admin → o servidor recusa o pedido
(403); como admin, em ensaio desfeito, `ok:true` e 1 notificação posta na fila.

**C — "Conta em análise" do estafeta** — commit `037c282d`. Lista vermelha "Falta enviar" com um
botão por item: "Enviar foto", "Escrever" (número do documento, matrícula) e "Enviar" (comprovativo).
Prova no site real (`web/42-…png`, `43-…png`): enviou a foto do veículo e a matrícula ali mesmo; a
base confirma, sem mexer em nome, telefone, veículo ou estado da candidatura.

**E — O mesmo defeito noutros sítios (só relatório, não corrigido)**
- `lib/screens/register_partner_screen.dart:420, 448, 476, 503` — cadastro de parceiro manda
  `image/$ext` e **engole o erro** (logótipo, capa, documento do dono e comprovativo de atividade).
  Pior caso: ficheiro sem extensão ou PDF manda um tipo inválido e a loja fica sem o documento sem
  ninguém saber.
- `lib/screens/add_product_screen.dart:444` — foto de produto com `image/$ext` (o balde aceita, mas
  HEIC fica ilegível no navegador).
- `lib/screens/admin/admin_partner_detail_screen.dart:225, 341` e
  `lib/screens/admin/admin_service_provider_detail_screen.dart:623, 796` — painel manda `image/jpg`
  (aceite, porque o balde não restringe; o erro aparece, não é engolido).
- Limpeza e lavagem (`provider_upload_service.dart`, `carwash_upload_service.dart`): já corrigem o
  tipo e mostram o erro — sem o defeito. Fotos de entrega e talão: vão pela Edge, sem o defeito.

**F — Publicação:** ver a secção "Publicação" no fim.

## O SAM (estafeta real, candidatura de 22/10)
A ficha dele mostra agora: Falta selfie, foto do documento, número do documento, foto do veículo e
matrícula. **O "comprovativo de atividade" que ele enviou não é das Finanças — é a fotografia de uma
folha do Burger King com instruções para estafetas.** Não aprovar o comprovativo. Ele já pode
reenviar tudo pelo "Conta em análise" com a versão nova da app (ou na web hoje).

## Erros encontrados pelo caminho (reportados, não corrigidos)
1. NIF repetido mostra ao estafeta uma mensagem técnica em inglês: "Erro no registo: duplicate key
   value violates unique constraint idx_drivers_nif_unique".
2. As rotas do painel (`/#/admin/...`) abrem para qualquer conta com sessão; os dados ficam
   protegidos pelo servidor (cada um só vê a sua linha), mas o ecrã abre.
3. O cadastro novo não grava o e-mail nem a data do consentimento na linha do estafeta (aparecem
   "—" no painel); ficam só na conta de acesso.
4. Encerrar conta (`delete-account`) não limpa o comprovativo de atividade — o da conta de teste 1
   (imagem fictícia) continua "em análise" na fila do comprovativo; pode ser recusado no painel.
5. Contas encerradas ficavam em "Pendentes" — **corrigido** neste ecrã (commit `1702a55e`), porque
   as minhas contas de teste iam aparecer lá.

## Limpeza
As 2 contas de teste foram encerradas pelo caminho oficial da app (o próprio utilizador pede):
nome "Conta eliminada", fotos apagadas do armazém (contagem 0), conta bloqueada para sempre.

## PARA O DANILO
- Abre "Aprovações" → SAM → carrega em "Pedir documentos em falta". Não aproves o comprovativo
  dele (é uma folha do Burger King).
- Decidir se queres a função dedicada do reenvio (proposta guardada; precisa de quem possa aplicar
  migrações na tabela de estafetas).

## Publicação (as 3 plataformas)
- **Web (app.boraguarda.com):** dois deploys verdes; o ficheiro da app no ar tem as frases novas
  ("Pedir documentos em falta", "Falta enviar", "Selfie e foto do documento obrigatórias") e o ecrã
  de aprovações já pede só estafetas não encerrados (`deleted_at=is.null`, `prova_filtro_eliminados.py`).
  Todas as provas de ecrã acima foram feitas neste site no ar.
- **Android (Play, faixa alpha):** autoteste dos 3 perfis no emulador verde + pacote enviado;
  versionCode **687** (blocos A–D) e **688** (filtro das contas encerradas);
  `app_latest_version_code = 688`.
- **iPhone (App Store Connect / TestFlight):** build **204** — "UPLOAD SUCCEEDED with no errors",
  Delivery UUID `51580d52-7cfc-4bbb-87cc-c9c064c35d60`, `app_latest_version_code_ios = 204`
  (blocos A–D). O filtro das contas encerradas segue no build seguinte, que ficou em fila no CI.

## Registo
e2e_log, fluxo `cadastro-estafeta-fotos-22-10`, linhas 4390 a 4412. Provas em
`.claude/.ai/provas/cadastro-estafeta-2026-10-22/` (sem dados pessoais) e, só no PC, as do SAM em
`C:\Users\danil\Documents\Bora-provas-privadas\cadastro-estafeta-2026-10-22\`.

---

**Para ouvir (resumo):** Fiz isto: as fotos do cadastro do estafeta passaram a chegar (antes perdiam-se
todas sem ninguém saber, e o documento do veículo nunca chegava); o teu ecrã de aprovação mostra agora
tudo o que o estafeta envia, com as fotos a abrir em grande, o que falta a vermelho e um botão para lhe
pedir o que falta; e o estafeta, na "Conta em análise", vê o que falta e envia ali mesmo. Está no site,
no Android (versão 688) e no iPhone (build 204). Falta isto: a função própria de reenvio, que a nossa
tranca não deixou criar — usei a que já existia e funciona. Erros que encontrei: o comprovativo do SAM é
uma folha do Burger King, não das Finanças; o cadastro de parceiros tem o mesmo defeito de engolir fotos;
um NIF repetido mostra um erro técnico em inglês. Próximo passo: abre o SAM nas aprovações e carrega em
"Pedir documentos em falta".
