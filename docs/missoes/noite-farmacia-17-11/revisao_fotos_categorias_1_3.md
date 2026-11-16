# Missão noite-farmacia-17-11 — bloco 1.3: fotos e categorias da Farmácia da Sé

Data: 16/11/2026 (noite), Claude Code no PC do Danilo. Pedido da missão noite-farmacia-17-11 (bloco 1.3).
PC: memória livre medida 2037 MB no início e 2836 MB no fim; nada de Flutter, nada de emulador.

## Resumo para ouvir

Fiz isto: vi as 867 fotos da Farmácia da Sé, uma a uma, em 29 folhas de contacto com o nome por baixo.
Encontrei 6 fotos claramente erradas (mostram outra marca ou outro produto) e tirei-lhes a foto: na app o
cliente passa a ver o quadrado cinzento com o ícone, em vez de um produto que não é o que compra. Mudei 9
produtos que estavam na categoria errada (por exemplo, um gel da Eroxon que estava em "Suplementos" e
ampolas Martiderm que estavam em "Homem"). Não mexi em nomes, preços, disponibilidade nem noutras lojas.
Antes de mexer fiz a cópia de segurança. Na Farmácia Teixeira vi 100 produtos ao acaso: 2 têm a foto
errada, e por comparação exata descobri mais 4 da Teixeira com as mesmas fotos erradas da Sé (não corrigi,
a ordem era só verificar).

Falta isto: pôr a foto certa nos 6 produtos da Sé (agora estão sem foto, marcados "precisa de foto");
decidir os 4 duvidosos; corrigir as 6 da Teixeira se a Claude.ai mandar.

## Números

- Sé: 867 produtos vistos (867 fotos descarregadas, 0 falhas; dados conferidos por md5 com o servidor).
- Fotos claramente erradas: 6 (corrigidas). Duvidosas: 4 (não mexidas).
- Fotos iguais (mesmo md5) em produtos diferentes: 4 grupos, 12 produtos (detalhe abaixo).
- Categorias: 16 na Sé, todas mantidas; 9 produtos mudados de categoria.
- Teixeira: 100 vistos ao acaso (ordem por md5(id||'noite-17-11'), reproduzível), 2 claramente errados,
  0 duplicados por md5 dentro da amostra; mais 4 fora da amostra com a mesma foto errada da Sé.

## Fotos claramente erradas — Farmácia da Sé (corrigidas)

O que fiz em todas: `photo_url = null`, `needs_photo = true`, `image_source = 'foto-errada-glovo-17-11'`.
É o mesmo que o botão "Resetar foto" do painel faz (RPC `admin_reset_product_photo`). No código da app
(`lib/screens/store_products_screen.dart`, `_ProductThumbnail` e `_PlaceholderImage`;
`lib/stores/restaurant_store.dart` via `imagemParaMostrar`) uma foto vazia mostra um quadrado cinzento com
ícone; o produto continua visível e à venda. Nenhum filtro esconde produtos sem foto.

| id | nome | o que a foto mostrava |
|---|---|---|
| fse-4611686018581478491 | A-DERMA DERMALIB+ CR CICA REPAR 100ML | creme "Rosacure Fast" (outra marca) |
| fse-4611686018581481782 | MARTIDERM PROTEOS AMP HYDRA PLUS X30 | sérum Filorga "Lift-Designer" (outra marca) |
| fse-4611686018581472528 | ISDIN FOTOULTRA ACTIVEUNIFY COR50+ 50ML | ISDIN FotoUltra 100 "Spot Prevent" (outro produto) |
| fse-4611686018581478459 | VICHY NEOVADIOL REPLENISHING NOITE 50ML | Neovadiol "Redensifying Lifting Day Cream" (outro produto) |
| fse-4611686018581483455 | VICHY NEOVADIOL REDENSIFYING NOITE 50ML | Neovadiol "Redensifying Lifting Day Cream" (creme de dia, não de noite) |
| fse-4611686018581483457 | VICHY NEOVADIOL REPLENISHING 50ML | Neovadiol "Redensifying Lifting Day Cream" (outro produto) |

Prova (lida de volta depois do UPDATE): 6 linhas com photo_url nulo, needs_photo true, a marca nova,
is_available true e o preço igual ao da cópia.

