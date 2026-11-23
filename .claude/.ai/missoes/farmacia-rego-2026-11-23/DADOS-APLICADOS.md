# Farmácia Rego — o que foi gravado no servidor (23/11/2026)

Missão `farmacia-rego-2026-11-23`, fluxo e2e_log com o mesmo nome. Só dados, nenhuma
mudança de estrutura e nenhum código da app: **não há nada a publicar nas lojas (Play,
Apple, web) por causa do Bloco 1.**

## Loja `farmacia-rego-guarda` (tabela `restaurants`)
- Farmácia Rego, `category = pharmacy`, parceira, `approval_status = approved` com
  `bora.forcar_ativacao = 1` (sem IBAN: é demonstração, regra de 17/11).
- **Escondida**: `so_lista_permissao = true`, `coming_soon = false`.
- Morada Av. Rainha Dona Amélia 142, 6300-749 Guarda; coordenadas 40.5289707, -7.2752385
  (nó do OpenStreetMap "Farmácia Rego", amenity=pharmacy, código postal 6300-749).
- Horário 08:00–22:00 todos os dias. Telefone +351 926 144 981.
- Síntese Vitalícia, Lda., NIF 517083116 (lidos no rodapé do site deles — a confirmar).
- `email = regoteste@bora.app` de propósito: o gestaorego@gmail.com só entra quando a
  farmácia aceitar (assim nenhum aviso automático lhes chega antes). `alert_call_phone` vazio.
- `pharmacy_prescription_mode = so_lista`, `partner_extra_commission_pct = NULL`,
  `app_markup_pct = 0.15` (só tem efeito com a proposta de preço aplicada).
- Imagens reais do site farmaciarego.pt (media WordPress), enviadas pela Edge
  `upload-restaurant-asset` com o login de regoteste: logo = símbolo do trevo, capa =
  interior, hero = fachada. Origem de cada ficheiro em
  `bora-site/sites-parceiros/farmacia-rego/origem/site-oficial/origens.json`.

## Contas de teste (senha 123456)
- `regoteste@bora.app` — parceiro, dono da loja (user_roles partner + client).
- `regocliente@bora.app` — cliente.
Criadas pelo mesmo caminho das contas da A3 (auth.users + auth.identities; public.users pelo
gatilho; user_roles à mão).

## Lista de quem vê a loja (`loja_lista_permissao`)
nilofulfarotuga@gmail.com, boraappbora@gmail.com, regocliente@bora.app, regoteste@bora.app.

## Catálogo de demonstração (100 produtos, ids `frg-*`)
Copiados da Farmácia da Sé (nome, foto do nosso Storage, categoria, descrição), 11
categorias, marcas mais comuns primeiro, nenhum com receita. `partner_shelf_price` = balcão
da Sé (provisório); `price` = balcão × 1,15; `preco_provisorio = true`; `source` =
"demo-rego-2026-11-23: preço provisório, a confirmar pela Rego".

## Para abrir ao público (quando a Rego disser)
1. Aplicar a proposta de preço (PROPOSTA-preco-farmacia-com-markup.sql) com o AUTORIZO.
2. Trocar o email de login de regoteste pelo da farmácia e pôr o IBAN (o contrato aceita-se
   no painel do parceiro).
3. Preços de balcão reais da Rego por cima dos provisórios.
4. Painel admin › Farmácias › Abrir ao público (`admin_farmacia_abrir`).
