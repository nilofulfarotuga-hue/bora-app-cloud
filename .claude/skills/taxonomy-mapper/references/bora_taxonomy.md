# Bora Taxonomy — 18 Secções Canónicas

Este documento é a fonte única de verdade para a classificação de produtos de supermercado na Bora App. Cada secção tem:

- **ID canónico** (1-18)
- **Nome canónico** (string exacta a escrever em `products.taxonomy_section`)
- **Keywords PT** (para matching em `products.name`)
- **Mapeamento por `category_root`** (padrões comuns dos retalhistas)
- **Anti-keywords** (palavras que desqualificam)

---

## 1. Padaria & Pastelaria

**Canónico:** `Padaria & Pastelaria`

**Keywords (name):**
pão, paozinho, pao-de-forma, pão-de-forma, baguete, cacete, papo-seco, broa, carcaça, bolacha tostada, tosta, croissant, pain-au-chocolat, pastel de nata, pastel-de-nata, pastel-de-belem, bolo, bolinho, queque, muffin, donut, rosquinha, folhado, torta, palmier, suspiro, bolo-rei, bolo rainha, mil-folhas, éclair, eclair, profiterole, tarte

**category_root contains:** `padaria`, `pastelaria`, `bakery`, `pao`, `pão`, `bolos`, `pastelarias`

**Anti-keywords:** `congelada` (→ vai para Congelados), `cereais` (→ Mercearia), `bolacha maria` (→ Mercearia, é snack doce)

---

## 2. Frutas & Legumes

**Canónico:** `Frutas & Legumes`

**Keywords (name):**
maçã, maca, pera, banana, laranja, tangerina, clementina, limão, limao, lima, morango, uva, kiwi, manga, ananás, ananas, pêssego, pessego, nectarina, ameixa, cereja, melancia, melão, melao, abacate, figo, romã, roma, framboesa, mirtilo, amora, coco, dióspiro, diospiro, maracujá, maracuja, alface, tomate, pepino, cebola, alho, cenoura, batata, batata-doce, abóbora, abobora, courgette, beringela, beringela, brócolos, brocolos, couve, couve-flor, espinafres, rúcula, rucula, aipo, alho-francês, alho-frances, alho frances, beterraba, nabo, rabanete, pimento, pimentão, pimentao, ervilha, feijão-verde, feijao-verde, milho (fresco), cogumelo, cogumelos, cogumelo-paris, champignon, salsa, coentros, manjericão, manjericao, hortelã, hortela

**category_root contains:** `frutas`, `legumes`, `hortícolas`, `horticolas`, `produce`, `fruits`, `vegetables`, `frutas-e-legumes`, `fruta`, `vegetais`

**Anti-keywords:** `congelad`, `em conserva`, `lata`, `sumo`, `compota`, `desidratad`

---

## 3. Talho

**Canónico:** `Talho`

**Keywords (name):**
carne, vaca, vitela, porco, leitão, leitao, frango, galinha, peru, pato, borrego, cordeiro, coelho, cabrito, javali, veado, perdiz, chouriço, chourico, salsicha, salsichas, bacon, fiambre, paio, linguiça, linguica, morcela, farinheira, alheira, chispe, presunto, lombinho, lombo, costeleta, bife, entrecôte, entrecote, picanha, acém, acem, vazia, perna (carne), peito (frango), asa (frango), coxa, cachaço, cachaco, rojões, rojoes, febras, secretos, plumas, entremeada, carne-picada, hambúrguer (fresco), hamburguer (fresco), almôndegas, almondegas, espetada

**category_root contains:** `talho`, `carne`, `meat`, `butcher`, `carnes`, `carnes-frescas`, `charcutaria`

**Anti-keywords:** `congelad`, `lata` (conserva), `seco` (enchidos secos — estes ficam em Talho), `pate` (→ Mercearia)

---

## 4. Peixaria

**Canónico:** `Peixaria`

