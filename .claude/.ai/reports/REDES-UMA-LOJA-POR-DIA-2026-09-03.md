# REDES — UMA LOJA POR DIA — 2026-09-03

> Sessão `redes-uma-loja-por-dia`. Motor: Claude Opus 5 → Fable 5.1, Claude Code, PC novo.
> Portão de RAM no início: **1867 MB** (acima dos dois portões). Nada foi libertado.
> CEO-AI invocado; Córtex lido ("flyer": ordens do flyer v2/v3 de 28/08 com a
> lição "Gemini só faz fundo, nunca texto nem logos"; "divulgacao"/"BEMVINDO": sem
> entradas). Base lida (tabelas `restaurants` e `service_providers`).

---

## OS 6 LINKS DE HOJE (os 3 parceiros, Facebook E Instagram)

| Parceiro | Facebook (feed) | Instagram (feed) | Stories |
|---|---|---|---|
| **Goola Açaí** (La Vie) | https://www.facebook.com/1230974540107256_122096226585453644 | https://www.instagram.com/p/Dc0g_a8l5hh/ | FB foto 122096227005453644 · IG 18124550921497244 |
| **Barbearia Ouro e Prata** (Gilberto) | https://www.facebook.com/1230974540107256_122096227683453644 | https://www.instagram.com/p/Dc0hFCAl3TJ/ | FB 122096227833453644 · IG 18108531698157044 |
| **Sabores do Brasil** (Keli) | https://www.facebook.com/1230974540107256_122096236713453644 | https://www.instagram.com/p/Dc0ijyWlygl/ | FB 122096236869453644 · IG 17988197856062354 |

Cada uma saiu em **feed 1080×1350** e **story 1080×1920**, nas duas redes, pela
API, com o script `publicar_cartaz.sh` (cada passo tenta 1× mais se falhar; o
Telegram do Danilo recebeu os links e a frase pronta para reenviar ao parceiro:
*"Publiquei a tua loja no Bora, partilha aí"*).

**Marcação (tag):**
- Instagram: marcação na foto (`user_tags`) + `@utilizador` na legenda —
  `@goolaacai.pt`, `@ouroepratabarbeariaguarda`, `@sabores_do_brasil.pt`.
  Aceite à primeira nas três (nenhuma caiu para o modo sem marcação).
- Facebook: a API **ignora** `@[id-da-página]` na legenda de fotos (testado no
  Goola: `message_tags` só devolveu as hashtags e a linha não ficou visível).
  Fica o nome em texto. Registado em `parceiros.md`.

**As duas publicações planas da manhã** (restaurantes e mercados, cartaz liso)
foram **apagadas** — as do Facebook pela API (`{"success":true}` ×2), a do
Instagram pelo clique (a API não deixa apagar media do Instagram; confirmado:
"Insufficient permissions"), e o permalink já responde "esta página não está
disponível".

---

## COMO AS IMAGENS FORAM FEITAS (adendo "as imagens têm de impressionar")

A API do Gemini respondeu **429 RESOURCE_EXHAUSTED** logo no primeiro pedido de
imagem (modelos disponíveis para a chave: `gemini-2.5-flash-image`,
`gemini-3.1-flash-image`, …). Regra da ordem: não parar, não subir o tecto →
**Gemini pelo clique** em `gemini.google.com` (conta `nilofulfarotuga@gmail.com`,
`/u/1/app`), com as **fotos reais do parceiro anexadas** como referência e o
prompt exacto escrito por mim. O `chatgpt.com` **não tinha sessão** (a ordem dizia
que tinha) — não foi usado.

| Cena | Referência real anexada | Resultado |
|---|---|---|
| Goola | foto do quiosque no La Vie + logo | taça de açaí a transbordar, o quiosque real (balões rosa, balcão branco em gota) desfocado atrás — **à 1.ª** |
| Barbearia | logo/caricatura do Gilberto | cadeira clássica preta com ouro e prata, barbeiro só mãos, cliente de costas, espelho com lâmpadas — **à 1.ª** |
| Sabores | foto real da caixa de salgados + logo | travessa de coxinhas, kibes, bolinhas e enroladinhos, vapor, festa desfocada — **à 3.ª** (ver abaixo) |
| genérica restaurante (lojas grandes) | — | hambúrguer numa caixa de cartão lisa sem marca, cozinha portuguesa |
| genérica supermercado | — | saco de papel liso com fruta e pão à porta de uma casa de pedra |

