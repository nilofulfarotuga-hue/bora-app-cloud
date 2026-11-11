# Catálogo das farmácias da Guarda (Glovo) — missão farmacias-2026-11-11

Recolhido da API pública da Glovo (menu da loja + páginas de categoria + ficha de cada produto) a 11/11/2026.
Nada foi inserido na base. As fotos estão no bucket público `product-images`, pasta `farmacias/<loja>/`.

## Farmácia da Sé (`farmacia-se-guarda`) — Glovo store 461279 / address 732949

- Menu da Glovo: 14 secções, 76 categorias, 185 subsecções; subsecções lidas: 182; em falta: 3.
- Subsecções do menu sem produtos na Glovo (vazias, não é falha de leitura): suplementos-alimentares-c.19758457 / suplementacao-cuidados-de-pele-s.19758241, suplementos-alimentares-c.19758457 / suplementacao-pediatrica-s.25362936, bronzeadores-e-autobronzeadores-c.56618851 / suplementos-para-o-bronzeado-s.56618871.
- Produtos distintos na Glovo (por id): 872.
- Duplicados por nome normalizado retirados: 0. Secções de promoções/mais vendidos: não existem no menu desta loja (só `elementsWithoutMenu` = [{"slugSuffix": "pb"}, {"slugSuffix": "bc"}, {"slugSuffix": "isbc"}], ignorados).
- Produtos finais: **872**; com preço promocional: 0; marcados como medicamento: 115; parafarmácia: 757; esgotados na Glovo no momento: 0 (vão como is_available true, como pedido).
- Sem descrição na ficha da Glovo: 416.
- Fotos: com foto real, subida e provada (200 no URL público, mesmo tamanho, mesmos primeiros bytes e mesmo md5) 867; sem foto real 5. Tipos: image/jpeg 812, image/png 55 (nenhuma AVIF).
- SQL: 867 linhas em 5 INSERT (`insert_farmacia-se-guarda.sql`).

Produtos SEM foto real (ficam fora do SQL; as cópias do quadro ficaram no Storage mas o JSON tem photo_url null):
- fse-4611686018581478511 — Visine , 0.5 mg/ml Frasco conta-gotas 15 ml Col, sol — estado: marcador_sem_imagem_na_glovo: quadro 'PRODUTO SEM IMAGEM DISPONÍVEL' (Nossa Farmácia)
- fse-4611686018581483572 — AVENE HYALURON ACTIV B3 CR REFILL 50ML — estado: marcador_sem_imagem_na_glovo: quadro 'SKIN — IMAGEM INDISPONÍVEL' (a mesma em produtos diferentes)
- fse-4611686018581483668 — CAUDALIE RESVER-LIFT FIRM CR NOITE 50ML — estado: marcador_sem_imagem_na_glovo: quadro 'PRODUTO SEM IMAGEM DISPONÍVEL' (Nossa Farmácia)
- fse-4611686018581478623 — CAUDALIE SOLEIL VIGNES OIL ELIXIR 100ML — estado: marcador_sem_imagem_na_glovo: logótipo Caudalie (cacho de uvas) em vez do produto
- fse-4611686018581474521 — KLORANE CAPILAR MASC MANGA 150ML — estado: marcador_sem_imagem_na_glovo: quadro 'SKIN — IMAGEM INDISPONÍVEL' (a mesma em produtos diferentes)

Categorias (ordem, nome, produtos):

1. Medicamentos sem receita — 52
2. Dor e febre — 22
3. Constipação, gripe e alergias — 45
4. Primeiros socorros — 15
5. Suplementos e vitaminas — 41
6. Nutrição e controlo de peso — 23
7. Bebé e mamã — 44
8. Saúde oral — 45
9. Saúde sexual e íntima — 38
10. Dermocosmética — 188
11. Higiene e cuidado pessoal — 100
12. Cabelo — 128
13. Homem — 19
14. Solares — 61
15. Maquilhagem e perfumes — 31
16. Ortopedia e bem-estar — 20

Amostra ao acaso de 20 produtos para conferir à mão:

| # | Nome | Preço Glovo | Categoria | Medicamento | Foto |
|---|---|---|---|---|---|
| 1 | CAUDALIE RESVER-LIFT FIRM INST SER 30ML | 53,65 € | Dermocosmética | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581483670.jpg |
| 2 | Zovirax Duo, 50/10 mg/g-2g x 1 creme bisnaga | 14,34 € | Saúde oral | sim | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581470266.jpg |
| 3 | SENSIBIO BIODERMA DS CR 40 ML | 27,33 € | Dermocosmética | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581474709.jpg |
| 4 | WIN FIT MELATONINA COMP MAST X60 MELATONINA [PA] LAVANDA (LAVANDULA OFFICINALIS) (EXTRATO) [PA] GRIFFONIA (GRIFFONIA SIMPLICIFOLIA) (EXTRATO) [PA] ALECRIM (ROSMARINUS OFFICINALIS) (FOLHA) [PA] 5-HIDROXITRIPTOFANO [PA] | 20,61 € | Suplementos e vitaminas | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581472017.jpg |
| 5 | VICHY MINERAL 89 CONCENTRADO ROSTO 50ML | 35,50 € | Dermocosmética | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581481548.jpg |
| 6 | CONTROL PLEASURE VIBES ANEL VIBRATORIO | 14,11 € | Saúde sexual e íntima | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581471166.jpg |
| 7 | RENE FURTERER SOL OL PROT VERAO 100ML | 23,91 € | Solares | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581472522.jpg |
| 8 | KLORANE CAPILAR FIGO INDIA CH 400ML | 19,38 € | Cabelo | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581483559.png |
| 9 | MYCOSANA UNHAS SOL 5ML + 10LIMAS | 27,44 € | Higiene e cuidado pessoal | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581475379.jpg |
| 10 | Mebocaína Forte 4 mg + 1 mg + 0.2 mg Pastilha - X 24 Und(s) | 11,20 € | Constipação, gripe e alergias | sim | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581470088.png |
| 11 | EASYSLIM LIPO3 COMP X60 L-CARNITINA [PA] CROMIO (CLORETO) [PA] PECTINA DE MACA [PA] LEVOCARNITINA [PA] GARCINIA (GARCINIA CAMBOGIA) (EXTRATO) [PA] LECITINA SOJA [PA] CROMIO [PA] | 31,92 € | Nutrição e controlo de peso | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581472313.jpg |
| 12 | ISDIN FOTOPROT FWATER BRONZ SPF50 50ML | 31,02 € | Solares | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581472670.png |
| 13 | Cegrinaso MG, 200 mg + 30 mg Blister 24 Unidade(s) Comp revest | 11,14 € | Constipação, gripe e alergias | sim | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581470364.jpg |
| 14 | ISDIN ACNIBEN BODY SPRAY 150ML | 31,86 € | Medicamentos sem receita | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581472599.jpg |
| 15 | A-DERMA DERMAT BIO AG MICELAR 400ML | 21,22 € | Dermocosmética | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581478507.jpg |
| 16 | VICHY PUR THERMAL DESMAQ INTEG 300ML | 21,56 € | Dermocosmética | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581474533.jpg |
| 17 | PARODONTAX COMPL PROT BRANQ PASTA DENT 75 | 9,07 € | Saúde oral | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581472133.jpg |
| 18 | ARKOREAL GELEIA REAL IMUNID AMP 15ML X20 MEL [PA] PROPOLIS (BACCHARIS DRACUNCULIFOLIA) [PA] PROPOLIS (PROPOLIS CERA) [PA] POLEN [PA] GELEIA REAL [PA] EQUINACEA (ECHINACEA PURPUREA) (EXTRATO) [PA] | 34,33 € | Suplementos e vitaminas | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581471858.jpg |
| 19 | DUREX SENSITIVO SUAVE PRESERVATIVO X12 | 13,38 € | Saúde sexual e íntima | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581470825.png |
| 20 | CERAVE CORE MOIST LOCAO FACIAL PM 52G | 18,59 € | Dermocosmética | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-se-guarda/fse-4611686018581478354.jpg |

## Farmácia Teixeira (`farmacia-teixeira-guarda`) — Glovo store 461596 / address 733650

- Menu da Glovo: 14 secções, 66 categorias, 141 subsecções; subsecções lidas: 137; em falta: 4.
- Subsecções do menu sem produtos na Glovo (vazias, não é falha de leitura): sono-e-ansiedade-c.19757797 / *, suplementos-alimentares-c.19757847 / suplementacao-cabelo-e-unhas-s.22038738, suplementos-alimentares-c.19757847 / suplementacao-pediatrica-s.25363013, elixires-sprays-e-pastihas-c.19757895 / sprays-s.19758096.
- Produtos distintos na Glovo (por id): 515.
- Duplicados por nome normalizado retirados: 0. Secções de promoções/mais vendidos: não existem no menu desta loja (só `elementsWithoutMenu` = [{"slugSuffix": "pb"}, {"slugSuffix": "bc"}, {"slugSuffix": "isbc"}], ignorados).
- Produtos finais: **515**; com preço promocional: 0; marcados como medicamento: 99; parafarmácia: 416; esgotados na Glovo no momento: 0 (vão como is_available true, como pedido).
- Sem descrição na ficha da Glovo: 195.
- Fotos: com foto real, subida e provada (200 no URL público, mesmo tamanho, mesmos primeiros bytes e mesmo md5) 511; sem foto real 4. Tipos: image/jpeg 473, image/png 38 (nenhuma AVIF).
- SQL: 511 linhas em 3 INSERT (`insert_farmacia-teixeira-guarda.sql`).