**Keywords (name):**
peixe, peixaria, bacalhau, sardinha, sardinhas, atum (fresco), salmão, salmao, dourada, robalo, pescada, tamboril, linguado, maruca, cherne, garoupa, corvina, polvo, choco, chocos, lula, lulas, camarão, camarao, gamba, gambas, lagostim, lagosta, caranguejo, sapateira, ostra, mexilhão, mexilhao, amêijoa, ameijoa, berbigão, berbigao, vieira, lingueirão, lingueirao, percebe, navalheira

**category_root contains:** `peixaria`, `peixe`, `peixes`, `marisco`, `fish`, `seafood`, `peixe-e-marisco`

**Anti-keywords:** `congelad`, `lata` (→ Mercearia, se atum/sardinha em conserva), `seco` (bacalhau seco é OK, fica em Peixaria)

**Nota especial:** Bacalhau salgado/seco → Peixaria. Bacalhau em lata → Mercearia.

---

## 5. Laticínios & Ovos

**Canónico:** `Laticínios & Ovos`

**Keywords (name):**
leite, iogurte, yogurt, queijo, queijinho, manteiga, margarina, nata, natas, creme-de-leite, kefir, requeijão, requeijao, mascarpone, ricota, mozzarella, mozarela, cheddar, gouda, emmental, parmesão, parmesao, feta, flamengo, ilha, serra, azeitão, azeitao, ovo, ovos, ovos-caseiros, clara-de-ovo, quark, skyr, pudim, arroz-doce (refrigerado), sobremesa-láctea, sobremesa-lactea

**category_root contains:** `laticínios`, `laticinios`, `lácteos`, `lacteos`, `dairy`, `ovos`, `queijo`, `leite`, `iogurte`, `charcutaria` (parcial — precisa co-ocorrência)

**Anti-keywords:** `soja` sozinho sem `leite-de-soja` (bebidas vegetais vão para Bebidas se rotuladas como drink; se for iogurte de soja pode ficar aqui)

---

## 6. Congelados

**Canónico:** `Congelados`

**Keywords (name):**
congelad, congeladas, congelados, gelado, gelados, ice-cream, sorbet, pizza-congelada, nuggets-congelados, legumes-congelados, bacalhau-congelado, filete-congelado, polvo-congelado, brócolos-congelados, lasanha-congelada, batata-frita-congelada, palitos-congelados

**category_root contains:** `congelad`, `frozen`, `ultracongelad`, `gelad`

**Anti-keywords:** (nenhuma — a palavra "congelado" no nome é decisiva)

**Nota:** Esta secção tem precedência sobre Talho/Peixaria/Frutas&Legumes. Se o produto estiver congelado, vai para Congelados mesmo que seja peixe, carne ou legume.

---

## 7. Mercearia

**Canónico:** `Mercearia`

**Keywords (name):**
massa, esparguete, macarrão, macarrao, penne, fusilli, farfalle, tagliatelle, lasanha (seca), arroz, arroz-basmati, arroz-carolino, arroz-agulha, farinha, sêmola, semola, açúcar, acucar, sal, especiaria, pimenta, canela, noz-moscada, oregãos, oregaos, tomilho, alecrim, louro, caril, açafrão, acafrao, colorau, mostarda, maionese, ketchup, molho, azeite, óleo, oleo, vinagre, vinagrete, café, cafe, chá, cha, cereal, cereais, flocos, granola, aveia, muesli, leite-condensado, bolacha, biscoito, snack, batata-frita (saco), tortilha, chips, chocolate, tablete, bombom, bombons, rebuçado, rebucado, gomas, chiclete, pastilha-elástica, pastilha-elastica, goma, gummy, conserva, enlatad, lata, atum-em-lata, sardinha-em-lata, feijão-lata, feijao-lata, grão-lata, grao-lata, ervilha-lata, milho-lata, tomate-enlatado, ananás-lata, ananas-lata, compota, geleia, mel, pepita, bebida-pó (instantânea), leite-po, frutos-secos, amêndoa, amendoa, noz, avelã, avela, caju, pistáchio, pistachio, passas, tâmara, tamara, figo-seco, ameixa-seca

