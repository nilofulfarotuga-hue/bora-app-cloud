# Robô das stories publica lojas "em breve" — patch para a missão do PC (01/11/2026)

Ordem do Danilo (01/11/2026 19:56, literal): "Robô da Story está publicando lojas em breve. Conserta isso."

## Onde vive o robô (não é editável daqui, por isso este ficheiro)

O robô das redes vive na VPS `srv1786862.hstgr.cloud` (host, crontab de Lisboa), não no Supabase
nem no repo. Mapa lido de `docs/ESTADO-DIVULGACAO-2026-09-21.md`,
`.claude/.ai/reports/REDES-UMA-LOJA-POR-DIA-2026-09-03.md` e do e2e_log fluxo
`redes-coming-soon-2026-10-27` (ids 4968–4972, ordem `ordem-20261027221351-220b`):

- `/opt/data/scripts/social-story.sh` — story das 10:00 (`SOCIAL_SLOT=manha`) e das 19:30
  (pergunta na imagem; dias pares com foto real de uma loja da pasta
  `/opt/data/social/parceiros/<slug>/`). Montagem em `/opt/data/social/story_pergunta.py`.
- `/opt/data/scripts/social-loja-do-dia.sh` (12:00) — feed + story da loja do dia, pela
  `/opt/data/social/rotacao.md` e, quando a tabela acaba, `proxima_loja.py` (lê a base).
  Publica pelo `publicar_cartaz.sh` (o e2e_log mostra "Story FB/IG: story publicada").
- `formato_extra.py` (15:00), `carrossel.py` (18:00 ter/qui/sáb), `social-reel.sh`,
  `grupos_plano.py`, `portao_parceiro.py`.
- Desde 27/10 existe o **escolhedor único** `/opt/data/social/lojas_permitidas.py`
  (md5 48ff3c67 na altura): lê `restaurants` + `service_providers` na hora
  (`coming_soon=false`, `is_active_admin=true`, `approval_status='approved'`) + lista fixa
  EXCLUIR (`82e3162c…` Ouro e Prata, `mr-kebab-grd1`, `mrkebab-guarda`, `boom-burger-guarda`);
  sem resposta da base devolve código 4 e não sai peça de loja. Foi ligado a: social-story.sh,
  social-loja-do-dia.sh, social-reel.sh, carrossel.py, formato_extra.py, portao_parceiro.py,
  proxima_loja.py, grupos_plano.py.

Ou seja: a regra já foi escrita a 27/10, mas a 01/11 o Danilo viu uma story com loja "em breve".
Há três buracos possíveis, por ordem de probabilidade — a missão do PC confirma na VPS qual é
(`grep -n lojas_permitidas /opt/data/scripts/*.sh /opt/data/social/*.py` e `/opt/data/social/log.md`
+ `/root/social-story.log` do dia 01/11).

## Estado real da base a 01/11/2026 20:30 UTC (SELECT)

Lojas que NUNCA podem sair numa story/peça (`restaurants`):

| id | nome | porquê |
|---|---|---|
| `amaya-sushi-guarda` | Amaya Sushi Bar | coming_soon=true ("Em breve na Bora — a preparar fotos") |
| `boom-burger-guarda` | Boom! Burger | coming_soon=true, parceiro |
| `mrkebab-guarda` | Mr Kebab & Restaurant | coming_soon=true, parceiro |
| `demo-parceiro-loja` | Loja Demo Bora | coming_soon=true, demo |
| `lidl-guarda` | Lidl | is_active_admin=false |
| `mercadona-guarda` | Mercadona | is_active_admin=false (parada até "vamos reabrir a loja") |
| `pizzahut-guarda` | Pizza Hut | is_active_admin=false |

`service_providers`: Mister Navalha (`553a0d77…`), Ouro e Prata (`82e3162c…`) e BeUnique
(`192c7d0b…`) estão coming_soon=true; Barbearia Bora Demo está pending/inativa.

Peças que saíram a 01/11 (e2e_log `porteiro-telegram`): story 10:01 e 19:31 "Qual é a loja da
Guarda que querias ver no Bora?" (ids IG 18118525072806214 / 18213148957365041), loja do dia 12:02
= KFC (`kfc-guarda`, aberta, ok), formato extra 15:01 (conteúdo não visível daqui).

## O patch (aplicar na VPS, ficheiro a ficheiro)

### 1. `lojas_permitidas.py` — a regra fica completa e única

Condição de loja permitida (as duas tabelas), substituir a atual por esta:

