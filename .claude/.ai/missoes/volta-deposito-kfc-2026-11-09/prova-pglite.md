# Prova local (PGlite 0.2.17) — PARTE 1 e PARTE 2

Corrida final: 2026-11-09 22:30 no PC, com as definições reais de produção lidas de novo às ~22:30 (já com a migração 20261109214000_robo_talao_extras_pendentes da missão pendencias-2026-11-09 aplicada) e os 38 talões lidos pelo robô.
Comando: `bun prova_volta.mjs <pasta com as funções> supabase/migrations/20261109220000_volta_catalogo_e_talao.sql PARTE2-dinheiro-proposta.md`

```
KFC casar ANTES  : kfc-ca992720:55 kfc-7139cdb9:672 kfc-57c110ea:738
Robô ANTES: {"ok":true,"aplicadas":1,"ja_batiam":0,"pendentes":2,"sem_match":0,"segunda_volta":0,"extras_pendentes":0,"extras_mais_caros":[]} [{"product_id":"kfc-57c110ea-e07d-453b-b9d9-ffd0db49da4e","old_base":"8.39","new_base":"7.38","status":"pending"},{"product_id":"kfc-7139cdb9-b8ba-4c44-a1c0-dccce410dd6f","old_base":"6.07","new_base":"6.72","status":"applied"},{"product_id":"kfc-ca992720-ca03-4741-b7db-9d5090b65759","old_base":"6.20","new_base":"0.55","status":"pending"}]
KFC casar DEPOIS : kfc-ca992720:620 kfc-7139cdb9:845 kfc-57c110ea:915
Outros talões: 25/26 iguais; mudaram: [
 {
  "loja": "Burger King",
  "antes": [
   715,
   1295
  ],
  "depois": [
   745,
   1295
  ],
  "linhas": "M Whopper=0 | Whopper=478 | Com Ketchup=0 | Com Maionese=0 | Com Cebola=0 | Com Pepino=0 | Extra Alface=0 | Com Tomate=0 | Batatas Media=237 | Compal Pêssego Premi=30 | 3C Western XXL=1295 | Saco de Papel=5 | Extra Ketchup=0"
 }
]
Robô DEPOIS (preços antigos): {"ok":true,"absurdas":0,"aplicadas":2,"ja_batiam":1,"pendentes":0,"sem_match":0,"segunda_volta":0,"extras_pendentes":0,"extras_mais_caros":[]} [{"product_id":"kfc-57c110ea-e07d-453b-b9d9-ffd0db49da4e","old_base":"8.39","new_base":"9.15","status":"applied"},{"product_id":"kfc-7139cdb9-b8ba-4c44-a1c0-dccce410dd6f","old_base":"6.07","new_base":"8.45","status":"applied"}]

=== OK (52) ===
PARTE 1 aplica sem erros (âncoras de catalog_price_update_from_receipt e _recibo_pedido = 1)
Box 6 Hotwings = 6,20 (0,55 + 5,65) → ["BOX 6 HOTWINGS","6 HOT WINGS"]
Menu Wrap Coronel = 8,45 (5,02 + 1,70 + 1,73) → ["MENU WRAP CORONEL","WRAP CORONEL","BATATA MEDIA","V LIPTON IT MANGA LA"]
Menu Kentucky BBQ = 9,15 (5,64 + 1,74 + 1,77) → ["MENU KENTUCKY BBQ","KENTUCKY BBQ ORIGINA","BATATA MEDIA","V LIPTON IT MANGA LA"]
DEPOSITO e SACO fora dos produtos
robô: nenhuma proposta absurda (nada abaixo de 40% nem acima de 250%)
robô: Menu Wrap Coronel 6,07 → 8,45
robô: Menu Kentucky BBQ 8,39 → 9,15
robô com o catálogo já certo: 3 batem, 0 propostas → {"ok":true,"absurdas":0,"aplicadas":0,"ja_batiam":3,"pendentes":0,"sem_match":0,"segunda_volta":0,"extras_pendentes":0,"extras_mais_caros":[]}
classificar "Água sem Gás Alcalina pH 9,5 Monchique (emb. 6 x 1,5 lt)" @continente-guarda = marcar/6 → {"units":6,"estado":"marcar","motivo":"agua_garrafa"}
classificar "Refrigerante Coca-Cola Original Lata (emb. 33 cl)" @continente-guarda = marcar/1 → {"units":1,"estado":"marcar","motivo":"lata"}
classificar "Cerveja Super Bock Mini (emb. 6 x 25 cl)" @continente-guarda = duvidoso/0 → {"units":0,"estado":"duvidoso","motivo":"garrafa_pequena_pode_ser_vidro","units_se_marcar":6}
classificar "Cerveja Sagres Lata (emb. 24 x 33 cl)" @continente-guarda = marcar/24 → {"units":24,"estado":"marcar","motivo":"lata"}
classificar "Vinho Tinto Douro (emb. 75 cl)" @continente-guarda = excluido/0 → {"units":0,"estado":"excluido","motivo":"excluido_vinho"}
classificar "Iogurte Líquido Manga e Papaia (emb. 640 gr (4 un))" @continente-guarda = nao_bebida/0 → {"units":0,"estado":"nao_bebida","motivo":"nao_e_bebida"}
classificar "Leite Meio Gordo (emb. 1 lt)" @continente-guarda = nao_bebida/0 → {"units":0,"estado":"nao_bebida","motivo":"nao_e_bebida"}
classificar "Bebida Láctea Ucal Lata 25cl" @continente-guarda = excluido/0 → {"units":0,"estado":"excluido","motivo":"excluido_lactea"}
classificar "Água das Pedras 25cl" @continente-guarda = duvidoso/0 → {"units":0,"estado":"duvidoso","motivo":"garrafa_pequena_pode_ser_vidro","units_se_marcar":1}
classificar "Água Luso 5 lt" @continente-guarda = excluido/0 → {"units":0,"estado":"excluido","motivo":"mais_de_3_litros"}
classificar "Sumo de Laranja Compal Clássico (emb. 1 lt)" @continente-guarda = duvidoso/0 → {"units":0,"estado":"duvidoso","motivo":"sumo_pode_ser_cartao_ou_vidro","units_se_marcar":1}
classificar "Ice Tea Lipton Manga 1,5 lt" @continente-guarda = marcar/1 → {"units":1,"estado":"marcar","motivo":"refrigerante_lata_ou_pet"}
classificar "Red Bull Energy Drink 25cl" @kfc-guarda = marcar/1 → {"units":1,"estado":"marcar","motivo":"marca_so_em_lata"}
classificar "Pepsi Lata" @kfc-guarda = marcar/1 → {"units":1,"estado":"marcar","motivo":"lata"}
classificar "Água 50cl" @kfc-guarda = marcar/1 → {"units":1,"estado":"marcar","motivo":"agua_garrafa"}
classificar "Coca-Cola Média" @burgerking-guarda = excluido/0 → {"units":0,"estado":"excluido","motivo":"copos_burger_king"}
classificar "Coca-Cola Média" @mcdonalds-guarda = excluido/0 → {"units":0,"estado":"excluido","motivo":"copos_mcdonalds"}
classificar "Whisky Johnnie Walker 70cl" @continente-guarda = excluido/0 → {"units":0,"estado":"excluido","motivo":"excluido_whisky"}
classificar "Batata Frita Lays" @continente-guarda = nao_bebida/0 → {"units":0,"estado":"nao_bebida","motivo":"nao_e_bebida"}
classificar "Néctar de Pêssego Compal (emb. 6 x 20 cl) pacote" @continente-guarda = excluido/0 → {"units":0,"estado":"excluido","motivo":"excluido_pacote"}
volta_deposito_itens: 2 packs de 6 + 3 menus com lata = 15 embalagens → 15
volta_deposito_itens: por linha 12/3/0/0 e cêntimos 120/30/0/0 → [[12,120],[3,30],[0,0],[0,0]]
recibo do cliente: linha "Depósito Volta (8 emb.)" = 80 cênt. → {"nome":"Depósito Volta (8 emb.)","valor_cents":80}
PARTE 2 aplica sem erros (todas as âncoras = 1, 7 funções de dinheiro compilam)
create_order: depósito fora do subtotal, tecto dos tokens sem ele, colunas no INSERT
quote: devolve deposit_cents
tokens sem o depósito
livro-razão: deposit_volta
acerto do parceiro: + v_deposit
finalizar: depósito dos "Não há"
imutabilidade: colunas do depósito
cópias guardadas em bkp_fn_volta_20261109
app antiga (sem a chave) não cobra; app nova (com a chave) cobra
talão +2 DEPOSITO (dinheiro por entregar): cash_total_due 10 → 10,20 → {"cash_total_due":"10.20","final_total":"10.20","deposit_ajuste_cents":20,"deposit_from_receipt_cents":20}
produto que gerou o depósito fica marcado (1 lata por unidade, origem talao) → {"deposit_units":1,"deposit_review":true,"deposit_origem":"talao"}
ler o mesmo talão outra vez não cobra duas vezes → {"cash_total_due":"10.20","deposit_ajuste_cents":20}
talão +2 DEPOSITO (cartão): dívida de 20 cênt. na carteira → [{"amount_cents":-20,"kind":"debit","reason":"volta_deposito_talao"}]
talão com MENOS depósito (dinheiro): cash_total_due 10 → 9,60 → {"cash_total_due":"9.60","deposit_ajuste_cents":-40}
talão sem depósito num pedido que cobrou 0,30 (MB Way): +30 cênt. na carteira → [{"amount_cents":30,"kind":"refund_credit_free"}]
loja parceira: o talão não mexe no depósito → {"cash_total_due":"10","deposit_ajuste_cents":0}
diferença > 10 €: não aplica, avisa o admin → {"o":{"cash_total_due":"10","deposit_ajuste_cents":0},"av":[{"event_type":"volta_talao_diferenca_grande"}]}
talão do KFC de hoje: depósito lido = 20 cênt. (2 latas de Ice Tea) → 20
"VALOR DE DEPOSITO 6U" e "VASILHAME" são depósito; "FRANGO ASSADO EMB." não → {"a":true,"b":false,"c":true}

=== FALHAS (0) ===

```
