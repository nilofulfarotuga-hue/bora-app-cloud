# C2 — Extras do Burger King: proposta de preços (09/11/2026)

> ISTO MEXE EM PREÇOS. Nada foi aplicado. O SQL está em `C2-extras-bk.sql` e só corre com o
> "autorizo" do Danilo.

## Resumo em uma frase

Dos 21 extras do Burger King na app, só UM tem preço de balcão provado por talão e está barato:
o "EXTRA Bacon" (0,91 € guardado, 2,50 € ao balcão). Sobe para **1,22 €** nas **65 opções** onde
aparece, porque a 2,50 € o cliente veria 2,88 € e o Glovo da Guarda cobra hoje 1,40 € — e a regra
manda nunca passar o Glovo. Os outros 20 ficam como estão (sem talão que os prove, ou já batem).

## Como a app calcula o preço do Burger King (confirmado no servidor e no código)

- O Burger King é **NÃO-parceiro**: `restaurants.is_partner = false` (`burgerking-guarda`) e o pedido
  56fa8623 tem `is_partner_store = false`.
- O extra vive em `product_option_items.price_add` (não em `products`). Grupo "Adiciona extras …".
- Margem não-parceiro `platform_settings.non_partner_markup_pct = 0.15`, somada em runtime:
  `quote_order_pricing` / `_create_order_core` cobram `ROUND(preço_base × 1,15; 2)` + `ROUND(Σ extras × 1,15; 2)`
  por unidade (em take-away não há margem). Prova real: no pedido 56fa8623 a linha do menu custou
  16,38 € = 15,24 (13,25 × 1,15) + 1,14 ((0,08 + 0,91) × 1,15).
- Por isso o preço guardado é o de BALCÃO, sem margem. O cliente vê `ROUND(price_add × 1,15; 2)`.
- `pricing_calculate` só recebe o subtotal já com a margem (taxa de serviço 0,99 €, entrega, sacos);
  não mexe no preço dos extras.

## Fontes usadas

- **Balcão (talões reais em produção)**: só há 3 talões do BK em `order_receipts_v2`.
  - a244493e (08/11, pedido 56fa8623): "EXTRA BACON 2 FATIAS" **2,50 €** (duas vezes), "Extra Alface" 0,00,
    "Com Cebola" 0,00, "Com Pepino" 0,00.
  - 4c44a23f (03/10, pedido b18d2675): "Extra Alface" 0,00, "Extra Ketchup" 0,00 (×3), "Com Ketchup/Maionese/
    Cebola/Pepino/Tomate" 0,00.
  - 53e74f60 (24/09): nunca foi lido (o Gemini deu `gemini_503`).
- **Glovo da Guarda**: no banco não há extras (`glovo_precos_restaurantes` de 23/10 só tem produtos).
  No repo: `relatorios/ANALISE_GLOVO_OPCOES_2026_06_09.md` (junho: Bacon +1,10, Bacon+Queijo +2,00,
  Queijo +0,90, Carne Whopper +2,60). Como junho está velho, li hoje às 21:08 (UTC) a página pública da loja
  `glovoapp.com/pt/pt/guarda/stores/burger-king-grd` (só leitura): Extra Bacon **1,40**, Extra Queijo + Bacon 2,20,
  Extra Queijo 1,10, Extra Carne Whopper 2,50, Extra Carne Burger 2,00, Extra Ovo 1,60, Extra Molho CBK 1,15,
  Extra Crispy Chicken / Frango Crocante 2,10, Extra Ketchup/Mostarda/Picles/Tomate 0,00.
  A proposta usa o Glovo de HOJE; com o de junho o bacon ficaria em 0,96 (cliente 1,10).
- A origem dos 0,91: os extras foram copiados do Glovo em junho com ×0,8261 (1,10 × 0,8261 = 0,91),
  ver `relatorios/FASE2_OPCOES_GLOVO_2026_06_09.md`. Não é preço de balcão.

## Regra aplicada

1. Guardar ao preço de balcão (sem margem). 2. Só subir. 3. O cliente nunca acima do Glovo da Guarda:
se `ROUND(balcão × 1,15; 2)` passa o Glovo, guarda-se o maior valor com `ROUND(valor × 1,15; 2) ≤ Glovo`.
4. Sem balcão conhecido: fica como está.

Bacon: balcão 2,50 → cliente 2,88 > Glovo 1,40 → teto: 1,22 (1,22 × 1,15 = 1,403 → 1,40; 1,23 já dá 1,41).
1,22 > 0,91, logo sobe. Combinações também ficam abaixo do Glovo (ex.: Bacon 1,22 + Queijo 0,74 = 1,96 × 1,15 = 2,25 ≤ 2,50).

