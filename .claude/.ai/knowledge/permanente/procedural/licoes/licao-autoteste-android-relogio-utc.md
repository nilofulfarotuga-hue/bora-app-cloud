---
tema: licao-autoteste-android-relogio-utc · escopo: projeto · estado: atual · atualizado: 2026-10-05
id: licao-autoteste-android-relogio-utc
tipo: licao
origem: [integration_test/demo_real_test.dart, lib/models/restaurant_model.dart, tool/ci/autoteste_emulador.sh, corridas 495 e 497 do build_android.yml]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: auto
---

# Lição — o emulador do autoteste anda em UTC: de verão, das 08h às 10h de Lisboa as lojas estão "fechadas"

- **Contexto:** envio para produção às 08h15 de Lisboa de 05/10/2026 (merge `9fe6b9f8`). O job
  `autoteste` do `build_android.yml` falhou duas vezes em `não apareceu: botao-ver-carrinho` e
  travou o build Android.
- **A descoberta:** não era regressão. Há dois relógios a discordar:
  - a **app** decide "loja aberta" pelo relógio do aparelho (`RestaurantModel.isOpenNow` usa
    `DateTime.now()` — `lib/models/restaurant_model.dart:367-369`) e o emulador do CI anda em **UTC**;
  - o **arnês** só salta o carrinho "fora de horas" pela hora de **Lisboa**
    (`lisboa.hour < 8 || lisboa.hour >= 22`) ou quando a própria app diz "está fechada"
    (`integration_test/demo_real_test.dart:442-483`).

  De verão (Lisboa = UTC+1), entre as 08h e as 10h de Lisboa o emulador ainda não chegou às
  09:00, hora a que a Auchan abre: para a app a loja está fechada, mas o arnês já exige o
  carrinho. E como a ficha do produto dizia "adicionado ao carrinho" em vez de "está fechada"
  (bug #26 de `permanente/episodica/bugs-resolvidos.md`), o arnês não tinha como saber.
- **Medido a 2026-10-05 (horas UTC, registadas pela missão):** a corrida #495 falhou às 07:15 e
  às 08:16; a #497 passou às 09:30 e publicou o versionCode 649 — com o defeito da ficha ainda no
  código. Mudou a hora, não o carrinho. Só foi medido de verão; com a hora de inverno a diferença
  Lisboa–UTC muda e a janela tem de ser medida de novo.
- **Regra a aplicar:**
  1. Autoteste a falhar em `botao-ver-carrinho` de manhã → olhar primeiro para a hora. Não é para
     "corrigir" o teste nem o carrinho: relançar os jobs falhados depois das 10h de Lisboa
     (`.claude/.ai/provas/ronda-05-10/relancar_ci.mjs <run_id>`).
  2. Enquanto a correcção do bug #26 não estiver publicada, não empurrar para produção entre as
     08h e as 10h de Lisboa.
  3. A prova está no `autoteste.log` do **artefacto** `autoteste-android-<n.º da corrida>` —
     linhas `[arnes] … sao HH:MM no simulador` e `CartStore.addItem: BLOQUEADO` —, não no registo
     do job, que só mostra as últimas 120 linhas (`tool/ci/autoteste_emulador.sh:34-36`).
- **Mesma família, já vista:** 13/09/2026, corrida #432 às 23:25 UTC, "nenhuma das 5 lojas abriu"
  (`PADRAO_BORA.md` §1.27); 22/09/2026, 21:05 UTC = 22h05 de Lisboa, a janela do arnês media-se em
  UTC (comentário em `integration_test/demo_real_test.dart:469-474`). Lição do PADRAO: um teste que
  corre a horas diferentes das tuas descobre regras que só se cumpriam de dia.
- **Evidência:**
  - produção, 2026-10-05: `restaurants.business_hours` da Auchan abre às `09:00`;
    `platform_settings.app_latest_version_code = 649`;
  - commit `8d15f259` (`ci: bump versionCode to 649`, 10:01:49Z), que só existe com o autoteste
    verde; `lib/screens/product_detail_screen.dart` nesse ramo (`6c86177d`) ainda sem o aviso de
    loja fechada;
  - relatório `.claude/.ai/reports/2026-10-05-ronda-dinheiro-despacho.md`, secção "Porque o
    autoteste falhou duas vezes".

`estado: atual`