**category_root contains:** `mercearia`, `grocery`, `grocery-staples`, `despensa`, `pantry`, `secos`, `conservas`, `cereais`, `massas`, `arroz`, `especiarias`, `óleos`, `oleos`, `bolachas`, `snacks`, `chocolates`, `doces`, `cafés`, `cafes`, `chás`, `chas`

**Anti-keywords:** `congelad`, `bio` + root bio (→ Bio & Saudável), `whey`, `protein-bar` (→ Fitness), `bebé` (→ Bebé), `cão`, `gato` (→ Animais)

---

## 8. Bebidas

**Canónico:** `Bebidas`

**Keywords (name):**
água, agua, água-mineral, agua-mineral, água-com-gás, agua-com-gas, sumo, sumos, néctar, nectar, refrigerante, coca-cola, pepsi, sprite, fanta, 7up, ice-tea, iced-tea, chá-gelado, cha-gelado, red-bull, monster, bebida-energética, bebida-energetica, vinho, tinto, branco, rosé, rose, verde (vinho), vinho-do-porto, porto, champanhe, espumante, prosecco, cava, cerveja, cervejas, sagres, super-bock, heineken, budweiser, corona, sidra, hidromel, whisky, whiskey, vodka, gin, ron, rum, tequila, bagaço, bagaco, aguardente, ginja, licor, brandy, conhaque, cognac, cápsula-café, capsula-cafe, nespresso, dolce-gusto

**category_root contains:** `bebidas`, `beverages`, `drinks`, `águas`, `aguas`, `sumos`, `refrigerantes`, `vinhos`, `cervejas`, `espirituosas`, `álcool`, `alcool`, `champanhes`, `espumantes`

**Anti-keywords:** `congelad`, `leite` sozinho (→ Laticínios), `whey` (→ Fitness), `bebé` (→ Bebé)

---

## 9. Bebé

**Canónico:** `Bebé`

**Keywords (name):**
fralda, fraldas, pampers, dodot, huggies, toalhitas-bebé, toalhitas-bebe, papa, papinha, boião, boiao (bebé), leite-bebé, leite-bebe, fórmula-infantil, formula-infantil, nan, aptamil, nestum, biberão, biberao, chupeta, chucha, chuchas, lenços-bebé, lencos-bebe, baba, babete, esparadrapo-bebé, pomada-fraldas

**category_root contains:** `bebé`, `bebe`, `bebes`, `baby`, `infantil`, `infantis`, `puericultura`

---

## 10. Animais

**Canónico:** `Animais`

**Keywords (name):**
ração, racao, ração-cão, racao-cao, ração-gato, racao-gato, ração-cachorro, royal-canin, whiskas, friskies, felix, purina, pro-plan, hills, advance-pet, petisco-cão, petisco-cao, brinquedo-cão, brinquedo-cao, coleira, trela, guia (animal), caixa-areia, areia-gato, tapete-higiénico, tapete-higienico, petisco-gato, snack-cão, snack-cao, aquário, aquario, peixe-ornamental, gaiola, roedor, hamster

**category_root contains:** `animais`, `animal`, `pet`, `pets`, `cão`, `cao`, `gato`, `cães`, `caes`, `gatos`, `roedores`, `aves` (domésticas — ambíguo, precisa co-ocorrência com "ornamental"), `mundo-animal`

---

## 11. Higiene Pessoal

**Canónico:** `Higiene Pessoal`