**O que correu mal nos salgados, dito como foi:** a 1.ª tentativa foi enviada sem
a foto anexada (o menu de anexos não abriu) e a 2.ª colou, em vez da foto, o
**texto do adendo do Danilo** que estava na área de transferência do PC — o Gemini
fez uma festa com pessoas de cara visível. Nenhuma das duas foi usada. A 3.ª, com
a foto real anexada pelo menu, saiu certa. Lição: no PC do Danilo a área de
transferência é dele; não se cola nada sem ver o que lá está.

**Texto, logos e selo BEMVINDO** entram DEPOIS por PIL (`cartaz_cinema.py`):
logo do Bora numa pastilha branca em cima à esquerda, logo do parceiro num disco
branco em cima à direita (só parceiros), título grande em **Inter ExtraBold** (a
fonte do flyer, copiada para a VPS), nome, selo laranja `#F97316` com o código,
rodapé. Lojas grandes: sem logo de terceiros, nome só em texto, aviso legal no
cartaz e na legenda.

**Juiz de visão:** a API do Gemini também está no tecto para texto
(`gemini-2.5-flash` 429, `gemini-2.0-flash` 404), por isso o juiz automático
(`juiz_visao.py`) ficou instalado mas **hoje o juiz fui eu**: vi as três cenas e
os seis cartazes um a um. Sem texto estranho no primeiro plano, sem mãos ou rostos
deformados, produto reconhecível, logos intactos. O único reparo: na cena do Goola
há sinalética minúscula e desfocada no quiosque de fundo — ilegível, aceite.

Prompts que funcionaram: `/opt/data/social/prompts-imagem.md`.

---

## A ROTAÇÃO (14 dias) — `/opt/data/social/rotacao.md`

Parceiro, grande, parceiro, grande… Os 3 parceiros voltam sempre (cada um ≥1×
por semana); entre eles as lojas não-parceiras **activas** na app. Mr Kebab e
Sabores de Casa só entram quando deixarem de estar `coming_soon` (o script
verifica na base no dia). Nada de TVDE/boleia.

| data | loja | tipo |
|---|---|---|
| 03/09 | Goola · Barbearia · Sabores (os três, hoje) | parceiros — **feito** |
| 04/09 | McDonald's | grande |
| 05/09 | Goola Açaí | parceiro |
| 06/09 | Continente | grande |
| 07/09 | Barbearia Ouro e Prata | parceiro |
| 08/09 | Burger King | grande |
| 09/09 | Sabores do Brasil | parceiro |
| 10/09 | Pingo Doce | grande |
| 11/09 | Goola Açaí | parceiro |
| 12/09 | KFC | grande |
| 13/09 | Barbearia Ouro e Prata | parceiro |
| 14/09 | Intermarché | grande |
| 15/09 | Sabores do Brasil | parceiro |
| 16/09 | Wells | grande |
| 17/09 | Goola Açaí | parceiro |

Quando a tabela acabar, `proxima_loja.py` continua sozinho pela mesma regra,
lendo a base, e acrescenta a linha do dia.

---

## O QUE CORRE SOZINHO A PARTIR DE AMANHÃ — crontab (adendo 2, calendário fixo)

```
0 12 * * *     social-loja-do-dia.sh   # loja do dia, FB + IG, feed + story
30 19 * * *    social-story.sh         # 1 story por dia (pergunta escrita na imagem)
0 18 * * 1,3,5 social-reel.sh          # reel vertical por ffmpeg, sem música
0 11 * * 0     social-semana.sh        # domingo: grelha "esta semana no Bora"
0 9  * * 1     social-medir.sh         # segunda: relatório curto no Telegram
```

Calendário completo e regras de crescimento em `/opt/data/social/calendario.md`.

**O relatório de segunda já correu uma vez, hoje, como prova** (foi para o
Telegram):

```
Seguidores: Instagram 1 · Facebook 0
Alcance no Instagram (7 dias): ?          <- a conta é de hoje; a métrica ainda não existe
Melhor publicacao: 1 gostos — https://www.instagram.com/p/Dc0ijyWlygl/
Publicacoes no Instagram ate hoje: 4 · saidas registadas no log: 5
Codigo BEMVINDO: sem acesso pela chave anonima (RLS)
Instalacoes (Play Console): por ligar — falta a chave da API do Play.
```

