# Farmácias da Guarda — dados públicos e imagens (missão farmacias-2026-11-11)

Recolhido a 11/11/2026 pelo agente dos dados públicos. Só fontes públicas; nada inventado.
Gravado em `public.restaurants` (projeto ojykpzwqrtusfeakzrna) nas linhas
`farmacia-se-guarda` e `farmacia-teixeira-guarda`. Não mexi em `approval_status`,
`is_active_admin`, `coming_soon`, `is_partner`, `partner_commission_billing`, nem noutra loja
ou tabela. Ninguém foi contactado.

Nota: as duas farmácias são do mesmo grupo (marca "Gripharma"). O logótipo que a Glovo mostra
nas duas é o do grupo; o logótipo próprio de cada uma está no Facebook delas.

---

## 1. Farmácia da Sé (`farmacia-se-guarda`)

| Campo | Valor gravado | Fontes |
|---|---|---|
| Morada | Rua Batalha Reis, Bloco A, r/c, 6300-668 Guarda | Farmácias Portuguesas/ANF (farmacia-info/09105), Google Maps ("R. Batalha Reis A, 6300-668"), Instagram oficial ("Rua Batalha Reis Bl A 6300-668"), ciberforma (sede), indice.eu, farmaciaperto (alvará INFARMED 4198) |
| Telefone | +351271223202 | ANF, Google Maps, Glovo (botão "Telefonar"), ciberforma, indice.eu |
| Lat/Lng | 40.534032, -7.2705826 | Google Maps (pino da ficha). Confirmado no OpenStreetMap: a geocodificação inversa desse ponto dá "Rua Batalha Reis, Guarda" |
| Horário | seg–sex 09:00–21:00; sáb 09:00–20:00; dom fechada | ANF e indice.eu dizem o mesmo |
| Feriados | fechada (não gravado, ver secção 4) | ANF ("Feriados: Fechada") |
| Facebook | https://www.facebook.com/p/Farm%C3%A1cia-da-S%C3%A9-100063488654105/ | página "Farmácia da Sé, Guarda", 3922 seguidores |
| Instagram | https://www.instagram.com/farmacia_da_se/ | a bio diz "Rua Batalha Reis Bl A 6300-668 Guarda" |
| about_text | "Farmácia da Guarda na Rua Batalha Reis, com medicamentos, dermocosmética, cuidados do bebé e ortopedia. Faz vacinação, medição da tensão arterial e do colesterol e consultas de nutrição." | serviços da ficha ANF e categorias da loja na Glovo |

Diferenças encontradas:
- Hora de abertura nos dias úteis: o Google Maps diz 08:30 e a ANF e o indice.eu dizem 09:00.
  Gravei 09:00 (duas fontes e a mais prudente: a loja nunca aparece aberta antes de abrir).
  Fecho às 21:00 e sábado 09:00–20:00 estão iguais nas três.
- Número de porta: a capa do Facebook (anúncio "Farma Drive") diz "Rua Batalha Reis, N. 2".
  Só uma fonte, por isso não entrou na morada; a morada oficial (ANF/INFARMED) não tem número.
- As coordenadas do farmaciaperto.pt (40.582578, -7.344681) estão erradas, a 8,3 km da cidade.
  Não usei.
- Na ANF, a 11/11 aparecia "ABERTA 24H". É a escala de farmácia de serviço desse dia, não
  o horário normal. Não foi gravado.

Email público: farmacia-se@farmacia-se.com (ANF, ciberforma, indice.eu) e j.grilo@farmacia-se.com
(ANF). **Não gravei** (ver secção 4).
Site: o farmacia-se.com aparece na ciberforma e no indice.eu, mas está fora do ar. A 11/11 o
servidor não respondeu (HTTP 000) nem em http nem em https. Deixei vazio.
Na Glovo: loja 461279, morada de loja 732949, página
https://glovoapp.com/pt/pt/guarda/stores/farmacia-da-se-grd

## 2. Farmácia Teixeira (`farmacia-teixeira-guarda`)

