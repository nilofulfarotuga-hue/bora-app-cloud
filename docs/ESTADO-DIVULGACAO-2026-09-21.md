# Estado da divulgação — 2026-09-21 (Bloco E0, zero alterações)

> Missão `link-unico-iphone`, run `link-unico-20260921`. Escrito antes de mexer em seja o que for.
> Tudo o que está aqui foi lido do ar, do repo, da VPS ou da base — nada foi presumido.

## 0. O que NÃO bate com o prompt (para o Danilo ouvir primeiro)

O prompt dizia que a página `boraguarda.com/baixar`, vista a 21/09, mostrava ao iPhone
"Pedir pelo site — iPhone ou computador · sem instalar nada" em vez do botão da App Store.

O que está mesmo no ar (puxado com `curl`, `md5` igual ao ficheiro do repo `bora-site/baixar.html`,
commit `b36887d` de 2026-09-13 21:08, "feat(baixar): botao da App Store no iPhone e QR das duas
lojas"): o HTML tem os três botões — Google Play visível, App Store escondido (`hidden`) e "Pedir
pelo site" visível — e é o JavaScript da página que, ao ler o aparelho, mostra o botão da App Store
em primeiro no iPhone, esconde o da Play, e muda a linha pequena do botão do site. Quem puxa a
página sem correr JavaScript (uma leitura por `fetch`, como a Claude.ai faz) vê exactamente o que
o prompt descreve: Play em cima e "Pedir pelo site — iPhone ou computador". Foi assim que a
verificação de 21/09 foi feita, e por isso deu a conclusão errada.

Conclusão: no iPhone com JavaScript a App Store já aparece desde 13/09. Mas o pedido do Danilo
continua por cumprir em três pontos, e é isso que o Bloco E1 vai fazer:

1. "Pedir pelo site" ainda é um botão inteiro (branco, do mesmo tamanho) no iPhone e no Android —
   ele quer uma linha pequena por baixo, alternativa, nunca caminho principal.
2. No computador os botões saem empilhados e há DOIS QR pequenos (Play e App Store) — ele quer os
   dois botões lado a lado e UM QR grande que aponte para `/baixar`, para o telemóvel decidir.
3. Sem JavaScript a página cai no Android: o botão da App Store nasce escondido. Passa a nascer
   visível (as duas lojas), e o JavaScript só esconde a que não interessa.

Os dois links da Apple respondem: `apps.apple.com/pt/app/id6809954739` e
`apps.apple.com/pt/app/bora-entregas-e-servicos/id6809954739` dão HTTP 200 com o título
"App Bora — entregas e serviços – App Store" (com agente de computador); com agente de iPhone a
Apple devolve 301 para `itms-apps://`, que é o que abre a loja no telemóvel. Play Store 200,
`app.boraguarda.com` 200, `/baixar?de=qr-flyer` 200.

## 1. A página /baixar — como está publicada e no repo

- Repo vivo: `C:\BoraLocal\projetosflutter\bora-site` (é o git; a junção `Desktop\bora-site`
  aponta para `Desktop-PC-antigo\bora-site`, que NÃO é git e não se toca).
- Publicada = repo, byte a byte (md5 `e90fb144…` nos dois lados, 12 018 bytes).
- Origem por peça: `?de=` aceita `qr-feed, qr-story, qr-reel, qr-carrossel, qr-extra, qr-grupo,
  qr-flyer, pago, bio, site` e `qr-grupo-<slug>`; o resto cai em `directo`. A origem vai no
  Install Referrer da Play (`utm_source=<de>&utm_medium=bora-redes&utm_campaign=guarda-2026-09`)
  e no `?de=` do site. Contagem de visitas por `/api/visita` (função Pages), com a plataforma.
- BEMVINDO na página bate com a base: `promo_codes` code=BEMVINDO, type=tokens_grant,
  value_cents=1000, max_uses_per_user=1, is_active=true (SELECT de 21/09).
- Publica-se com `bora-site/deploy-cloudflare.sh` (regra 4.1 do PADRAO_BORA), nunca a pasta em bruto.
- O repo do site tem alterações por committar de outra sessão (`og-image.png`, `deploy-cloudflare.sh`,
  `privacidade.html`, `termos.html`, `functions/`, `provas/apple-review/`, dois vídeos). Não são
  desta missão: commit só de `baixar.html` e do que esta missão tocar, caminho a caminho.

## 2. Onde vive o QR e que destino está cravado em cada molde

Gerador único, já certo: `bora-site/tools/qr/bora_qr.py` (05/09) — `BASE_DESTINO =
https://boraguarda.com/baixar`, QR = `/baixar?de=<origem>`, `colar_qr()` para feed/story/reel/
carrossel, `ler_qr()` com OpenCV (a mesma leitura do portão). A cópia da VPS vive em
`/opt/data/social/bora_qr.py` e o portão mecânico é `/opt/data/social/portao_qr.py` (descodifica
o QR da própria imagem e chumba destino errado; corre antes do `fiscal_arte.py`).

Moldes de arte impressa — TODOS com QR velho (lidos com o `ler_qr` a 21/09):

| molde | ficheiro do gerador | destino cravado |
|---|---|---|
| Flyer A4 + WhatsApp | `bora-site/tools/flyer/build_flyer.py` (`PLAY_URL`, `WEB_URL`) | 2 QR: Play Store + `app.boraguarda.com/#/registo-cliente` |
| Cartaz Bora A3 + WhatsApp | `Desktop\Bora\cartaz-bora\montar_cartaz.py` | 2 QR: idem |
| Autocolantes Bora (clara/escura, 5 formatos, PDFs) | `Desktop\Bora\autocolantes-bora\build.py` + `entregaveis.py` | 2 QR (Ø5 e faixa só Play) |
| Material Goola (cartaz V/H + autocolantes) | `Desktop\Bora\goola-material\build_cartaz.py`, `build_autocolantes.py` | 2 QR: idem |

Leitura literal dos QR das peças (todas as 30 imagens lidas): nenhuma aponta para `/baixar`; 22
lêem Play+registo web, 8 lêem só Play (formatos pequenos) — ver saída em `provas/link-unico-20260921/`.
Os verificadores (`verificar.py`, `verificar_cartaz.py` ×2) exigem hoje os DOIS URL velhos: têm de
passar a exigir o único.

Mini-sites de parceiros (`bora-site/sites-parceiros/*`) e `viagens.html` têm botões (não QR) para
Play e `app.boraguarda.com/#/registo-cliente` — fora do scope, fica na secção "fora do scope".

## 3. O robô das redes (VPS `srv1786862.hstgr.cloud`, contentor `hermes-agent-fvnc-hermes-agent-1`)

Crontab do host (hora de Lisboa): loja do dia `0 12 * * *` (`social-loja-do-dia.sh`, só publica
quando a `rotacao.md` tem linha para hoje — terça parceiro, sábado loja grande); story `30 19`
todos os dias + `0 10` (manhã); reel `0 18` seg/qua/sex; carrossel `0 18` ter/qui/sáb; formato
extra `0 15`; grupos plano `10 9`, resumo `30 18`; grelha da semana `0 11` domingo
(`social-semana.sh`); medir `0 9` segunda; reavaliação `35 8,13,19`; resumo do dia `30 21`
(`resumo_do_dia.py` — o "verificador 21:30"); DM automático do Instagram a cada 10 min.

Links que cada script escreve hoje:
- loja do dia (`texto_loja.py`): `boraguarda.com/baixar?de=qr-feed` ✔
- story (`story_pergunta.py`): rodapé "Bora — Guarda · boraguarda.com/baixar" ✔
- reel (`social-reel.sh`): legenda `?de=qr-reel` ✔; MAS o cartão de fecho do caminho de
  recurso (slideshow) escreve "Bora — Guarda · play.google.com/store" ✘ (linha 77)
- carrossel (`social-carrossel.sh` 165-166): "Android: …/baixar?de=qr-carrossel" e
  "iPhone ou computador: https://app.boraguarda.com" ✘ — manda o iPhone para o site
- formato extra: `?de=qr-extra` ✔ · grelha (`semana_grelha.py`): `boraguarda.com/baixar` ✔
- grupos: `?de=qr-grupo-<slug>` (regra 6 do `_COMUM.md`) ✔
- bio do Instagram: `boraguarda.com/baixar?de=bio` ✔

Rotação (`/opt/data/social/rotacao.md`): próximas linhas 22/09 sabores-brasil, 26/09 pingodoce,
29/09 goola, 03/10 kfc, 06/10 Ouro e Prata, 10/10 intermarché… A nota da rotação diz "Mr Kebab e
Sabores de Casa só entram quando deixarem de estar coming_soon". Sabores de Casa Açaí já não está
(`coming_soon=false`, 106 produtos, parceiro aprovado) mas ainda NÃO está na rotação nem tem pasta
de fotos em `/opt/data/social/parceiros/` (só `goola/`, `ouro-e-prata/`, `sabores-do-brasil/` e os
logos). O portão do parceiro (`portao_parceiro.py`) chumba qualquer peça de parceiro sem foto real
dele — logo, sem pasta e sem registo em `parceiros-fotos.json`, a loja do dia dela não sairia.
Mr Kebab: `coming_soon=true`, 47 produtos — o robô salta-o (correcto, é decisão do Danilo).

## 4. Peças de arte em `Desktop\Bora\` e QR

- `autocolantes-bora\` (04/09): 5 formatos × 2 famílias, A4 de pré-visualização, 2 PDFs de gráfica — QR velho.
- `cartaz-bora\` (04/09): A3 de gráfica + WhatsApp + lado-a-lado com o Goola — QR velho.
- `goola-material\` (03/09): cartaz vertical/horizontal + WhatsApp + 5 autocolantes + PDF — QR velho.
- `fichas\`, `filme\`, `ios\`: sem peças com QR.
- Flyer A4/WhatsApp: já não está em `Downloads` (o gerador escreve lá); refaz-se pelo `build_flyer.py`.

## 5. Ficha da App Store (para o E3)

Ficha pública: "App Bora — entregas e serviços", id 6809954739, loja PT. Idioma e categoria
confirmam-se no App Store Connect (agente de clique, perfil certo do Chrome).

## 6. Provas deste bloco

- `curl` da `/baixar` (HTTP 200, md5 igual ao repo) e dos 5 links das lojas — saída acima.
- SELECT em `promo_codes`, `restaurants` (Sabores de Casa, Goola, Mr Kebab) e colunas do `e2e_log`.
- Leitura dos QR das 30 imagens de `Desktop\Bora` com `bora_qr.ler_qr` (OpenCV).
- `crontab -l` e `grep` dos links nos scripts da VPS por SSH.