**Keywords (name):**
champô, champo, shampoo, amaciador, condicionador, gel-duche, gel-banho, sabonete, sabão-pessoal, sabao-pessoal, pasta-dentes, pasta-dentífrica, pasta-dentifrica, dentífrica, dentifrica, escova-dentes, fio-dentário, fio-dentario, colutório, colutorio, elixir-dentário, elixir-dentario, desodorizante, antitranspirante, creme-hidratante, loção, locao, loção-corporal, locao-corporal, óleo-corporal, oleo-corporal, máscara-facial, mascara-facial, sérum, serum, batom, rímel, rimel, máscara-pestanas, mascara-pestanas, base-maquilhagem, pó-compacto, po-compacto, blush, corretor, lápis-de-olhos, lapis-de-olhos, eyeliner, esmalte, verniz-unhas, lima-unhas, corta-unhas, pinça, pinca, depilação, depilacao, cera-depilatória, cera-depilatoria, lâmina-barbear, lamina-barbear, gillette, gel-barbear, after-shave, aftershave, perfume, eau-de-toilette, eau-de-parfum, protector-solar, protetor-solar, papel-higiénico (PARCIAL → ver Higiene do Lar), pensos-higiénicos, pensos-higienicos, tampão-higiénico, tampao-higienico, copo-menstrual

**category_root contains:** `higiene-pessoal`, `higiene`, `beleza`, `cosmética`, `cosmetica`, `beauty`, `cosmetics`, `perfumaria`, `perfumes`, `maquilhagem`, `capilar`, `corpo`, `rosto`, `dental`

**Anti-keywords:** `bebé`, `bebe` (→ Bebé)

---

## 12. Higiene do Lar

**Canónico:** `Higiene do Lar`

**Keywords (name):**
detergente, detergente-roupa, detergente-loiça, detergente-louca, amaciador-roupa, amaciador-tecidos, lixívia, lixivia, desinfectante, desinfetante, lava-tudo, multiusos, multi-usos, papel-higiénico, papel-higienico, papel-cozinha, guardanapo, guardanapos, toalhetes (limpeza), rolo-cozinha, saco-lixo, saco-congelar, alumínio (folha), aluminio, película-aderente, pelicula-aderente, desinfectante-mão, desinfetante-mao, ambientador, insecticida, inseticida, mata-moscas, inseto-cida, lustra-móveis, lustra-moveis, cera-chão, cera-chao, anti-calcário, anti-calcario, destapa-canos, ajax, cif, fairy, skip, persil, omo, finish, cotonetes, disco-algodão, disco-algodao, algodão-hidrófilo, algodao-hidrofilo

**category_root contains:** `higiene-do-lar`, `higiene-lar`, `limpeza`, `cleaning`, `household`, `casa`, `lar`, `produtos-limpeza`, `detergentes`

---

## 13. Saúde & Bem-Estar

**Canónico:** `Saúde & Bem-Estar`

**Keywords (name):**
vitamina, vitaminas, multivitamínico, multivitaminico, suplemento (sem proteína), magnésio, magnesio, cálcio, calcio, ferro, zinco, ómega-3, omega-3, coenzima-q10, probiótico, probiotico, paracetamol, ben-u-ron, aspirina, ibuprofeno, brufen, lasolvan, xarope, xarope-tosse, pastilha-garganta, soro-fisiológico, soro-fisiologico, penso-rápido, penso-rapido, band-aid, compressa, ligadura, adesivo, álcool-etílico, alcool-etilico, termómetro, termometro, tensiómetro, tensiometro, dispositivo-médico, farmácia, farmacia, teste-gravidez, preservativo, lubrificante-íntimo, lubrificante-intimo, spray-nasal, gotas-ouvidos, gotas-nasais, pomada, creme-hidratante-medicinal, hidratante-medicinal

**category_root contains:** `saúde`, `saude`, `health`, `farmácia`, `farmacia`, `pharmacy`, `suplementos`, `bem-estar`, `medicamentos`, `parafarmácia`, `parafarmacia`

**Anti-keywords:** `whey`, `protein`, `fitness`, `desporto` (→ Fitness & Proteínas), `bio` (→ Bio & Saudável, se for essa a identidade)

---

## 14. Bio & Saudável

**Canónico:** `Bio & Saudável`

**Keywords (name):**
bio, biológico, biologico, orgânico, organico, organic, eco, ecológico, ecologico, sustentável, sustentavel, fairtrade, fair-trade, sem-glúten, sem-gluten, gluten-free, vegan, vegano, vegetariano, sem-lactose, lactose-free, sem-açúcar, sem-acucar, sugar-free, natural (parcial — precisa co-ocorrência), raw, cru, superalimento, superfood, spirulina, chlorella, maca-peruana, acai, chia, quinoa, linhaça, linhaca, sementes-cânhamo, sementes-canhamo