## Duvidosas — Farmácia da Sé (não mexi)

| id | nome | o que a foto mostra | porquê duvidosa |
|---|---|---|---|
| fse-4611686018581469812 | Nasexilo, 1 mg/mL-10 mL x 1 sol pulv nasal | caixa "Actifed Descongestionante" 1 mg/ml, 10 ml | mesma substância e dose; provável mudança de nome da marca |
| fse-4611686018581469852 | Flonaze (60 doses), 50 mcg/dose | caixa "Vibrocil Anti-Alergias" fluticasona 50 mcg | mesma substância e dose, mesma empresa (Haleon); provável mudança de nome |
| fse-4611686018581470411 | Fenistil Gel, 1 mg/g-50 g | bisnaga de gel ao lado de uma caixa "Fenistil Emulsão" | foto misturada: a bisnaga está certa, a caixa não |
| fse-4611686018581475172 | URIAGE BARIEDERM CICA SPRAY 100ML | "Uriage Bébé 1er Spray asséchant réparateur" | mesma marca, versão de bebé de um spray parecido |

## Fotos iguais em produtos diferentes (md5) — Sé

1. LYCIAS T2 MEL e LYCIAS T2 NUDE (2 produtos): foto genérica da meia, só muda a cor. Não é erro.
2. LYCIAS T3 MEL, T3 NUDE, T4 NUDE, T4 MEL, T3 PRETO (5 produtos): idem, foto genérica. Não é erro.
3. VICHY NEOVADIOL REPLENISHING NOITE, REDENSIFYING NOITE, REPLENISHING (3 produtos): a foto é do creme de
   dia Redensifying. Era erro: corrigido (tabela acima).
4. CAUDALIE VINOHYDRA CR HIDRA INTENSE 60ML e 50ML (2 produtos): o de 60 ml usa a foto do de 50 ml desde a
   correção à mão de 16/11 (`corrigido-bora-16-11`). Não mexi.

## Categorias — Farmácia da Sé

Contagem antes das mudanças (SQL): Dermocosmética 187, Cabelo 127, Higiene e cuidado pessoal 99,
Solares 61, Medicamentos sem receita 52, Saúde oral 45, Constipação gripe e alergias 44, Bebé e mamã 43,
Suplementos e vitaminas 41, Saúde sexual e íntima 38, Maquilhagem e perfumes 31, Nutrição e controlo de
peso 23, Dor e febre 22, Ortopedia e bem-estar 20, Homem 19, Primeiros socorros 15. Total 867.

Verifiquei os exemplos do pedido: nenhum champô fora de Cabelo (os de bebé estão em Bebé e mamã, o
Papillon Pure Mint em Homem, ambos certos); nenhum protetor solar fora de Solares (só produtos com SPF que
são maquilhagem ou batom, certos onde estão); as chupetas Chicco estão em Bebé e mamã.

Mudadas (9):

| id | nome | de → para |
|---|---|---|
| fse-4611686018581470524 | EROXON GEL UNIDOSE TUBOS X4 | Suplementos e vitaminas → Saúde sexual e íntima |
| fse-4611686018581472691 | Isdinceutics Instant Flash Monodoses Efeito lifting imediato | Homem → Dermocosmética |
| fse-4611686018581478362 | MARTIDERM ORIGIN FLASH SER 15ML | Homem → Dermocosmética |
| fse-4611686018581478368 | MARTIDERM FLASH AMP 2ML X 5 | Homem → Dermocosmética |
| fse-4611686018581478639 | ISDIN ACNIBEN GEL ESFOLIANTE SUAV 100ML | Homem → Dermocosmética |
| fse-4611686018581474456 | MUSTELA PN AGUA LIMPEZA BEBE500ML PRESP | Dermocosmética → Bebé e mamã |
| fse-4611686018581472599 | ISDIN ACNIBEN BODY SPRAY 150ML | Medicamentos sem receita → Dermocosmética |
| fse-4611686018581478409 | URIAGE BARIEDERM CICA DAILY SERUM 30ML | Medicamentos sem receita → Dermocosmética |
| fse-4611686018581480240 | COLAGENIUS BEAUTY AC HIALURONICO SAQX30 | Nutrição e controlo de peso → Suplementos e vitaminas (os outros 3 Colagenius já lá estão) |