```python
def loja_permitida(r: dict) -> bool:
    return (
        r.get("coming_soon") is False
        and r.get("is_active_admin") is not False
        and r.get("approval_status") == "approved"
        and not r.get("is_demo", False)
        and r["id"] not in EXCLUIR
        and r.get("id", "").startswith("demo-") is False
        and r.get("produtos_disponiveis", 0) > 0        # só restaurants; service_providers não têm produtos
    )
```

Fonte dos dados: trocar a leitura direta das tabelas pela RPC nova
`public.social_lojas_permitidas()` (aplicada a 01/11, ver secção 4), que já devolve só o que pode
sair e o número de produtos disponíveis, com a chave anónima:

```python
r = requests.post(f"{SUPABASE_URL}/rest/v1/rpc/social_lojas_permitidas",
                  headers={"apikey": ANON, "Authorization": f"Bearer {ANON}",
                           "Content-Type": "application/json"}, json={}, timeout=15)
if r.status_code != 200: sys.exit(4)        # sem base, não sai peça de loja (regra de 27/10)
permitidas = {x["id"]: x for x in r.json()}
```

`EXCLUIR` fica como está (Ouro e Prata, Mr Kebab x2, Boom) — é a vontade do Danilo até ele
dizer "abre"; mas a RPC já os tira sozinha porque estão coming_soon.

### 2. `social-story.sh` + `story_pergunta.py` — a story nunca mostra loja fora da lista

- A foto real (dias pares) só pode vir de `/opt/data/social/parceiros/<slug>/` se `<slug>`
  estiver em `permitidas` (mapear slug → id em `parceiros-fotos.json`; `ouro-e-prata`,
  `sabores-do-brasil` e `goola` têm de ser conferidos contra a RPC: Ouro e Prata está
  coming_soon=true → NÃO sai).
- A lista fixa de 7 perguntas não pode ter nome de loja; se tiver (`grep -n "Ouro\|Kebab\|Boom\|
  Amaya\|Navalha" /opt/data/scripts/social-story.sh /opt/data/social/story_pergunta.py`), trocar
  por perguntas genéricas.
- Antes de publicar: `python3 /opt/data/social/lojas_permitidas.py --verifica "<slug ou id>"`
  tem de devolver 0; qualquer outro código → não publica e escreve no log + Telegram
  (`info:social-story` já existe no porteiro).

### 3. `social-loja-do-dia.sh` / `proxima_loja.py` / `formato_extra.py` / `carrossel.py` / `grupos_plano.py`

- Linha de `rotacao.md` do dia: antes de montar a cena, `--verifica <id>`; se falhar, marcar a
  linha como `SALTADA (em breve)` e chamar `proxima_loja.py` para escolher outra permitida.
- `proxima_loja.py`: a candidatura vem só de `permitidas` (RPC), ordenada parceiro → grande como
  já estava, e a rotação atrasa 3 dias (erro (b) de 27/10) — corrigir a data base para `hoje`.
- `formato_extra.py` e `carrossel.py` (série parceiros, `series-carrossel.json`): filtrar as
  páginas pelo mesmo `permitidas`; a biblioteca dos grupos (`grupos_plano.py`) idem.
- Produtos nas peças: só `products.is_available = true` (a RPC já conta só esses).

### 4. O que já ficou feito do lado do Supabase (01/11)

RPC `public.social_lojas_permitidas()` — leitura só, SECURITY DEFINER, aberta a `anon` de
propósito (motivo: o robô da VPS usa a chave anónima; devolve só id, nome, categoria, tipo,
is_partner e contagem de produtos — nada sensível; nomes de lojas já são públicos na app).
Migração no repo: `supabase/migrations/20261101213000_social_lojas_permitidas_2026_11_01.sql`.

Prova (SELECT a 01/11): a RPC devolve 0 linhas com Amaya, Boom, Mr Kebab, Lidl, Mercadona,
Pizza Hut, Loja Demo, Mister Navalha, Ouro e Prata, BeUnique.

### 5. Prova a fazer na VPS depois do patch

```
SOCIAL_DRY_RUN=1 bash /opt/data/scripts/social-story.sh            # dias par e ímpar (forçar com DATA=)
SOCIAL_DRY_RUN=1 bash /opt/data/scripts/social-loja-do-dia.sh      # com rotacao de ensaio a começar por boom-burger-guarda → código 3
python3 /opt/data/social/lojas_permitidas.py --lista               # tem de bater com a RPC
```
e registar no e2e_log fluxo `stories-em-breve-2026-11-01` (passo por script, com o código de
saída e o nome da loja escolhida).