**category_root contains:** `bio`, `biologico`, `organico`, `organic`, `saudável`, `saudavel`, `sem-glúten`, `sem-gluten`, `vegan`, `vegetarian`, `natural`, `superfoods`

**Nota:** Esta secção tem precedência sobre Mercearia quando houver selo bio/organic evidente no nome. Se for só "arroz-bio" → Bio & Saudável. Se for "arroz basmati" → Mercearia.

---

## 15. Fitness & Proteínas

**Canónico:** `Fitness & Proteínas`

**Keywords (name):**
whey, whey-protein, proteína, proteina, protein, caseína, caseina, casein, bcaa, creatina, creatine, pré-treino, pre-treino, preworkout, pre-workout, barra-proteica, protein-bar, shaker, shake-proteína, shake-proteina, ganhar-massa, queimador-gordura, fat-burner, l-carnitina, carnitina, glutamina, beta-alanina, isolate, hidrolisada, concentrado-proteico, ganho-muscular, iso-100, gold-standard, optimum-nutrition, myprotein, scitec, bulk, nutripharma-fitness

**category_root contains:** `fitness`, `desporto-suplementos`, `sports-nutrition`, `sports`, `musculação`, `musculacao`, `nutrição-desportiva`, `nutricao-desportiva`, `proteínas`, `proteinas`

---

## 16. Pronto a Comer

**Canónico:** `Pronto a Comer`

**Keywords (name):**
sandes (pronta), sanduíche-pronta, sanduiche-pronta, wrap (pronto), salada-pronta, refeição-pronta, refeicao-pronta, sushi (take-away), take-away, pronto-a-comer, ready-to-eat, esparguete-à-bolonhesa (refrigerado), arroz-de-marisco (refrigerado), bacalhau-à-brás (refrigerado), bacalhau-a-bras (refrigerado), frango-assado, pizza (fresca, não congelada), lasanha (refrigerada), sopa (fresca), empadão (fresco), empadao

**category_root contains:** `pronto-a-comer`, `ready-to-eat`, `take-away`, `refeições-prontas`, `refeicoes-prontas`, `pratos-do-dia`

**Anti-keywords:** `congelad` (→ Congelados)

---

## 17. Festa & Ocasiões

**Canónico:** `Festa & Ocasiões`

**Keywords (name):**
vela-aniversário, vela-aniversario, velas-aniversário, velas-aniversario, balão, balao, balões, baloes, chapéu-festa, chapeu-festa, apito-festa, cornetas-festa, pinhata, piñata, confete, serpentina, guardanapo-festa, prato-descartável, prato-descartavel, copo-descartável, copo-descartavel, talher-descartável, talher-descartavel, toalha-mesa-papel, decoração-aniversário, decoracao-aniversario, decoração-natal, decoracao-natal, presente-embrulho, papel-presente, fita-presente, laço-presente, laco-presente

**category_root contains:** `festa`, `festas`, `aniversário`, `aniversario`, `party`, `celebration`, `ocasiões`, `ocasioes`, `decoração`, `decoracao`

---

## 18. Outros

**Canónico:** `Outros`

**Uso:** Rede de segurança. Recebe:
- Lâmpadas, pilhas, carregadores, cabos
- Artigos de escritório genéricos (quando não é categoria própria)
- Produtos sem keyword match E sem `category_root` mapeado E com LLM confidence < 0.50
- Miscelânea não-alimentar não classificável

**Keywords (name):** lâmpada, lampada, pilha, pilhas, bateria, carregador, cabo-usb, carregador-telemóvel, carregador-telemovel, vela (não-festa), fósforo, fosforo, isqueiro, guarda-chuva, lanterna

**category_root contains:** `outros`, `diversos`, `other`, `miscelânea`, `miscelanea`

---