Produtos SEM foto real (ficam fora do SQL; as cópias do quadro ficaram no Storage mas o JSON tem photo_url null):
- fte-4611686018581479656 — Visine , 0.5 mg/ml Frasco conta-gotas 15 ml Col, sol — estado: marcador_sem_imagem_na_glovo: quadro 'PRODUTO SEM IMAGEM DISPONÍVEL' (Nossa Farmácia)
- fte-4611686018581484407 — CAUDALIE RESVER-LIFT FIRM CAXEM REC50ML — estado: marcador_sem_imagem_na_glovo: quadro 'PRODUTO SEM IMAGEM DISPONÍVEL' (Nossa Farmácia)
- fte-4611686018581484310 — AVENE HYALURON ACTIV B3 CR REFILL 50ML — estado: marcador_sem_imagem_na_glovo: quadro 'SKIN — IMAGEM INDISPONÍVEL' (a mesma em produtos diferentes)
- fte-4611686018581484406 — CAUDALIE RESVER-LIFT FIRM CR NOITE 50ML — estado: marcador_sem_imagem_na_glovo: quadro 'PRODUTO SEM IMAGEM DISPONÍVEL' (Nossa Farmácia)

Categorias pequenas juntadas: Nutrição e controlo de peso → Suplementos e vitaminas

Categorias (ordem, nome, produtos):

1. Medicamentos sem receita — 35
2. Dor e febre — 21
3. Constipação, gripe e alergias — 35
4. Primeiros socorros — 16
5. Suplementos e vitaminas — 30
6. Bebé e mamã — 20
7. Saúde oral — 42
8. Saúde sexual e íntima — 13
9. Dermocosmética — 106
10. Higiene e cuidado pessoal — 65
11. Cabelo — 42
12. Homem — 11
13. Solares — 45
14. Maquilhagem e perfumes — 17
15. Ortopedia e bem-estar — 17

Amostra ao acaso de 20 produtos para conferir à mão:

| # | Nome | Preço Glovo | Categoria | Medicamento | Foto |
|---|---|---|---|---|---|
| 1 | Valdispert 45 mg Comprimido Revestido - X 60 Und(s) | 15,85 € | Suplementos e vitaminas | sim | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581471380.jpg |
| 2 | CAUDALIE VINOPURE LOC PURIFIC 400ML | 29,68 € | Dermocosmética | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581484172.jpg |
| 3 | CLEARBLUE TESTE GRAVID IND SEMANAS | 17,36 € | Saúde sexual e íntima | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581471719.jpg |
| 4 | Bisoltussin Tosse Seca, 2 mg/mL-200 mL x 1 sol oral mL | 12,49 € | Constipação, gripe e alergias | sim | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581470357.jpg |
| 5 | CONTROL FINISSIMO PRESERV ULTRAFEEL X10 | 11,14 € | Saúde sexual e íntima | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581471788.jpg |
| 6 | Actifed, 60/2,5 mg x 20 comp | 10,92 € | Constipação, gripe e alergias | sim | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581470097.jpg |
| 7 | Nurofen Musc 200 mg Emplastro Medicamentoso - X 4 Und(s) | 19,49 € | Dor e febre | sim | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581470815.jpg |
| 8 | CAUDALIE ANGE DES VIGNES EAU PARF 50ML | 25,65 € | Maquilhagem e perfumes | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581479795.jpg |
| 9 | CAUDALIE ROSE DE VIGNE GEL DUCHE 200ML | 7,73 € | Higiene e cuidado pessoal | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581479755.jpg |
| 10 | Homeogene 9 , Blister 60 Unidade(s) Comp | 11,59 € | Constipação, gripe e alergias | sim | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581471415.jpg |
| 11 | MAGNESIUM OK COMP X 30 PIRIDOXINA (VITAMINA B6) [PA] TOCOFEROL (VITAMINA E) [PA] ZINCO (GLUCONATO) [PA] SELENIO (LEVEDURA ENRIQUECIDA) [PA] TIAMINA (VITAMINA B1) [PA] MANGANESIO (GLUCONATO) [PA] MAGNESIO (OXIDO) [PA] RIBOFLAVINA (VITAMINA B2) [PA] CROMIO | 17,36 € | Suplementos e vitaminas | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581471972.jpg |
| 12 | LRPOSAY LIPIKAR BAUME AP+M ECO TUBE 200ML | 21,50 € | Higiene e cuidado pessoal | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581484271.jpg |
| 13 | LIERAC HOMME BALSAMO SUAV POS BARBA 75 | 21,22 € | Homem | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581477314.jpg |
| 14 | AVENE HYALURON ACTIV B3 CR REFILL 50ML | 36,62 € | Dermocosmética | não | — |
| 15 | CAUDALIE VINOPERF CR NOIT GLYC MANCH 50 | 40,21 € | Dermocosmética | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581479558.jpg |
| 16 | URIAGE BARIEDERM BALSAMO LAB 15 ML | 11,76 € | Dermocosmética | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581477292.jpg |
| 17 | VICHY FLEXITEINT 25 ANTIRUGAS 30ML | 35,00 € | Maquilhagem e perfumes | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581482279.jpg |
| 18 | URIAGE BARIESUN LEITE KIDS SPF50+100ML | 20,61 € | Solares | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581481012.jpg |
| 19 | ISDIN FOTOPROT PED F WATER SPF50 50ML | 31,58 € | Solares | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581472858.png |
| 20 | DRENASLIM COCKTAIL MORANGO STICKS X15 | 17,75 € | Suplementos e vitaminas | não | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/farmacias/farmacia-teixeira-guarda/fte-4611686018581479796.jpg |
