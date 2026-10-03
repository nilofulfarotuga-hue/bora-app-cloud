# Google Ads — campanha "Bora Guarda 3 km" (pronta a montar) · 30/09/2026

> Ordem do Danilo 30/09 22:14: 10 €/dia, raio de 3 km da Guarda, destino boraguarda.com/baixar?de=google.
> Estado: **NÃO montada.** A conta boraappbora@gmail.com (perfil Bora do Chrome) **não tem conta Google Ads**
> ("Não tem contas do Google Ads. Quer criar uma?"). Criar a conta e pôr o cartão é acto do Danilo.
> Quando a conta existir com cartão, qualquer sessão monta isto em ~15 min seguindo esta ficha.

## Conta
- Google: boraappbora@gmail.com (perfil Bora, deviceId d9e862e0). Fuso Europe/Lisbon, moeda EUR.
- Alternativa a decidir pelo Danilo: o perfil pessoal já tem uma conta Google Ads (jaiagarwala.com, 144-763-8091).
  Se essa conta tiver cartão válido, a campanha do Bora pode nascer lá sem passo de cartão (ver relatório).

## Campanha
| Campo | Valor |
|---|---|
| Objetivo | Tráfego do site (sem metas guiadas) → tipo **Pesquisa** |
| Nome | Bora Guarda · Pesquisa · 3 km |
| Redes | Só Pesquisa Google (desligar Parceiros de pesquisa e Rede de Display) |
| Localização | Raio **3 km** à volta de "Guarda, Portugal" (centro: 40.5373, -7.2679). Opção de local: **Presença** (pessoas em ou regularmente na área), nunca "Presença ou interesse" |
| Idioma | Português |
| Orçamento | **10,00 € por dia** |
| Lances | Maximizar cliques, com limite de CPC de 0,60 € (rever à 1.ª semana) |
| Horário | Todos os dias 08:00–23:00 (a app entrega nesse horário) |
| Datas | Início imediato, sem fim |
| URL final | https://boraguarda.com/baixar?de=google |
| Caminho de visualização | boraguarda.com/baixar |

⚠️ **Destino:** desde 23/09 o `/baixar` responde **302 para o Play Store / App Store** (Cloudflare). O Google Ads
pode reprovar por "destino não corresponde" (domínio da URL final ≠ domínio de chegada) e a página **não regista
visitas** (`link_clicks`/`site_visits` parados desde 23/09 17:41). Duas saídas, à escolha do Danilo:
(a) URL final `https://boraguarda.com/?de=google` (página principal, sem redirecção) e o botão "Instalar" leva ao store;
(b) manter `/baixar` mas repor a página intermédia que regista a visita antes de redirecionar.

## Grupo de anúncios 1 — Comida em casa (Guarda)
Palavras-chave (correspondência de expressão):
"entrega comida guarda", "comida ao domicílio guarda", "restaurantes entrega guarda", "pedir comida guarda",
"delivery guarda", "açaí guarda", "goola açaí guarda", "hambúrguer entrega guarda", "jantar em casa guarda"
Negativas: emprego, vagas, recrutamento, curso, receita, grátis download apk, uber eats, glovo, bolt

Anúncio responsivo (títulos ≤30):
1. Entrega de comida na Guarda · 2. Pede na app, chega a casa · 3. Código BEMVINDO: menos 5 € · 4. Restaurantes da Guarda
5. Estafetas da cidade · 6. Açaí, pizza, hambúrguer · 7. Bora, a app da Guarda · 8. Sem sair de casa
Descrições (≤90):
1. Restaurantes e lojas da Guarda a entregar em casa. Primeiro pedido com o código BEMVINDO: 5 euros de desconto.
2. Escolhes na app, um estafeta da Guarda traz à porta. Vês a hora de chegada e pagas como preferires.
3. Descarrega a Bora, a app de entregas feita na Guarda, e poupa 5 euros no primeiro pedido.

## Grupo de anúncios 2 — Supermercado ao domicílio
"supermercado ao domicílio guarda", "compras supermercado entrega guarda", "compras em casa guarda",
"entrega compras guarda", "mercearia entrega guarda"
Títulos: As compras à porta de casa · Supermercado ao domicílio · Guarda, hoje mesmo · BEMVINDO: 5 € no 1.º pedido ·
Estafeta vai por ti · Lista na app, pagas no fim
Descrições: Um estafeta faz as tuas compras no supermercado e entrega em casa, na Guarda. Código BEMVINDO no primeiro pedido.
/ Ficaste sem leite? A app do Bora vai ao supermercado por ti. Preço à vista antes de confirmar.

## Grupo de anúncios 3 — Serviços (barbearia, lavagem, limpeza)
"barbearia guarda", "barbeiro guarda marcação", "lavagem auto guarda", "lavagem de carros guarda",
"limpeza doméstica guarda", "empregada limpeza guarda"
Títulos: Marca a barbearia na app · Lavagem do carro na Guarda · Limpeza de casa marcada · Escolhes dia e hora ·
Ouro e Prata na app do Bora · BEMVINDO: 5 € de desconto
Descrições: Barbearias, lavagem automóvel e limpeza doméstica da Guarda com marcação pela app. Sem telefonemas.
/ Marcas na app do Bora e chegas à hora certa. Primeiro pedido com o código BEMVINDO: menos 5 euros.

## Recursos (assets)
- Imagens: peças aprovadas do banco (VPS `/opt/data/social/saidas/carrossel-2026-09-06-*.jpg`), sem logos de terceiros
  (**não** usar `2-supermercado-*` nem `frame-01-mercado` — têm Continente/Pingo Doce/Auchan no visual).
- Vídeo (só se houver campanha de vídeo): `5-lavagem-auto.mp4` (fiscal 90,5) e `4-sabores-de-casa.mp4` (85,3), no
  canal YouTube da conta Bora. Os IPG 1 e 2 têm marcas de terceiros no texto → não em anúncios.
- Extensões: sitelinks (Restaurantes / Supermercado / Barbearias / Lavagem auto), callout (Entrega na Guarda ·
  Código BEMVINDO · Estafetas locais), telefone 937 501 673 (WhatsApp do Bora), localização (Guarda).

## Relatório diário (Telegram, três números)
gasto do dia (€) · cliques · visitas a /baixar vindas de `?de=google` — este 3.º número está a **zero por defeito**
enquanto o `/baixar` não voltar a registar visitas (ver aviso acima). Fonte: Google Ads (gasto, cliques) +
`select count(*) from site_visits where origem='google' and created_at::date = current_date` no Supabase do Bora.
