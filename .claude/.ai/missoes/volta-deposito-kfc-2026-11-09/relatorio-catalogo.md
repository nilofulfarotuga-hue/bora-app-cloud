# Volta — marcação do catálogo e KFC (missão volta-deposito-kfc-2026-11-09)

Catálogo lido a 09/11/2026 21:03 (56.986 linhas: produtos ativos + opções dos menus) e classificado no PGlite com a função `volta_classificar` da PARTE 1 — a mesma que o passo 3 corre em produção.

## Por loja

| Loja | Parceiro | Marcados | Embalagens | Rever (duvidosos) | Excluídos | Opções de menu marcadas |
|---|---|---|---|---|---|---|
| KFC | não | 511 | 511 | 109 | 0 | 497 |
| Continente | não | 321 | 575 | 441 | 2423 | 0 |
| Intermarché | não | 212 | 450 | 150 | 501 | 0 |
| Auchan | não | 156 | 164 | 161 | 88 | 0 |
| Pingo Doce | não | 75 | 101 | 111 | 60 | 0 |
| Mr Kebab & Restaurant | sim | 29 | 29 | 160 | 0 | 13 |
| Jyosmi Sushi | não | 25 | 25 | 9 | 5 | 8 |
| Pôr do Sol Kebab & Pizza House | não | 24 | 24 | 99 | 0 | 22 |
| McDonald's | não | 22 | 22 | 0 | 205 | 22 |
| Fuku Sushi | não | 11 | 11 | 1 | 0 | 0 |
| Sabores de Casa Açaí | sim | 5 | 5 | 8 | 0 | 0 |
| Boom! Burger | sim | 1 | 1 | 24 | 0 | 0 |
| Sabores do Brasil - Keli Barbosa | sim | 0 | 0 | 3 | 0 | 0 |
| Burger King | não | 0 | 0 | 0 | 530 | 0 |
| Goola Açaí | sim | 0 | 0 | 4 | 0 | 0 |
| Leonidas Chocolates Guarda | não | 0 | 0 | 0 | 16 | 0 |
| Lidl | não | 0 | 0 | 1 | 4 | 0 |
| Natur House Guarda | não | 0 | 0 | 1 | 0 | 0 |
| Pizza Hut | não | 0 | 0 | 7 | 0 | 0 |

## Motivos

| Estado | Motivo | N |
|---|---|---|
| duvidoso | garrafa_pequena_pode_ser_vidro | 513 |
| duvidoso | refrigerante_sem_embalagem | 270 |
| duvidoso | sumo_pode_ser_cartao_ou_vidro | 244 |
| duvidoso | alcool_sem_lata_pode_ser_vidro | 208 |
| duvidoso | agua_sem_embalagem | 48 |
| duvidoso | agua_com_gas_pequena_pode_ser_vidro | 6 |
| excluido | excluido_vinho | 2023 |
| excluido | copos_burger_king | 484 |
| excluido | excluido_espumante | 206 |
| excluido | copos_mcdonalds | 195 |
| excluido | excluido_whisky | 167 |
| excluido | excluido_licor | 130 |
| excluido | excluido_gin | 107 |
| excluido | excluido_moscatel | 58 |
| excluido | excluido_vegetal | 51 |
| excluido | excluido_aguardente | 47 |
| excluido | excluido_vodka | 37 |
| excluido | excluido_rum | 37 |
| excluido | excluido_champanhe | 33 |
| excluido | excluido_aperitivo | 26 |
| excluido | excluido_espirituosa | 21 |
| excluido | excluido_tequila | 17 |
| excluido | excluido_saquetas | 15 |
| excluido | excluido_leite | 15 |
| excluido | excluido_fever_tree | 14 |
| excluido | excluido_iogurte | 13 |
| excluido | excluido_garrafao | 13 |
| excluido | excluido_cachaca | 12 |
| excluido | excluido_martini | 12 |
| excluido | excluido_concentrado | 11 |
| excluido | excluido_porto | 11 |
| excluido | excluido_royal_bliss | 10 |
| excluido | excluido_gelo | 10 |
| excluido | excluido_cognac | 8 |
| excluido | mais_de_3_litros | 7 |
| excluido | excluido_brandy | 7 |
| excluido | excluido_whiskey | 5 |
| excluido | excluido_vermute | 5 |
| excluido | excluido_ucal | 3 |
| excluido | excluido_vidro | 3 |
| excluido | excluido_brick | 3 |
| excluido | excluido_tinta | 2 |
| excluido | excluido_champagne | 2 |
| excluido | excluido_soja | 2 |
| excluido | excluido_tetra | 2 |
| excluido | excluido_lactea | 2 |
| excluido | excluido_armagnac | 2 |
| excluido | excluido_vinagre | 1 |
| excluido | excluido_tequilla | 1 |
| excluido | excluido_xarope | 1 |
| excluido | excluido_aveia | 1 |
| marcar | lata | 391 |
| marcar | refrigerante_lata_ou_pet | 337 |
| marcar | agua_garrafa | 296 |
| marcar | marca_so_em_lata | 199 |
| marcar | loja_marca_sdr | 142 |
| marcar | pet | 17 |
| marcar | sumo_garrafa_grande_pet | 10 |