## Mapeamento Directo por `category_root` (Heurísticas Comuns)

Tabela de atalhos quando o `category_root` é identificável:

| Pattern em `category_root`           | → Secção                 | Confidence |
|--------------------------------------|--------------------------|-----------|
| `%padaria%` / `%bakery%`             | Padaria & Pastelaria     | 0.80      |
| `%frutas%` / `%legumes%` / `%produce%` | Frutas & Legumes       | 0.85      |
| `%talho%` / `%carne%` / `%meat%`     | Talho                    | 0.85      |
| `%peixaria%` / `%peixe%` / `%fish%`  | Peixaria                 | 0.85      |
| `%laticínios%` / `%dairy%` / `%queijo%` / `%iogurt%` | Laticínios & Ovos | 0.85 |
| `%congelad%` / `%frozen%` / `%gelad%` | Congelados              | 0.90      |
| `%mercearia%` / `%grocery%`          | Mercearia                | 0.70      |
| `%bebida%` / `%beverage%` / `%vinho%` / `%cerveja%` / `%água%` | Bebidas | 0.85 |
| `%bebé%` / `%bebe%` / `%baby%`       | Bebé                     | 0.90      |
| `%animal%` / `%pet%`                 | Animais                  | 0.90      |
| `%higiene-pessoal%` / `%beleza%` / `%cosmética%` | Higiene Pessoal | 0.85 |
| `%higiene-lar%` / `%limpeza%` / `%cleaning%` | Higiene do Lar     | 0.85      |
| `%saúde%` / `%farmácia%` / `%pharmacy%` | Saúde & Bem-Estar    | 0.80      |
| `%bio%` / `%organic%` / `%natural%` / `%vegan%` | Bio & Saudável  | 0.80      |
| `%fitness%` / `%sports-nutrition%` / `%proteína%` | Fitness & Proteínas | 0.85 |
| `%pronto-a-comer%` / `%ready-to-eat%` / `%take-away%` | Pronto a Comer | 0.85 |
| `%festa%` / `%party%` / `%aniversário%` | Festa & Ocasiões     | 0.80      |
| (qualquer outro)                     | Outros (com needs_review) | 0.20     |

---

## Regras de Precedência Final (v2 — pós-correcções)

1. **Congelados ganha sempre** — `congelad`/`frozen`/`gelad`/`ultracongelad`/`surgelé`/`helado` ganha sobre qualquer outra secção.
2. **Pet-context ganha sobre Talho/Peixaria/Mercearia/Laticínios** — se `name` contiver "cão", "gato", "cachorro", "ração", "pet", "snack para cão", "vitakraft", "para gato", etc. → Animais. Resolve "Comida Seca Gato Peru" (era Talho), "Snack para Cão Linguiça" (era Talho).
3. **Bebé ganha sobre Laticínios** — "leite-bebé" → Bebé.
4. **Bebé ganha sobre Saúde** — "fralda" sem qualificador → Bebé. "fralda adulto"/"incontinência"/"tena" → Saúde.
5. **Fitness ganha sobre Saúde** — whey/bcaa/creatina/protein → Fitness.
6. **Bio só ganha sobre Mercearia** — vinho-bio → Bebidas; ovos-bio → Laticínios; arroz-bio → Bio.
7. **Talho/Peixaria ganham sobre Mercearia** — produtos frescos têm precedência sobre root "Mercearia" genérico.
8. **Keyword distintiva vence keyword ambígua** — se "geleia" (Mercearia distinctive) + "hortelã" (Frutas ambíguo) → Mercearia.
9. **Root ≥ 0.85 vence keyword_weak quando divergem** — "Sumo de Laranja" com root Bebidas → Bebidas (não Frutas via "laranja").
10. **Keyword distintiva (1 match) = confidence 0.88 no review** — evita ruído de revisão em casos óbvios.

## Keywords Multilingue (v2)

Adicionadas para cobrir Intermarché (FR), Auchan (FR/EN), Lidl (EN/vários), Mercadona (ES), Pingo Doce (PT), Continente (PT):