Dois buracos honestos nesse relatório: **os resgates do BEMVINDO** não se lêem
com a chave anónima (a RLS da `promo_codes` bloqueia — é preciso um RPC de
leitura ou a chave de serviço no `.env` do Hermes, decisão para ordem própria;
lido hoje pelo MCP: **BEMVINDO tem 2 resgates de 300, activo, sem data de fim**) e
**as instalações do Play Console** precisam de uma chave da API do Play que não
existe. O relatório diz isso à cara em vez de inventar números. A regra "PRONTO
PARA TESTE DE ANÚNCIO" está escrita: aparece quando o log tiver 20 saídas — só
escreve, nunca liga tráfego pago.

**Interacção pelo agente de clique (seguir/gostar/comentar, máx. 20/dia) e
respostas em <1 h:** ficou **por montar** — precisa de uma sessão do Chrome
aberta em permanência e de ritmo humano; fica para ordem própria, com o
calendário já a prevê-lo.

A linha antiga `0 12 * * 1,3,5 … social-bora.sh` (seg/qua/sex) foi **retirada**.
`CRON_TZ=Europe/Lisbon` continua declarado uma só vez (linha 7). O
`radar-dinheiro.sh` de quarta e o `radar-ia.sh` de domingo não foram tocados.

**Guardas:** `.loja-feita-<data>`, `.story-feita-<data>`, `.reel-feito-<data>` —
nunca duas no mesmo dia. **Vigia:** cada passo tenta 1× mais; sucesso → link no
Telegram; falha → aviso com o erro real; tudo em `/opt/data/social/log.md`.

**Cena "de cinema" no dia-a-dia:** o `social-loja-do-dia.sh` tenta primeiro a
API (`gerar_cena.py`, com as fotos reais da base anexadas); se a API estiver no
tecto usa a **última cena guardada** do parceiro (as três de hoje) ou a **cena
genérica da categoria** (restaurante e supermercado já feitas hoje; farmácia e
lojas ficam por gerar antes de 16/09); se não houver nenhuma, avisa no Telegram e
sai o cartaz de reserva verde.

---

## O PRIMEIRO REEL (hoje) — Facebook sim, Instagram travado num detalhe técnico

`social-reel.sh`: 3 cenas reais (saco de compras, hambúrguer, salgados) com zoom
lento de 4 s cada + cartão final verde com BEMVINDO, **15,0 s, 1080×1920, h264,
sem áudio, 2 MB**, renderizado em 49 s no contentor do Hermes.

```
FB VIDEO OK id=2517577688750273  -> https://www.facebook.com/2517577688750273
IG REEL publicar falhou: 2207076 "O download dos conteúdos multimédia falhou."
```

**Porquê:** o Instagram só aceita vídeo por URL público. Usei o URL `source` do
próprio vídeo do Facebook, e o Instagram não o consegue descarregar (é um URL
assinado do CDN). O Supabase Storage não aceita upload com a chave anónima (RLS,
403) e não há chave de serviço no `.env` do Hermes.

**Resolvido na VPS, sem tocar em nada que já existia:** a VPS tem o traefik a
servir `*.srv1786862.hstgr.cloud` com certificados automáticos. Pus um `nginx:alpine`
(`bora-social-static`) a servir só a pasta `/opt/data/social/publico` em
**`https://social.srv1786862.hstgr.cloud/`**, na rede `hermes-agent-fvnc_default`
como os outros contentores. Prova: `HTTP 200, 2009657 bytes, video/mp4`.
(Primeira tentativa errada: pus o nginx em rede `host`, onde o traefik não o vê —
404; corrigido.) O `social-reel.sh` passou a copiar o mp4 para essa pasta e a dar
esse URL ao Instagram.

```
contentor 18093796730213941: IN_PROGRESS ×8 → FINISHED
IG REEL OK id=18107856392582335 -> https://www.instagram.com/reel/Dc0mjXsEhrP/
```

**Primeiro reel publicado nas duas redes hoje**, como a ordem pedia.