## Tabela por extra (21 nomes, 515 opções do BK)

| Extra (nome na app) | opções | guardado hoje | cliente vê hoje | balcão (talão) | Glovo hoje | novo | decisão |
|---|---|---|---|---|---|---|---|
| EXTRA Bacon | 65 | 0,91 | 1,05 | **2,50** (a244493e) | 1,40 | **1,22** | sobe (teto Glovo) |
| EXTRA Alface | 47 | 0,00 | 0,00 | 0,00 (2 talões) | — | 0,00 | já bate |
| EXTRA Ketchup | 26 | 0,00 | 0,00 | 0,00 (4c44a23f) | 0,00 | 0,00 | já bate |
| EXTRA Cebola | 25 | 0,00 | 0,00 | 0,00 ("Com Cebola") | — | 0,00 | já bate |
| EXTRA Picles | 29 | 0,00 | 0,00 | 0,00 ("Com Pepino") | 0,00 | 0,00 | já bate |
| EXTRA Tomate | 37 | 0,00 | 0,00 | 0,00 ("Com Tomate") | 0,00 | 0,00 | já bate |
| EXTRA Bacon+Queijo | 65 | 1,65 | 1,90 | sem talão | 2,20 | 1,65 | fica (à parte) |
| EXTRA Queijo | 73 | 0,74 | 0,85 | sem talão | 1,10 | 0,74 | fica (à parte) |
| EXTRA Carne whopper® | 44 | 2,15 | 2,47 | sem talão | 2,50 | 2,15 | fica (à parte) |
| EXTRA Carne hambúrguer | 2 | 1,65 | 1,90 | sem talão | 2,00 | 1,65 | fica (à parte) |
| EXTRA Frango premium | 3 | 1,57 | 1,81 | sem talão | 2,10 (?) | 1,57 | fica (à parte) |
| EXTRA Ovo frito | 7 | 1,07 | 1,23 | sem talão | 1,60 | 1,07 | fica (à parte) |
| EXTRA Molho CBK | 3 | 0,66 | 0,76 | sem talão | 1,15 | 0,66 | fica (à parte) |
| EXTRA Molho Krispper | 1 | 0,50 | 0,58 | sem talão | — | 0,50 | fica (à parte) |
| EXTRA Maionese | 40 | 0,00 | 0,00 | sem talão ("Com Maionese" 0,00 não é extra) | — | 0,00 | fica |
| EXTRA Cebola frita | 17 | 0,00 | 0,00 | sem talão | — | 0,00 | fica |
| EXTRA Molho barbecue | 11 | 0,00 | 0,00 | sem talão | — | 0,00 | fica |
| EXTRA Molho de Cheddar | 6 | 0,00 | 0,00 | sem talão | — | 0,00 | fica |
| EXTRA Molho Sriracha | 5 | 0,00 | 0,00 | sem talão | — | 0,00 | fica |
| EXTRA Molho big king | 5 | 0,00 | 0,00 | sem talão | — | 0,00 | fica |
| EXTRA Mostarda | 4 | 0,00 | 0,00 | sem talão | 0,00 | 0,00 | fica |

"(?)": o Glovo não tem "Frango premium"; o mais parecido é "Extra Crispy Chicken"/"Extra Frango Crocante" 2,10.

**Total:** 1 extra sobe, 65 opções, de 0,91 € para 1,22 € guardado (cliente de 1,05 € para 1,40 €,
+0,35 € por bacon). A Bora continua a perder 1,10 € por bacon ao balcão (paga 2,50, recebe 1,40), menos
0,35 € do que hoje — é o preço de não passar o Glovo.

Extras sem preço de balcão conhecido (ficam como estão, para um talão futuro ou para o preço oficial do
site do BK, fonte `balcao_oficial`): Bacon+Queijo, Queijo, Carne whopper®, Carne hambúrguer, Frango premium,
Ovo frito, Molho CBK, Molho Krispper, Maionese, Cebola frita, Molho barbecue, Molho de Cheddar,
Molho Sriracha, Molho big king, Mostarda.

## As 65 opções "EXTRA Bacon" que sobem (produto id | nome | opção = id do produto + sufixo)

Todas hoje a 0,91 € → 1,22 €; balcão 2,50 €; Glovo 1,40 €. "(indisp.)" = produto `is_available = false`.