## Revisão com fotos (lição de 31/10)

Amostra aleatória (semente 0.42) de 30 marcados e 30 não marcados, com foto, vista uma a uma.
Primeira versão das regras: marcados 22 certos / 7 errados / 1 duvidoso; não marcados 29 certos / 1 errado.
Os erros eram garrafas pequenas de VIDRO (água com gás 25 cl, tónicas 20 cl, Fever-Tree, Royal Bliss, Castello 6×25 cl), uma água de coco em cartão e um chá frio em plástico de 1,5 L que ficou de fora. As regras aprenderam (vidro/vidrio/glass excluem; garrafa < 33 cl sem lata/PET/SDR fica para rever; chá pronto a beber com litros conta) e a mesma amostra dá agora 59/59 (o Ginger Ale "sdr" sem foto fica marcado porque a própria loja escreve SDR; o garrafão de 6 L fica fora por lei).

| Produto | Grupo | Visto na foto | Veredicto da 1.ª versão | Nota |
|---|---|---|---|---|
| ICE TEA FUZE TEA:LIMÃO 1.5L (SDR) | marcado | plastico | certo | PET 1,5 L |
| REFRIGERANTE C/GÁS FRISUMO LARANJA PET 1.5L (SDR) | marcado | plastico | certo | PET 1,5 L |
| SUMO COMPAL FRESCO:LARANJA ALG 0.25L (SDR) | marcado | plastico | certo | garrafa de plástico com tampa de plástico; a loja marca SDR |
| Ice Tea Framboesa Lipton (emb. 2 lt) | marcado | plastico | certo | PET |
| Fanta  - Refrigerante com gás laranja, garrafa de 1,5 l | marcado | plastico | certo | PET 1,5 L |
| Água com Gás Continente (emb. 25 cl) | marcado | vidro | errado | garrafa de vidro verde com tampa metálica, rótulo diz ecoponto verde. Não leva depósito. R |
| Pepsi  - Refrigerante com gás, pack 6 x 0.33 l | marcado | lata | certo | pack de 6 latas 330 ml |
| Fever Tree  - Tonic premium indian, garrafa de 500 ml | marcado | vidro | errado | garrafa de vidro com tampa metálica dourada. Não leva depósito. |
| Refrigerante sem Gás Ananás Continente (emb. 1,5 lt) | marcado | plastico | certo | PET 1,5 L |
| Cemporcento  - Sumo natural de maçã bio, garrafa de 1 l | marcado | vidro (provável) | duvidoso | imagem é um render: gargalo de boca larga com aro grosso e tampa twist-off branca, típico  |
| RED BULL XXL SLEEK CAN 473 ML V | marcado | lata | certo | lata; a foto mostra a lata de 250 ml, não a de 473 ml (foto não bate com o tamanho, mas é  |
| Royal Bliss Mixer Berry Botella Vidrio 20cl | marcado | vidro | errado | garrafa de vidro 200 ml com cápsula metálica; o próprio nome diz 'Botella Vidrio'. Não lev |
| Água Tónica Limão Schweppes 1L | marcado | plastico | certo | PET 1 L (fundo petalóide) |
| CERVEJA HEINEKEN:LATA 0.33L (SDR) | marcado | lata | certo | lata 33 cl |
| Ginger Ale Schweppes 1 lt sdr | marcado | sem_foto | certo | sem_foto (HTTP 404). Julgado pelo nome: a própria loja marca 'sdr' e a Schweppes de 1 L vi |
| Bebida Aloé Vera Com Polpa Continente Bio (emb. 1 lt) | marcado | plastico | certo | garrafa de plástico 1 L; bebida refrescante sem gás |
| Fanta Laranja lata 33cl | marcado | lata | certo | lata 330 ml; a foto mostra um pack de 6 + uma lata, mas o produto é a lata avulsa (units 1 |
| ÁGUA SAN PELLEGRINO COM GÁS SEM SABOR PET 1L | marcado | plastico | certo | garrafa verde de PET com fundo petalóide; nome diz PET |
| Água Coco Dr.martins Bio Original 500ml | marcado | cartao | errado | embalagem de cartão (tipo Tetra Prisma com tampa). Cartão está excluído, não leva depósito |
| Refrigerante sem Gás Tropical e Cenoura Continente (emb. 1,5 lt) | marcado | plastico | certo | PET 1,5 L |
| Água Tónica Schweppes Zero 0.20l | marcado | vidro | errado | garrafa de vidro 200 ml com cápsula metálica (formato clássico Schweppes de bar). Não leva |
| Água Tónica em Lata Schweppes (emb. 25 cl) | marcado | lata | certo | lata |
| Vitalis - Água mineral sem gás, pack 6 x 1.5 l | marcado | plastico | certo | 6 garrafas PET 1,5 L |
| Castello - Água com gás, pack 6 x 0.25 l | marcado | vidro | errado | 6 garrafas de vidro 25 cl com cápsula metálica. Não leva depósito (units devia ser 0). |
| Porsi  - Água tonica, pack 6 x 0.2 l | marcado | vidro | errado | 6 garrafas de vidro 0,20 L com cápsula metálica em cesto de cartão. Não leva depósito (uni |
| Ice Tea Pêssego Continente (emb. 50 cl) | marcado | plastico | certo | PET 50 cl |
| REFRIGERANTE C/ GÁS COCA-COLA:ORIGINAL 2X1.75L (SDR) | marcado | plastico | certo | 2 garrafas PET 1,75 L |
| Luso  - Água sem gás, pack 6 x 1.5 l | marcado | plastico | certo | 6 garrafas PET 1,5 L |
| Pepsi - Refrigerante com gás, pack de 2 x 1.75 l | marcado | plastico | certo | 2 garrafas PET |
| Pepsi - Refrigerante com gás max zero, pack de 2 x 1.75 l | marcado | plastico | certo | 2 garrafas PET 1,75 L |
| Sei lá Alentejano Vinho Tinto | nao_marcado | vidro | certo | vinho em vidro: decisão certa, mas o motivo 'nao_e_bebida' está errado (é bebida, excluída |
| Casa De Paços Loureiro Reserva Vinho Verde Branco | nao_marcado | vidro | certo | vinho em vidro; motivo devia ser vinho excluído |
| Fronteira Reserva Douro Vinho Tinto | nao_marcado | vidro | certo | vinho em vidro |
| Dona Ermelinda Pinot Noir Merlot Península de Setúbal Vinho Rosé | nao_marcado | vidro | certo | vinho em vidro |
| Taboadella Touriga Nacional Reserva Dão Vinho Tinto | nao_marcado | vidro | certo | vinho em vidro |
| Dona Graça Insuspeito Grande Reserva Douro Vinho Tinto | nao_marcado | vidro | certo | vinho em vidro |
| Herdade Papa Leite Tiro No Escuro Alentejano Vinho Tinto | nao_marcado | vidro | certo | vinho em vidro |
| Casa Ermelinda Freitas Alvarinho Vinho Tinto | nao_marcado | vidro | certo | vinho em vidro (é branco, o nome diz tinto) |
| Inseparable Gin Special Edition | nao_marcado | vidro | certo | gin em vidro com rolha; espirituosa excluída |
| Poliphonia Reserva Alentejano Vinho Tinto | nao_marcado | vidro | certo | vinho em vidro |
| Quinta Maria Izabel Vinhas da Princesa Douro Vinho Branco | nao_marcado | vidro | certo | vinho em vidro |
| Cálem Vinho do Porto Special Reserve | nao_marcado | vidro | certo | vinho do Porto em vidro com caixa |
| Cerveja com Álcool Heineken (emb. 12 x 25 cl) | nao_marcado | vidro | certo | caixa de 12 garrafas de vidro 25 cl. Não leva depósito: o 'duvidoso' resolve-se para não m |
| Batuta Douro Vinho Tinto | nao_marcado | vidro | certo | vinho em vidro |
| Cerveja com Álcool Cristal (6 x 33 cl) | nao_marcado | vidro | certo | 6 garrafas de vidro castanho 33 cl. Não leva depósito: o 'duvidoso' resolve-se para não ma |
| Adega de Vila Real Grande Reserva Douro Vinho Branco | nao_marcado | vidro | certo | vinho em vidro |
| BEBIDA PLENO CHÁ VERDE E LIMÃO 1.5L | nao_marcado | plastico | errado | garrafa PET 1,5 L de chá frio pronto a beber (bebida à base de chá). Devia ser marcado, 1  |
| Casa Américo Dão Vinho Branco | nao_marcado | vidro | certo | vinho em vidro |
| Delta  - Café com cafeina solúvel, embalagem de 20g | nao_marcado | nao_bebida | certo | caixa de saquetas de café solúvel |
| Absolut Vodka | nao_marcado | vidro | certo | vodka em vidro; espirituosa excluída |
| Cemporcento  - Infusão melhores digestões, embalagem de 10 unidades | nao_marcado | nao_bebida | certo | caixa de 10 saquetas de chá para infusão |
| Jameson Whisky Irish | nao_marcado | vidro | certo | whisky em vidro |
| Talha de Argilla Alfrocheiro Alentejano Vinho Tinto | nao_marcado | vidro | certo | vinho em vidro |
| Cerveja com Álcool Mini Pack 15X20CL Super Bock | nao_marcado | vidro | certo | caixa de 15 garrafas de vidro 20 cl (mini). Não leva depósito: o 'duvidoso' resolve-se par |
| Caol Ila Whisky 25 Anos Malt | nao_marcado | vidro | certo | whisky em vidro com caixa |
| Quinta do Carmo Alentejano Vinho Tinto | nao_marcado | vidro | certo | vinho em vidro |
| Graça Da Pedra Alvarinho Vinho Verde Branco | nao_marcado | vidro | certo | vinho em vidro |
| Quinta dos Roques Dão Vinho Tinto | nao_marcado | vidro | certo | vinho em vidro |
| Noval Vinho do Porto Vintage 2016 | nao_marcado | vidro | certo | vinho do Porto em vidro |
| Água Fastio Mineral Garrafão 6l | nao_marcado | plastico | certo | garrafão de plástico 6 L, acima de 3 L: excluído |

## KFC — preços pela regra do balcão (passo-4-kfc-precos-e-opcoes.sql)

Regra: preço de balcão; sem fonte de balcão, Glovo ÷ 1,24 (rácio do talão de hoje), só para subir, nunca acima do Glovo. Glovo kfc-grd lido a 09/11 ~21:30 (191 artigos; preço sem promoção). Os 3 preços do talão de hoje ficam (Menu Kentucky BBQ 9,15, Menu Wrap Coronel 8,45, Box 6 Hotwings 6,20). Nenhum produto ficou acima do Glovo.

| Produto | Antes | Depois | Fonte |
|---|---|---|---|
| Wrap O'Cheddar | 7.22 | 7.86 | Glovo 9.75 ÷ 1,24 |
| Wrap Boxmaster | 8.10 | 9.48 | Glovo 11.75 ÷ 1,24 |
| Tower | 7.65 | 8.35 | Glovo 10.35 ÷ 1,24 |
| Kentucky BBQ | 7.51 | 8.19 | Glovo 10.15 ÷ 1,24 |
| Box Meal Mix | 11.76 | 13.23 | Glovo 16.40 ÷ 1,24 |
| 4 Profiteroles | 1.88 | 2.06 | Glovo 2.55 ÷ 1,24 |
| Wrap Kentucky BBQ | 7.51 | 8.19 | Glovo 10.15 ÷ 1,24 |
| O'Cheddar | 7.22 | 7.86 | Glovo 9.75 ÷ 1,24 |
| Box Meal Kentucky BBQ | 10.58 | 11.69 | Glovo 14.50 ÷ 1,24 |
| Box Meal Coronel | 9.76 | 10.97 | Glovo 13.60 ÷ 1,24 |
| Box Meal Tenders | 9.55 | 12.18 | Glovo 15.10 ÷ 1,24 |
| Box Meal Clássica | 9.39 | 10.48 | Glovo 13.00 ÷ 1,24 |
| Box Meal Hotwings | 8.95 | 12.02 | Glovo 14.90 ÷ 1,24 |
| Box Meal Pedaços | 8.81 | 11.69 | Glovo 14.50 ÷ 1,24 |
| Menu Bowl Arroz Ranchero | 6.65 | 7.25 | Glovo 8.99 ÷ 1,24 |
| Bowl Arroz Ranchero | 5.91 | 6.44 | Glovo 7.99 ÷ 1,24 |
| Arroz | 2.44 | 2.66 | Glovo 3.30 ÷ 1,24 |
| Menu Tower Double | 11.06 | 12.38 | Glovo 15.35 ÷ 1,24 |
| Menu Kentucky BBQ Double | 10.92 | 11.90 | Glovo 14.75 ÷ 1,24 |
| Menu O'Cheddar Double | 10.62 | 11.57 | Glovo 14.35 ÷ 1,24 |
| Menu Clássica Double | 10.10 | 10.69 | Glovo 13.25 ÷ 1,24 |
| Menu Coronel Double | 10.10 | 11.17 | Glovo 13.85 ÷ 1,24 |
| Menu O'Cheddar | 8.10 | 8.83 | Glovo 10.95 ÷ 1,24 |
| Menu Coronel | 7.58 | 8.43 | Glovo 10.45 ÷ 1,24 |
| Menu Clássica | 7.22 | 7.94 | Glovo 9.85 ÷ 1,24 |
| Menu Double Krunch Cheese | 5.88 | 6.73 | Glovo 8.35 ÷ 1,24 |
| Menu Double Krunch BBQ | 5.74 | 6.57 | Glovo 8.15 ÷ 1,24 |
| Menu Wrap Boxmaster | 8.99 | 10.44 | Glovo 12.95 ÷ 1,24 |
| Menu Wrap Veggie | 6.55 | 7.46 | Glovo 9.25 ÷ 1,24 |
| Menu Wrap O'Cheddar | 6.48 | 8.83 | Glovo 10.95 ÷ 1,24 |
| Sundae Chocolate | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Sundae Chocolate Branco | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Bucket 6 Pedaços Para 2 | 16.09 | 17.70 | Glovo 21.95 ÷ 1,24 |
| Menu 4 Pedaços | 10.02 | 10.93 | Glovo 13.55 ÷ 1,24 |
| Menu 3 Pedaços | 8.32 | 9.15 | Glovo 11.35 ÷ 1,24 |
| Menu 2 Pedaços | 6.62 | 7.22 | Glovo 8.95 ÷ 1,24 |
| Bucket 15 Hotwings Para 2 | 16.09 | 17.86 | Glovo 22.15 ÷ 1,24 |
| Menu 8 Hotwings | 8.69 | 9.64 | Glovo 11.95 ÷ 1,24 |
| Menu 5 Hotwings | 6.78 | 7.54 | Glovo 9.35 ÷ 1,24 |
| Super Bucket para 2 | 21.41 | 23.35 | Glovo 28.95 ÷ 1,24 |
| Bucket Mix | 17.73 | 19.48 | Glovo 24.15 ÷ 1,24 |
| Menu Mix | 9.58 | 10.69 | Glovo 13.25 ÷ 1,24 |
| Bucket 10 Tenders Para 2 | 16.09 | 17.86 | Glovo 22.15 ÷ 1,24 |
| Menu 6 Tenders | 8.62 | 9.48 | Glovo 11.75 ÷ 1,24 |
| Menu 4 Tenders | 6.62 | 7.22 | Glovo 8.95 ÷ 1,24 |
| Bucket 10 Tenders Veggie | 16.09 | 17.86 | Glovo 22.15 ÷ 1,24 |
| Menu 6 Tenders Veggie | 8.62 | 9.48 | Glovo 11.75 ÷ 1,24 |
| Menu 4 Tenders Veggie | 7.36 | 8.02 | Glovo 9.95 ÷ 1,24 |
| Menu Veggie Burger | 7.22 | 7.94 | Glovo 9.85 ÷ 1,24 |
| Menu Salada Veggie | 7.14 | 7.78 | Glovo 9.65 ÷ 1,24 |
| Menu Salada | 7.14 | 7.78 | Glovo 9.65 ÷ 1,24 |
| Shake Morango | 2.91 | 3.19 | Glovo 3.95 ÷ 1,24 |
| Kream Lotus Biscoff | 2.59 | 2.82 | Glovo 3.50 ÷ 1,24 |
| Kream Nocilla | 2.59 | 2.82 | Glovo 3.50 ÷ 1,24 |
| Kream Caramelo | 2.59 | 2.82 | Glovo 3.50 ÷ 1,24 |
| Kream Morango | 2.59 | 2.82 | Glovo 3.50 ÷ 1,24 |
| Kream Oreo | 2.59 | 2.82 | Glovo 3.50 ÷ 1,24 |
| Burger Junior | 2.18 | 2.38 | Glovo 2.95 ÷ 1,24 |
| Veggie Burger | 6.32 | 6.98 | Glovo 8.65 ÷ 1,24 |
| Wrap Veggie | 5.65 | 6.49 | Glovo 8.05 ÷ 1,24 |
| Salada Veggie | 5.44 | 5.93 | Glovo 7.35 ÷ 1,24 |
| Salada Coronel Receita Original | 5.44 | 5.93 | Glovo 7.35 ÷ 1,24 |
| Salada Coronel Tenders | 5.44 | 5.93 | Glovo 7.35 ÷ 1,24 |
| Salada Emmental Bites | 5.44 | 5.93 | Glovo 7.35 ÷ 1,24 |
| Wrap Junior Veggie Cheese | 2.77 | 3.02 | Glovo 3.75 ÷ 1,24 |
| Wrap Junior Veggie Clássico | 2.77 | 3.02 | Glovo 3.75 ÷ 1,24 |
| 2 Tenders Veggie | 2.63 | 2.86 | Glovo 3.55 ÷ 1,24 |
| 4 Hotwings | 3.81 | 4.15 | Glovo 5.15 ÷ 1,24 |
| 2 Pedaços de Frango | 3.77 | 4.11 | Glovo 5.10 ÷ 1,24 |
| Kentucky Fries O'Cheddar | 3.44 | 3.75 | Glovo 4.65 ÷ 1,24 |
| Kentucky Fries BBQ Bacon | 3.44 | 3.75 | Glovo 4.65 ÷ 1,24 |
| Kentucky Fries Coronel | 3.44 | 3.75 | Glovo 4.65 ÷ 1,24 |
| Super Batata | 2.91 | 3.19 | Glovo 3.95 ÷ 1,24 |
| 2 Tenders | 2.63 | 2.86 | Glovo 3.55 ÷ 1,24 |
| Batata Grande Palitos | 2.41 | 2.62 | Glovo 3.25 ÷ 1,24 |
| Molho O'Cheddar XXL | 2.21 | 2.41 | Glovo 2.99 ÷ 1,24 |
| Molho BBQ XXL | 2.21 | 2.41 | Glovo 2.99 ÷ 1,24 |
| ½ Maçaroca | 2.18 | 2.38 | Glovo 2.95 ÷ 1,24 |
| 3 Bites Ruffles | 2.18 | 2.38 | Glovo 2.95 ÷ 1,24 |
| 4 Emmental Bites | 2.18 | 2.38 | Glovo 2.95 ÷ 1,24 |
| DIP Caesar | 1.44 | 1.57 | Glovo 1.95 ÷ 1,24 |
| Azeite, Vinagre e Sal | 0.93 | 1.01 | Glovo 1.25 ÷ 1,24 |
| Dip O'Cheddar | 0.85 | 0.93 | Glovo 1.15 ÷ 1,24 |
| Dip Coronel | 0.85 | 0.93 | Glovo 1.15 ÷ 1,24 |
| DIP Maionese | 0.85 | 0.93 | Glovo 1.15 ÷ 1,24 |
| DIP Maionese Alho | 0.85 | 0.93 | Glovo 1.15 ÷ 1,24 |
| Dip Mostarda e Mel | 0.85 | 0.93 | Glovo 1.15 ÷ 1,24 |
| DIP Barbecue | 0.85 | 0.93 | Glovo 1.15 ÷ 1,24 |
| Dip Hot Chilli | 0.85 | 0.93 | Glovo 1.15 ÷ 1,24 |
| Red Bull Energy Drink | 2.18 | 2.46 | Glovo 3.05 ÷ 1,24 |
| Red Bull Zero Energy Drink | 2.18 | 2.46 | Glovo 3.05 ÷ 1,24 |
| Red Bull Tropical Energy Drink | 2.18 | 2.46 | Glovo 3.05 ÷ 1,24 |
| V Pepsi Lata | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Cerveja Lata 33cl | 1.96 | 2.26 | Glovo 2.80 ÷ 1,24 |
| V Pepsi Zero Lata | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Sumol Laranja Lata 33cl | 2.00 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Sumol Ananás Lata 33cl | 2.00 | 2.26 | Glovo 2.80 ÷ 1,24 |
| 7Up Lata 33cl | 2.00 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Ice Tea Manga Lata 33cl | 2.00 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Néctar Pêssego 30cl | 1.88 | 2.06 | Glovo 2.55 ÷ 1,24 |
| Néctar Laranja/Manga 30cl | 1.88 | 2.06 | Glovo 2.55 ÷ 1,24 |
| Bongo 8 Frutos | 1.56 | 1.69 | Glovo 2.10 ÷ 1,24 |
| Shake Gorila Menta | 2.91 | 3.19 | Glovo 3.95 ÷ 1,24 |
| Shake Gorila Morango | 2.91 | 3.19 | Glovo 3.95 ÷ 1,24 |
| Shake Gorila Tutti Frutti | 2.91 | 3.19 | Glovo 3.95 ÷ 1,24 |
| Sundae Gorila Menta | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Sundae Gorila Morango | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Sundae Gorila Tutti Frutti | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Coronel | 6.70 | 7.46 | Glovo 9.25 ÷ 1,24 |
| Wrap Coronel | 6.70 | 7.46 | Glovo 9.25 ÷ 1,24 |
| Clássica | 6.32 | 6.98 | Glovo 8.65 ÷ 1,24 |
| Wrap Clássico | 5.65 | 6.49 | Glovo 8.05 ÷ 1,24 |
| Wrap Junior Cheese | 2.77 | 3.02 | Glovo 3.75 ÷ 1,24 |
| Sundae Caramelo | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Gelatina | 1.44 | 1.57 | Glovo 1.95 ÷ 1,24 |
| Sundae Natura | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Sundae Morango | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Menu Wrap Kentucky BBQ | 6.73 | 9.15 | Glovo 11.35 ÷ 1,24 |
| Menu Wrap Clássico | 5.24 | 7.46 | Glovo 9.25 ÷ 1,24 |
| Box 6 Tenders + 1 Molho Dip | 7.22 | 8.19 | Glovo 10.15 ÷ 1,24 |
| Box 4 Pedaços | 6.84 | 8.19 | Glovo 10.15 ÷ 1,24 |
| 10 Aros de Cebola | 2.91 | 3.19 | Glovo 3.95 ÷ 1,24 |
| Água 33cl | 1.18 | 1.37 | Glovo 1.70 ÷ 1,24 |
| Shake Lotus Biscoff | 2.91 | 3.19 | Glovo 3.95 ÷ 1,24 |
| Shake Oreo | 2.91 | 3.19 | Glovo 3.95 ÷ 1,24 |
| Shake Nocilla | 2.91 | 3.19 | Glovo 3.95 ÷ 1,24 |
| Shake Caramelo | 2.91 | 3.19 | Glovo 3.95 ÷ 1,24 |
| Água sem Gás 50cl | 1.40 | 1.61 | Glovo 2.00 ÷ 1,24 |
| Sundae Lotus Biscoff | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Sundae Nocilla | 2.07 | 2.26 | Glovo 2.80 ÷ 1,24 |
| Ketchup | 0.07 | 0.08 | Glovo 0.10 ÷ 1,24 |
| Saco Takeaway | 0.21 | 0.24 | Glovo 0.30 ÷ 1,24 |

Sem preço no Glovo (ficam como estão): Box 6 Hotwings, 8 Pedaços, 12 Tenders, Menu Kids.

## KFC — no Glovo e não no Bora (ficam de fora até haver foto real e preço; estimativa Glovo ÷ 1,24)

| Produto | Glovo | Estimativa balcão |
|---|---|---|
| Bucket 8 Pedaços | 19.99 | 16.12 |
| Bucket 12 Tenders | 19.99 | 16.12 |
| Bucket 16 Hotwings | 19.99 | 16.12 |
| Bucket 70 PopCorn Chicken | 13.99 | 11.28 |
| Kentucky Fries | 4.65 | 3.75 |
| Salada Snack | 3.25 | 2.62 |
| Molhos XXL | 2.99 | 2.41 |
| Bucket For One 25 PopCorn Chicken | 7.99 | 6.44 |
| Box Meal Pandilha | 16.90 | 13.63 |
| Menu Cheetos Pandilha Double | 14.85 | 11.98 |
| Cheetos Pandilha Double | 12.85 | 10.36 |
| Menu Cheetos Pandilha | 11.45 | 9.23 |
| Cheetos Pandilha | 9.45 | 7.62 |
| Kentucky Fries Cheetos Pandilha | 4.65 | 3.75 |
| Molho Cheetos Pandilha XXL | 2.99 | 2.41 |
| Box 25 PopCorn Chicken | 5.10 | 4.11 |
| Box Meal Golden | 14.30 | 11.53 |
| Menu 4 Tenders Golden | 9.75 | 7.86 |
| 2 Tenders Golden | 4.15 | 3.35 |
| Box Meal O'Cheddar | 14.10 | 11.37 |
| Menu 2 Pedaços + 1 Opção | 11.45 | 9.23 |
| Menu Tower | 11.95 | 9.64 |
| Menu Double Krunch Clássico | 7.85 | 6.33 |
| Wrap Junior Clássico | 3.75 | 3.02 |
| Menu Super Things Burger | 6.50 | 5.24 |
| Menu Super Things Wrap | 6.50 | 5.24 |
| Menu Super Things Tenders | 6.50 | 5.24 |
| Menu Kids Burger | 5.80 | 4.68 |
| Menu Kids Wrap | 5.80 | 4.68 |
| Menu Kids Tenders | 5.80 | 4.68 |
| Menu Bowl Arroz Asiático | 8.99 | 7.25 |
| Bowl Arroz Asiático | 7.99 | 6.44 |
| Box 8 Hotwings | 10.15 | 8.19 |
| Molho Coronel XXL | 2.99 | 2.41 |
| Sanduíche Coronel | 9.25 | 7.46 |
| 9 Tenders + Pedaços OU Hot Wings + 2 Batatas + 1 Acompanhamento | 33.00 | 26.61 |
| 2 Burgers + 2 Batatas + 2 Acompanhamentos | 28.00 | 22.58 |
| 5 Tenders + Pedaços OU Hot Wings + 1 Batata + 1 Acompanhamento | 19.98 | 16.11 |
| Burger + Batata + Acompanhamento | 13.99 | 11.28 |