**Um erro meu no caminho, corrigido:** a primeira versão do ffmpeg usava `-loop 1
-t 4` junto com `zoompan d=100`, e cada fotograma de entrada gerava 100 de saída:
400 s por parte, 70 MB, um render que nunca acabava. Matei o processo, corrigi
para uma imagem de entrada + `-frames:v 100`, e o render passou a 49 s. O texto
a 78 px também saía cortado dos lados; passou a 60 px com frases mais curtas.
Ambos os erros estão escritos no script para não se repetirem.

## O STORY DAS 19:30

`social-story.sh` alterna foto real com pergunta (dias pares) e pergunta em fundo
da marca (dias ímpares), roda por 7 perguntas, publica story no FB e no IG, guarda
`.story-feita-<data>`. Provado hoje com os dois formatos renderizados (a pergunta
em verde, e "Já usaste o código BEMVINDO?" por cima da cena do açaí) — e os seis
stories de hoje já saíram pelo `publicar_cartaz.sh` com o mesmo caminho da API.
A primeira corrida automática é hoje às 19:30.

## FICHEIROS NOVOS NA VPS (tudo em zona verde; nada de dinheiro)

| Onde | O quê |
|---|---|
| `/opt/data/scripts/social-loja-do-dia.sh` | a loja do dia (rotação → base → cena → cartaz → juiz → publicar → marcar) |
| `/opt/data/scripts/publicar_cartaz.sh` | publica feed + story nas duas redes com marcação e 1 retry por passo |
| `/opt/data/scripts/social-story.sh` · `social-reel.sh` · `social-semana.sh` · `social-medir.sh` | story 19:30, reel seg/qua/sex, grelha de domingo, relatório de segunda |
| `/opt/data/social/cartaz_cinema.py` · `story_pergunta.py` · `semana_grelha.py` | montagem PIL (Inter da marca) |
| `/opt/data/social/gerar_cena.py` · `juiz_visao.py` | Gemini API (cena, juiz) — hoje no tecto, fallbacks à vista |
| `/opt/data/social/texto_loja.py` · `marcar_rotacao.py` · `proxima_loja.py` | textos por tipo/categoria, estado da rotação, continuação automática |
| `/opt/data/social/rotacao.md` · `calendario.md` · `parceiros.md` · `prompts-imagem.md` | os quatro ficheiros de decisão |
| `/opt/data/social/cenas/` | 5 cenas de cinema (3 parceiros + 2 genéricas) |
| `/opt/data/social/publico/` → `https://social.srv1786862.hstgr.cloud/` | alojamento público dos vídeos para o Instagram |

`radar-ia.sh`, loop, carteiro e tudo o que é dinheiro: **não tocados**. Nenhum
push no `bora_app` (o relatório fica em commit local). Nenhum push no `bora-site`
(não foi preciso: o alojamento ficou na VPS).

---

## O QUE FICA POR CONFIRMAR

1. **A corrida automática de amanhã** (04/09 12:00, McDonald's, cena genérica do
   hambúrguer + aviso legal) — é a primeira vez que o `social-loja-do-dia.sh` corre
   sozinho. Hoje tudo saiu forçado à mão.
2. **O story das 19:30 de hoje e o reel de sexta às 18:00** pelo cron.
3. **Cenas genéricas de farmácia e lojas** (Wells a 16/09; Worten/Leroy/Kiwoko/
   Zippy na volta seguinte) — por gerar em `gemini.google.com` enquanto a API
   estiver no tecto; o script avisa no Telegram e usa o cartaz de reserva se
   chegar lá sem cena.
4. **Juiz de visão automático** — instalado, mas só funciona quando a API do
   Gemini responder; hoje o juiz fui eu.
5. **Marcação da página no Facebook** — a API ignora `@[id]` em fotos; fica o
   nome em texto. Facebook do Gilberto e da Keli não encontrados com certeza.
6. **Interacção pelo clique (seguir/gostar/comentar, ≤20/dia) e respostas em
   <1 h** — por montar, ordem própria.
7. **Resgates do BEMVINDO e instalações do Play** no relatório de segunda —
   precisam de RPC/chave de serviço e de chave da API do Play.
8. **Rótulo com letras na cena genérica do supermercado** (garrafa de leite) —
   pequeno; da próxima vez pede-se "garrafa sem rótulo" (já está no ficheiro de
   prompts).