| Secção | FR | EN | ES | PT-BR |
|--------|-----|-----|-----|-------|
| Padaria | pain, brioche, gateau, tartelette | bread, cake, pastry | pan, bollo | — |
| Frutas & Legumes | fruit, légume, pomme, fraise, carotte, oignon, salade | apple, grape, tomato, onion | manzana, fresa, lechuga, verdura, fruta | — |
| Talho | viande, boeuf, poulet, porc, jambon, saucisse, rillettes, pâté | beef, pork, chicken, turkey, ham | carne, ternera, pollo, jamón, chorizo | — |
| Peixaria | poisson, morue, saumon, thon, crevette | fish, cod, salmon, tuna, shrimp | pescado, atún, gamba, bacalao | — |
| Laticínios | lait, yaourt, fromage, beurre, crème, œuf, bifidus, paturages | milk, yogurt, cheese, butter, egg | leche, queso, yogur, huevo | — |
| Congelados | surgelé | frozen, ice-cream | helado, ultracongelada | — |
| Mercearia | pasta, sauce, riz, huile, farine, miel, biscuit | rice, flour, sugar, honey | aceite, vinagre, arroz, galleta | bala |
| Bebidas | eau, jus, vin, bière | water, juice, wine, beer | agua, zumo, vino, cerveza | suco |

## Roots Ambíguos (v2) — Força LLM

Roots sem mapeamento fiável → `classify_by_root` devolve `None` → cai em `fallback` → LLM:

- **Frescos** (2.118 produtos) — pode ser fruta, legume, peixe, carne, laticínio
- **Gastronomia** (192) — pode ser mercearia, pronto-a-comer, charcutaria
- **Regional** (129) — qualquer categoria regional PT
- **Casa** / **Casa e Lar** — ambíguo Higiene Lar vs Outros

Estimativa: ~2.500 produtos (5,8%) forçados para LLM.

## Keywords Distintivas (v2)

Keywords que, quando aparecem 1 vez, dão confidence 0.88 (bypass review). Lista completa em `scripts/classify.py` dict `DISTINCTIVE_KEYWORDS`. Resumo por secção:

- **Padaria**: pão, croissant, pastel-de-nata, baguete
- **Frutas & Legumes**: abacate, banana, maçã, morango, kiwi, ananás, manga, alface, brócolos, cenoura
- **Talho**: bacon, fiambre, chouriço, presunto, costeleta, picanha
- **Peixaria**: bacalhau, sardinha, polvo, camarão, gamba, mexilhão
- **Laticínios**: iogurte, queijo, manteiga, natas, bifidus, kefir, mozzarella
- **Congelados**: congelad, gelado, ultracongelad, frozen
- **Mercearia**: vinagre, azeite, arroz, massa, café, açúcar, farinha, coco-ralado, geleia, compota, mel, ketchup, maionese
- **Bebidas**: coca-cola, sagres, vinho, cerveja, sumo, suco, nespresso, whisky, champanhe
- **Bebé**: pampers, dodot, huggies, nestum, aptamil, chupeta, biberão, fralda-bebé, "bebé ", "para bebé"
- **Animais**: royal-canin, whiskas, friskies, ração, vitakraft, coleira
- **Higiene Pessoal**: champô, desodorizante, pasta-dentes, pensos-higiénicos
- **Higiene do Lar**: detergente, lixívia, papel-higiénico, papel-cozinha
- **Saúde**: paracetamol, ibuprofeno, vitamina, fralda-adulto, incontinência, tena
- **Bio**: biológico, orgânico, sem-glúten, vegan
- **Fitness**: whey, bcaa, creatina, isolate, myprotein

---

## Plano de Revisão Manual

Após classificação automática, o Danilo revê:
- TOP 20 produtos com menor `taxonomy_confidence`
- Amostragem aleatória de 50 produtos por secção (>5% de erro por amostra → reclassificar secção)
- Todos os produtos com `needs_review = true` e score de confidence ≥ 0.50 (revisão rápida)