| Campo | Valor gravado | Fontes |
|---|---|---|
| Morada | Largo General Humberto Delgado, n.º 5, 6300-712 Guarda | ANF (farmacia-info/09792), Google Maps ("Largo Gen. Humberto Delgado 5, 6300-712"), OpenStreetMap (nó 13697883425), farmaciaperto (alvará INFARMED 916), indice.eu, municipiosefreguesias.pt, servicospublicos.pt |
| Telefone | +351271211110 | ANF, Google Maps, Glovo, ciberforma, indice.eu, municipiosefreguesias.pt |
| Lat/Lng | 40.5365578, -7.2678577 | OpenStreetMap, nó "Farmácia Teixeira". A geocodificação inversa dá "Farmácia Teixeira, 5, Largo General Humberto Delgado". O pino do Google (40.5365063, -7.2675786) fica a 24 m e o do farmaciaperto a cerca de 12 m |
| Horário | seg–sex 09:00–20:00; sáb 09:00–13:30; dom fechada | ANF, Google Maps e indice.eu dizem o mesmo |
| Feriados | fechada (não gravado, ver secção 4) | ANF |
| Facebook | https://www.facebook.com/fteixeiraguarda/ | página "Farmácia Teixeira, Guarda", 1829 seguidores, com o logótipo da farmácia |
| Instagram | **vazio** | não encontrei uma conta da Guarda. As duas que aparecem com este nome são de farmácias do Brasil: @farmacia_teixeira_ tem telefone com indicativo 83 e @farmaciateixeiraa abre das 7h às 19h |
| about_text | "Farmácia no Largo General Humberto Delgado, no centro da Guarda, com medicamentos e produtos de saúde e bem-estar. Faz medição da tensão arterial, do peso e do índice de massa corporal, e vacinação." | serviços da ficha ANF, do indice.eu e da descrição do Facebook |

Diferenças encontradas:
- A ciberforma tem uma morada antiga: "Praça Município 5, 6300-736". As outras sete fontes,
  incluindo o registo da ANF/INFARMED, dizem Largo General Humberto Delgado 5, 6300-712.
  Usei esta.

Email público: farmateixeira.gripharma@gmail.com e j.grilo@farmacia-se.com (ANF). O
farmacia_teixeira@sapo.pt (indice.eu) parece antigo. **Não gravei** (ver secção 4).
Site: não tem.
Na Glovo: loja 461596, morada de loja 733650, página
https://glovoapp.com/pt/pt/guarda/stores/farmacia-teixeira-grd

## 3. Imagens (reais, nada gerado e nada de banco de imagens)

Colunas que a app usa, lidas no código do worktree:
- logótipo = `photo_url`: `restaurant_store.dart`, `lojaDaLinha`; no ecrã da loja é o círculo
  de 56 px em `restaurant_menu_screen.dart`.
- capa = `hero_image_url`: no ecrã da loja tem 150 px de altura e no cartão da página inicial a
  proporção é 1,6 : 1 (`home_feed.dart`).
- `cover_url` não é lida em `lib/`. Pus o mesmo URL da capa, como fazem as outras lojas
  parceiras (sabores-brasil, boom-burger, mrkebab).

Caminho no balde: a função `can_write_restaurant_asset(name)` aceita a primeira pasta igual ao
`restaurants.id` quando `restaurants.user_id = auth.uid()`. Fica assim
`restaurant-assets/<id-da-loja>/<ficheiro>`. Entrei com a conta de parceiro de demonstração de
cada loja: login 200 e o uid da sessão é o `user_id` da loja. A palavra-passe nunca foi
impressa. A chave pública foi passada por variável de ambiente, porque a tranca não deixa
escrevê-la no ficheiro do script.

| Loja | Tipo | URL público (HTTP 200, os mesmos bytes, sha256 igual) | Formato (bytes mágicos) | Tamanho | Origem |
|---|---|---|---|---|---|
| Sé | logótipo | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/restaurant-assets/farmacia-se-guarda/logo-fb-20261111.jpg | JPEG `ffd8ff`, sha256 ab1b774ddbfe4d0b… | 604×604, 20 412 B | Foto de perfil da página do Facebook (819×460). Recortei à volta do logótipo e pus fundo branco para ficar quadrado |
| Sé | capa | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/restaurant-assets/farmacia-se-guarda/capa-glovo-20261111.jpg | JPEG `ffd8ff`, sha256 abfc3c599a112527… | 832×520, 158 273 B | Foto do interior da própria farmácia, a que está no topo da loja na Glovo (`stores-glovo/stores/14b8db70…`, PNG 1242×690). Recortei a parte esquerda para tirar o selo amarelo "Exclusivo Glovo" e passei a JPEG |
| Teixeira | logótipo | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/restaurant-assets/farmacia-teixeira-guarda/logo-fb-20261111.jpg | JPEG `ffd8ff`, sha256 e298799863902680… | 505×505, 21 161 B | Foto de perfil da página do Facebook (648×648, logótipo "teixeira FARMÁCIA"). Recortei à volta do logótipo e centrei em fundo branco |
| Teixeira | capa | https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/restaurant-assets/farmacia-teixeira-guarda/capa-glovo-20261111.jpg | JPEG `ffd8ff`, sha256 b34113f6c868205d… | 832×520, 79 804 B | Foto do interior (balcões e "Medicação Familiar"), a que está no topo da loja na Glovo (`stores-glovo/stores/74976541…`, PNG 1242×690 com barras brancas). Recortei para tirar as barras e o selo "Exclusivo Glovo" e passei a JPEG |

Porque não usei as capas do Facebook:
- Sé: é um anúncio do "Farma Drive" com a foto de uma senhora ao volante, que parece de banco
  de imagens.
- Teixeira: é uma foto de grupo de um evento, com cerca de 60 pessoas à porta de um edifício
  que não é a farmácia.