Duvidosas de categoria (não mexi, ficam como sugestão):
- Antifúngicos que são medicamentos em "Higiene e cuidado pessoal": Lamisil creme (fse-4611686018581470142),
  Daktarin (…470201), Canesten (…470207), Nizoral creme (…470277). Talvez "Medicamentos sem receita".
- URIAGE BARIEDERM CR PROT ISOLANTE 75ML (…474478) em "Medicamentos sem receita": é creme cosmético de
  mãos; não é claro se vai para Dermocosmética ou Higiene.
- LIERAC BODY SCULPT GEL BUSTO REFIR (…478603) e LRPOSAY LIPIKAR AP+ OL LAV (…481757) em "Bebé e mamã".
- OHROPAX tampões auriculares (…471855, …472057) em "Medicamentos sem receita".

Prova (comparação com a cópia, SQL): 6 fotos mudadas, 9 categorias mudadas, 0 nomes mudados, 0 mudanças de
disponibilidade, 867 produtos, continuam 16 categorias.

## Farmácia Teixeira — 100 ao acaso (só verificação, nada corrigido)

Claramente errados na amostra: 2.
- fte-4611686018581479552 AVENE TOL CONTROL BALS 40ML: a foto é "Youth Lab Candy Scrub & Mask" (outra marca).
- fte-4611686018581479604 VICHY NEOVADIOL REPLENISHING NOITE 50ML: creme de dia Redensifying (mesmo erro da Sé).

Fora da amostra, os produtos da Teixeira com o mesmo nome dos 6 errados da Sé têm o ficheiro com o MESMO md5
da foto errada (prova exata, não visual):
- fte-4611686018581479636 A-DERMA DERMALIB+ CR CICA REPAR 100ML (Rosacure)
- fte-4611686018581484195 VICHY NEOVADIOL REPLENISHING 50ML (creme de dia Redensifying)
- fte-4611686018581484193 VICHY NEOVADIOL REDENSIFYING NOITE 50ML (creme de dia Redensifying)
- fte-4611686018581472802 ISDIN FOTOULTRA ACTIVEUNIFY COR50+ 50ML (Spot Prevent)
O Martiderm Proteos Hydra Plus x30 não existe na Teixeira.

## Tabelas de cópia

- `public.bkp_products_fotos_cat_se_20261116` — 867 linhas (id, name, category, photo_url, image_source,
  needs_photo, is_available) da Sé, tirada antes de qualquer UPDATE; RLS ligado (lido de volta: true).
- Para desfazer: `update products p set photo_url=b.photo_url, image_source=b.image_source,
  needs_photo=b.needs_photo, category=b.category from bkp_products_fotos_cat_se_20261116 b where p.id=b.id
  and p.restaurant_id='farmacia-se-guarda' and (p.photo_url is distinct from b.photo_url or p.category is
  distinct from b.category);`

## Erros que encontrei pelo caminho

- A trava do modo automático bloqueou ler `.dart_defines` e listar variáveis de ambiente (queria a chave
  pública para ler os produtos por REST). Não contornei: passei os dados pelo MCP do Supabase e conferi a
  cópia local com md5 calculado no servidor (igual).
- Na Sé e na Teixeira o mesmo catálogo da Glovo trouxe as mesmas fotos erradas: o erro vem da origem, não da
  importação. Outras farmácias vindas da Glovo podem ter os mesmos ficheiros.

## Próximo passo

1. Pôr foto certa nos 6 da Sé (procurar a imagem oficial do produto; carregar no bucket product-images).
2. Aplicar o mesmo tratamento às 6 da Teixeira (2 da amostra + 4 por md5), com cópia antes.
3. Decidir os 4 duvidosos de foto e as sugestões de categoria.

Ficheiros de trabalho (temporários, fora do repo): folhas em
`C:\Users\danil\AppData\Local\Temp\claude\9f7d01bb1a9d0958\7d8ff41a-530e-4d6e-a010-9472d7753f6c\scratchpad\fotos-se\folhas\`
e `...\scratchpad\fotos-te\folhas\`.
