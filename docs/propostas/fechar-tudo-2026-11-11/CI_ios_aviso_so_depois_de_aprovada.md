# CI do iPhone — o aviso de "versão nova" só depois de a Apple publicar (11/11/2026)

**Para quem:** Claude.ai (ou sessão com a tranca aberta). A bora-tranca do PC nega qualquer Edit em
`.github/workflows/**` ("cada push é um lançamento na Play Store"), mesmo com a janela das travas aberta.
**Ordem já aprovada:** página `proposta-ci-ios-latest-so-depois-de-aprovada-2026-11-10-aprovado`.

**Porquê:** o passo "Publicar app_latest_version_code_ios" do `build_ios.yml` grava o número da build logo a
seguir ao envio e liga o aviso de atualização nos iPhones antes de a Apple aprovar. Aconteceu a 10/11 (corrigido
à mão às 19:49) e a 11/11 (07:12); o valor certo hoje era 247.

**Já feito no PC (ramo `ai/2026-11-10-fechar-tudo`):** `.github/scripts/ios_publicar.py --aviso` lê a versão
`READY_FOR_SALE` na App Store Connect, tira o número da build e grava-o em `platform_settings` só se for MAIOR
do que o que lá está (nunca baixa), e lê de volta.

## 1. `build_ios.yml` — tirar o passo que grava cedo demais

Apagar o passo inteiro `- name: Publicar app_latest_version_code_ios (aviso de atualizacao)` (linhas ~663-685,
com o comentário de 07/10 por cima) e pôr no lugar:

```yaml
      # (11/11/2026) O aviso de atualizacao do iPhone ja NAO se grava aqui: a Apple
      # ainda nao aprovou nesta altura. Grava-o a vigia ios_aviso_versao.yml, so
      # quando a versao estiver READY_FOR_SALE (ios_publicar.py --aviso).
```

## 2. Workflow novo `.github/workflows/ios_aviso_versao.yml`

O `.p8` vem do mesmo segredo que o `build_ios.yml` já usa (`ASC_KEY_P8_B64`, em base64, linhas ~613-617).

```yaml
name: iPhone - aviso de versao nova so depois de a Apple publicar
on:
  schedule:
    - cron: '17,47 * * * *'
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: ios-aviso-versao
  cancel-in-progress: true
jobs:
  aviso:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
        with:
          sparse-checkout: .github/scripts
      - name: Gravar app_latest_version_code_ios = build a venda
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_KEY_P8_B64: ${{ secrets.ASC_KEY_P8_B64 }}
          SUPABASE_SERVICE_ROLE_KEY: ${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}
        run: |
          python3 -m pip install --quiet --disable-pip-version-check pyjwt cryptography requests
          mkdir -p ~/private_keys
          echo "$ASC_KEY_P8_B64" | base64 -d > ~/private_keys/AuthKey_${ASC_KEY_ID}.p8
          ASC_P8=~/private_keys/AuthKey_${ASC_KEY_ID}.p8 python3 .github/scripts/ios_publicar.py --aviso
```

Nota: o ramo de produção ignora `.github/**`? Não — um envio só com workflows dispara o build Android e a web
(gasta um versionCode). Juntar ao próximo envio normal.

## 3. `build_android.yml` — cabeçalho velho do passo 11

As linhas 281-286 dizem "Teste FECHADO ('alpha') + Teste INTERNO ('internal')", mas desde 31/07 o passo envia
também para PRODUÇÃO (ver o bloco "PRODUCAO" logo abaixo). Trocar a 1.ª linha por:

```yaml
      # 11. Upload para Google Play — PRODUCAO (todos os utilizadores) + Teste INTERNO
      #     ('internal') + Teste FECHADO ('alpha'), num so envio (ver 'tracks' abaixo).
```

## Prova depois

- Correr `ios_aviso_versao.yml` à mão (workflow_dispatch): com a 1.0.40 (build 247) à venda e a 1.0.41 em
  revisão, tem de dizer "a venda: 1.0.40 build 247; gravado hoje: 247 — nada a mudar".
- Quando a Apple publicar a 1.0.41 (build 250), a corrida seguinte grava 250 e lê de volta.