Não existe coluna de origem da foto em `restaurants` (procurei colunas com origem, source,
credit ou foto). A origem fica registada só neste ficheiro.

## 4. O que ficou vazio ou não foi gravado, e porquê

- **email: não mexi** (ficaram `demo.farmacia.se@bora.app` e `demo.farmacia.teixeira@bora.app`).
  A função `monthly_statement_recipients`, que alimenta o resumo mensal enviado por email no dia
  1, lê `r.email` de `restaurants`. O endereço de demonstração é filtrado por `is_demo_email`.
  Com o email verdadeiro, o sistema podia mandar emails automáticos às farmácias, e isso é
  contactá-las, o que está proibido. Os emails públicos estão nas secções 1 e 2, para quando
  houver acordo.
- **social_instagram da Teixeira:** vazio, não há conta da Guarda (ver secção 2).
- **site:** a Sé tem farmacia-se.com fora do ar e a Teixeira não tem site.
- **Feriados:** as duas fecham nos feriados (ANF). Não gravei porque `business_hours` só aceita
  dias especiais por data (`special_dates`) e nenhuma loja da base usa isso ainda. Fica para
  decidir se se acrescentam os feriados nacionais por data.
- **Farmácia de serviço** (abertas 24 h por escala): não cabe no horário semanal e não foi
  gravada.
- **gallery_urls:** não mexi (continua `[]`).
- Os relatórios de estágio da UBI que descrevem a Farmácia da Sé não abriram: o servidor
  ubibliorum.ubi.pt recusou a ligação. Não fizeram falta.

## 5. Capturas da Glovo para comparar (largura 390 px)

Na pasta `glovo-capturas/`:
- `glovo-farmacia-da-se-topo-390.jpg` (390×843)
- `glovo-farmacia-teixeira-topo-390.jpg` (390×843)

São o topo da loja na Glovo, sem sessão iniciada: capa, logótipo Gripharma, nome, taxa de
0,19 € e o primeiro carrossel "Medicamentos Não Sujeitos a Receita Médica". Rejeitei os
cookies e fechei o aviso de morada antes da captura. O painel de informação (i) da Glovo não
abre sem morada, por isso não há captura dele.

## 6. Leitura de volta (SELECT depois do UPDATE, 11/11/2026)

- farmacia-se-guarda: address "Rua Batalha Reis, Bloco A, r/c, 6300-668 Guarda", phone
  +351271223202, lat 40.534032, lng -7.2705826. business_hours: seg–sex 09:00–21:00, sáb
  09:00–20:00, dom closed, com break_start e break_end a null. Facebook e Instagram como acima,
  about_text gravado. photo_url = logo-fb-20261111.jpg; hero_image_url e cover_url =
  capa-glovo-20261111.jpg. Estado sem mudança: approval_status rejected,
  is_active_admin false, coming_soon true, is_partner true.
- farmacia-teixeira-guarda: address "Largo General Humberto Delgado, n.º 5, 6300-712 Guarda",
  phone +351271211110, lat 40.5365578, lng -7.2678577. business_hours: seg–sex 09:00–20:00,
  sáb 09:00–13:30, dom closed. Facebook gravado, Instagram null, about_text gravado. Imagens
  como acima. Estado sem mudança: rejected, false, true, true.

## Fontes (URLs)

- ANF / Farmácias Portuguesas: https://www.farmaciasportuguesas.pt/farmacia-info/09105 e https://www.farmaciasportuguesas.pt/farmacia-info/09792
- Google Maps: ficha "Farmácia da Sé" (@40.534032,-7.2705826) e ficha "Farmácia Teixeira" (@40.5365063,-7.2675786)
- OpenStreetMap (Overpass e Nominatim): nó 13697883425 (Farmácia Teixeira)
- Glovo: https://glovoapp.com/pt/pt/guarda/stores/farmacia-da-se-grd e https://glovoapp.com/pt/pt/guarda/stores/farmacia-teixeira-grd
- Facebook: https://www.facebook.com/p/Farm%C3%A1cia-da-S%C3%A9-100063488654105/ e https://www.facebook.com/fteixeiraguarda/
- Instagram: https://www.instagram.com/farmacia_da_se/
- indice.eu: https://www.indice.eu/pt/saude-onde/farmacia/farmacia-da-se-9105 e https://www.indice.eu/pt/saude-onde/farmacia/farmacia-teixeira-9792
- farmaciaperto.pt (dados do INFARMED): https://farmaciaperto.pt/guarda/guarda/da-se-4198.html e https://farmaciaperto.pt/guarda/guarda/teixeira-916.html
- ciberforma: https://codigopostal.ciberforma.pt/dir/500995850/farmacia-da-se-unipessoal-lda/ e https://codigopostal.ciberforma.pt/dir/0/farmacia-teixeira-guarda/
- municipiosefreguesias.pt e servicospublicos.pt (Farmácia Teixeira)
