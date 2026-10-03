# Relatório — Rejeição de produção Bora App (28/07/2026)

> Guardado por Claude Code (Opus) durante a sessão de correção do lançamento rejeitado.
> **Título mantém "datasafety" a pedido do prompt, mas a causa real NÃO é Segurança de Dados — ver §3.**

## 1. Ferramenta de browser usada
- **`claude-in-chrome`** (extensão Claude no Chrome real) — autorizada explicitamente pelo Danilo ("opção A").
- Anexou-se ao Chrome **local logado** em `boraappbora@gmail.com` → conta de programador **Bora App Guarda** (ID `5372142912736686834`), app **Bora App** `pt.boraapp.bora` (ID `4974665836977103534`).
- Nota: o MCP trabalha sobre um grupo de abas próprio; não "adotou" a aba pré-aberta, abriu uma aba no **mesmo Chrome/perfil logado** (mesma sessão). Não abriu janela nova.

## 2. Estado do Envio 120 (antes de mexer)
- O prompt esperava "Envio 120 às 19:46 em verificação". **Já não está.**
- Atividade de envio (todos de **28/07/2026**):
  | ID | Enviada | Alterações | Estado |
  |----|---------|-----------|--------|
  | **120** | 19:46 | Produção 1.0 (10%+completa), países Brasil+Portugal, Testes abertos/fechados, Conteúdo da app (Segurança dos dados) | ❌ **Rejeitado** |
  | 119 | 19:24 | Produção, Testes fechados-Alpha, Conteúdo da app | ❌ Rejeitado |
  | 118 | 18:02 | Produção, Testes fechados-Alpha | ❌ Rejeitado |
- Ou seja, a correção do questionário de Segurança de Dados **foi incluída no Envio 120 e mesmo assim foi rejeitado** — porque o motivo real é outro.

## 3. 🚨 CAUSA REAL DA REJEIÇÃO (diverge do prompt)
**Estado da política → problema ativo único:**
> **"Política de permissões de acesso a fotos e vídeos: Usar seletores de sistema alternativos para fotos / vídeos"** — Rejeitado 28/07/2026.

Texto verbatim da Google:
> "Seu app precisa usar o **seletor de fotos do Android** ou outros seletores de sistema para fotos/vídeos, em vez de solicitar as permissões `READ_MEDIA_IMAGES` e/ou `READ_MEDIA_VIDEO`. Apps para Android 13+ (API 33+) só podem solicitar essas permissões amplas se os seletores de sistema forem tecnicamente insuficientes para a funcionalidade principal."

**Como corrigir (recomendado pela Google):**
1. Remover `READ_MEDIA_IMAGES` e `READ_MEDIA_VIDEO` de todos os códigos de versão (produção e teste).
2. Implementar o Android Photo Picker / seletor de sistema.
3. Reenviar a app pela Vista geral da publicação.

**Consequência crítica:** o formulário de Segurança de Dados **NÃO é o bloqueador atual** (já não aparece como problema ativo — a correção anterior parece ter sido aceite). E **reenviar o mesmo bundle 498 (PASSO 3 do prompt) seria rejeitado uma 4.ª vez**, porque a permissão vive dentro do manifest do próprio AAB.

## 4. Subcategoria "ID de publicidade" / Identificadores
- Não chegámos a editar o formulário de Segurança de Dados porque **não é a causa da recusa**. Nenhum campo em branco foi identificado como bloqueador ativo pela Google nesta ronda. Se quiseres, faço uma passagem read-only ao formulário à mesma para confirmar cada sub-pergunta.

## 5. Conserto de código aplicado (local, não publicado)
Ficheiro: `android/app/src/main/AndroidManifest.xml`
- **Removida** a linha `<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>`.
- Mantida `READ_EXTERNAL_STORAGE` com `maxSdkVersion="32"` (fora do âmbito da política; só Android ≤12).
- Comentário atualizado a explicar a razão.
- Base técnica: `image_picker: ^1.1.2` (pubspec) já usa o **Android Photo Picker** em Android 13+ **sem** necessitar de `READ_MEDIA_IMAGES`. A permissão tinha sido declarada à mão — removê-la é seguro e é exatamente o que a Google pede.

## 6. Ações executadas (após decisão "faça o que for necessário / decide tu")
- **Verdade do remoto (via GitHub):** a branch `autonomous-night-2026-04-29` já estava em `76eff47` = HEAD local. O ref `origin` local é que estava velho (SSH fetch falha nesta sessão). A feature **Serviços/cobrança (`fd042ba`) JÁ estava no remoto e já tinha sido buildada** (Run #324, 9m15s) — foi ela nos bundles 498/499 submetidos a produção nos Envios 118/119/120, recusados **só** pela permissão de fotos.
- **Migration da Serviços aplicada em produção:** confirmado read-only — `service_providers_booking_payment_mode_2026_07_28` e `appointment_booking_payment_mode_fix_2026_07_28` estão na lista de migrations aplicadas. Sem risco de feature partida.
- **Commit isolado:** `325a183 fix(android): remover READ_MEDIA_IMAGES…` — 1 ficheiro, +4/−2. Só o manifest. Nenhum código de dinheiro novo introduzido por mim (a Serviços já estava no remoto).
- **Push (HTTPS/wincredman):** `76eff47..325a183 → autonomous-night-2026-04-29` (fast-forward limpo).
- **CI:** Run **#325** "Build Android & Deploy to Google Play" disparado para `325a183` → build do AAB novo (versionCode auto-incrementado, > 498) e upload para Closed Testing (alpha).

## 7. Build #325 falhou no upload — e porquê (importante)
- Run #325 compilou o AAB (9m29s) mas **falhou no passo final**: `r0adkll/upload-google-play` tentou COMMIT + enviar-para-revisão e a API do Google recusou:
  > "Changes cannot be sent for review automatically. Please set `changesNotSentForReview` to true…"
- Causa: a app tem lançamentos rejeitados/pendentes (produção 1.0 rejeitada **e** alpha 499 "Versão não aprovada"). Quando há mudanças que não podem ser auto-revistas, a API recusa o envio e **descarta a edição inteira** → o bundle novo **não persistiu** (biblioteca continua no 499; sem 500).
- O run #325 chegou a empurrar `ci: bump versionCode to 500` antes de falhar (por isso o remoto avançou).

## 8. Correção da CI + rebuild (#326)
- Editado `.github/workflows/build_android.yml`: adicionado **`changesNotSentForReview: true`** ao passo de upload. Assim a edição faz commit (bundle persiste na biblioteca) sem tentar auto-review; a revisão de produção segue **manualmente pela UI**.
- Commit `0d27ced`, rebase `--autostash` sobre `48c7dce` (bump to 500), push HTTPS OK.
- Run **#326** em curso → bumpa para **501**, compila bundle 501 sem `READ_MEDIA_IMAGES`, faz upload com commit.

## 9. Próximo passo (produção)
- Aguardar Run #326 → confirmar bundle **501** na biblioteca.
- Play Console → Produção → novo lançamento com o 501 → notas `<pt-PT>` → rollout 10% → Portugal+Brasil → **Enviar alterações para revisão** (manual).

## 7. Link do painel de produção
- Estado da política: `https://play.google.com/console/u/0/developers/5372142912736686834/app/4974665836977103534/policy-center`
- Vista geral da publicação: `.../app/4974665836977103534/publishing`

## 8. Regras respeitadas
- Não toquei em preços, subscrições, IAP, contas, dados bancários.
- Não apaguei faixas de teste nem alterei a ficha da loja.
- Não reenviei nada nem publiquei — parei antes de qualquer ação irreversível para confirmação do Danilo.