```
bk-bf337a76-6726-4353-8f2f-4b9f0e45f397 | Big King® | -g1-i6
bk-e9d5e441-f9ab-4852-af91-f446e91c546c | Big King® | -g1-i6
bk-0a5d592a-32c1-4eb0-b42b-ac3fa9e62caf | Big King® Chicken (indisp.) | -g1-i6
bk-99ab0243-679b-474c-8e0f-c30aeaa1eb49 | Big King® Frango Menu | -g4-i6
bk-71a5156b-eea1-4237-ad12-d2f8e31f1c35 | CBK | -g1-i3
bk-9ab57f0f-d87d-4740-b8cf-7958d0831fb8 | CBK | -g1-i3
bk-adb3aeb7-2e64-475a-8847-0a0595eb9960 | Chicken Krispper® | -g1-i4
bk-18380944-05cf-4508-b71b-9fe0bb9bd784 | Chicken Krispper® Spicy Menu + King Fusion™ (indisp.) | -g5-i0
bk-d5ab4cce-3730-432d-9dcc-433cd81196c1 | Cowboy (indisp.) | -g1-i2
bk-095302ea-7f24-4937-ba00-2107569e5a9e | Cowboy Crispy Chicken® (indisp.) | -g1-i1
bk-8f08853b-09a9-42e0-afb8-40a343b01982 | Cowboy Double Crispy Chicken® (indisp.) | -g1-i1
bk-1363e0b3-500a-47f6-854a-b87695d7e5c8 | Crispy Chicken | -g1-i1
bk-4955f7d1-d1d8-49bd-86e9-a391884c86c1 | Crispy Chicken | -g1-i1
bk-2ab6576f-b609-410d-be98-6464ce94425e | Double Chicken Krispper® Spicy Menu + King Fusion™ (indisp.) | -g5-i0
bk-8bae71ee-4878-429f-8ad8-af5ba4c85c38 | Double Cowboy (indisp.) | -g1-i2
bk-f4bb6329-9e51-4eb6-9bc1-e9904678d415 | Double Crispy Chicken | -g1-i5
bk-306b6bfe-f511-4ec2-9b31-8fa87a64e5b6 | Double Tuga Whopper® (indisp.) | -g1-i8
bk-ccdc9f1e-251c-4efe-bcb6-eea514ac24d3 | Double Tuga Whopper® com Chouriço (indisp.) | -g1-i8
bk-2ab5bad1-5874-4796-9fcb-be4fbc26dd78 | Long Chicken® | -g1-i3
bk-5cae79c9-d5cd-4ea7-bbb2-a36a8d40fe1e | Long Chicken® | -g1-i3
bk-af76ea32-554e-4558-a48b-71789db4fe96 | Menu Big King® XXL | -g4-i0
bk-a3cdc4be-bfa7-4309-b7a2-2523a2017329 | Menu Completo Cowboy (indisp.) | -g5-i2
bk-cccb165b-a353-4583-8667-545ea050de46 | Menu Completo Double CBK (indisp.) | -g5-i4
bk-3f391706-6486-43cd-81ad-0c75f2179e3b | Menu Completo Double Cowboy (indisp.) | -g5-i2
bk-c690e0ce-a98a-45d8-8198-92d7c8b253bb | Menu Completo Double Duo Bacon Cheddar (indisp.) | -g5-i2
bk-43c6f8c7-9a41-4dd1-bd03-bf2c9c033db9 | Menu Completo Double Steakhouse (indisp.) | -g5-i2
bk-22570a3d-429b-43a9-886f-6ea570eee746 | Menu Completo Double Whopper® (indisp.) | -g5-i3
bk-9d5de2ac-1523-40bb-a544-6780a818f2bd | Menu Completo Duo Bacon (1 Carne) (indisp.) | -g5-i2
bk-3cafcc39-2225-484b-9ac3-3e2e0d50391f | Menu Completo Duo Bacon (1 Frango) (indisp.) | -g5-i2
bk-f7054a94-b141-4708-b98d-f88b5ad5dcd7 | Menu Completo Duo Bacon Cheddar - Double Crispy Chicken (indisp.) | -g5-i1
bk-8f42ab9d-82d6-40f4-bec6-43e1c5838d0e | Menu Completo Steakhouse (indisp.) | -g5-i1
bk-0f7db8b6-3f2e-4711-825c-0586d35c5fc8 | Menu Completo Triple Whopper® (indisp.) | -g5-i1
bk-dee240a7-ef45-4807-ad51-0f92d0b4dfc6 | Menu Completo Whopper (indisp.) | -g5-i8
bk-dee240a7-ef45-4807-ad51-0f92d0b4dfc6 | Menu Completo Whopper (indisp.) | -g9-i8
bk-d839702d-af98-46f6-9474-2aba37886a6c | Menu Double Cheese Bacon XXL® | -g4-i7
bk-a95606bf-7a1d-4197-9957-6ea2cc9b9590 | Menu Double Duo Bacon Cheddar | -g4-i2
bk-34cd16cc-0ddb-42d7-8f0b-914dab7484dd | Menu Double Steakhouse | -g4-i2
bk-ccfe0f5e-6424-4620-8a05-6b9923a35523 | Menu Double The King Ovo | -g4-i8
bk-218430e0-592e-4bb6-8eed-932b7c02ee50 | Menu Double Western XXL | -g4-i2
bk-db8d083b-8e3b-44cc-b8f0-ac5577c5f67b | Menu Double Whopper® | -g4-i9
bk-162e4a5a-9b99-4eb8-aecb-a09087c69e4f | Menu Duo Bacon Cheddar | -g4-i2
bk-9689ab8a-fe7a-408b-8205-5c3deedb3b01 | Menu Long Chicken + 10 Anéis de Cebola (indisp.) | -g5-i3
bk-3ac94dbf-fea6-436c-bbf5-f7040b8f918e | Menu Long Chicken® | -g4-i4
bk-60d4e228-3edc-4cb8-8062-80eaeef017bf | Menú Long Chicken® Spicy Vegetal | -g4-i5
bk-db27e477-edac-4fef-8479-604a6631c8e1 | Menu Spicy Double Whopper® | -g4-i8
bk-7fe207b4-625b-4da9-8693-9fe991e16660 | Menu Steakhouse | -g4-i1
bk-05f1bca3-bb5b-4f6e-87a9-d8bc02accac7 | Menu The King Ovo | -g4-i7
bk-15218c5e-3424-4e8e-b6e4-18b8b104dbeb | Menu Triple Western XXL | -g4-i2
bk-88499967-2467-4fef-be19-ead4e5a6b597 | Menu Triple Whopper® | -g4-i9
bk-e688013a-1f8b-4b9f-ac68-8a2af443a703 | Menu Western XXL | -g4-i3
bk-b74c7077-1b41-4add-b0cc-8e16471d7041 | Menu Whopper® | -g4-i1
bk-06a5e13e-1a15-48e4-85ef-4d4a9df8fe5b | Menu Whopper® Spicy | -g4-i8
bk-06802d1a-38a3-4e15-a408-e366a20349ca | Steakhouse | -g1-i1
bk-dd7c4692-4416-433a-85a7-9ec5f9b0dbb6 | Steakhouse | -g1-i1
bk-072cd2ab-347b-4e10-a5c2-a62fd3fee53a | Triple Western XXL | -g1-i2
bk-078771af-f4cb-451a-b645-3738400175df | Triple Whopper Spicy Menu | -g4-i7
bk-928a170d-4733-4109-a762-7fc4dec29b68 | Tuga Long Chicken® (indisp.) | -g1-i3
bk-c7a20f7c-217c-434e-9596-2190adf9d55a | Tuga Long Chicken® com Chouriço (indisp.) | -g1-i3
bk-fc0bd731-84d2-4c85-a693-68c973b9fd9e | Tuga Whopper® (indisp.) | -g1-i8
bk-323ee72d-3438-4792-bee2-9998fb8fddaf | Tuga Whopper® com Chouriço (indisp.) | -g1-i8
bk-b628b5df-13c2-47d6-8460-d4e60790e6b6 | Tuga Whopper® com Chouriço Menu (indisp.) | -g4-i8
bk-455b3a9f-a8d9-4593-a36b-84adbdaa9339 | Tuga Whopper® Menu (indisp.) | -g4-i8
bk-c9f2fa81-eb73-4345-aa74-f293ab93d04c | Western XXL | -g1-i3
bk-c1047d63-82fa-45ff-8f0d-7278c6803832 | Whopper® | -g1-i8
bk-c6df5c75-0007-4ac6-a77e-92467e97ea33 | Whopper® | -g1-i8
```

## Avisos para quem aplica

- Depois de subir, o bacon continua "mais caro ao balcão" (2,50 > 1,22): cada talão do BK com bacon vai
  continuar a dar o aviso `catalogo_extra_mais_caro` e, com o C3, uma linha pendente no painel. É esperado
  (teto Glovo); rejeita-se no painel.
- O rótulo de cada opção no ecrã do produto mostra `+0,91 €` (o valor guardado, sem a margem), mas o
  botão e o checkout cobram com margem (1,05 €; depois 1,40 €). Ver "erros fora do âmbito" no relatório C.
