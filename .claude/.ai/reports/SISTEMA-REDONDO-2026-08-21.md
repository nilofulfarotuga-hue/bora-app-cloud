# SISTEMA REDONDO — relatório final · 2026-08-21

> Sessão nova, motor Opus. Retomada a partir de `ORDEM-sistema-redondo-RETOMAR.md`.
> `e2e_log` id **848**, `fluxo=sistema-redondo-2026-08-20`.

**Resumo:** 5 blocos fechados, 1 decidido sem instalar. Dois deles tinham a
**premissa errada** — e é isso que este relatório traz de mais útil.

---

## BLOCO 1 — as três regras do batedor ✅ FEITO

Ficheiro: `/opt/data/scripts/radar-ia.sh` (o `profile.yaml` é decorativo, como a
sessão anterior provou). O prompt é a variável `PROMPT=` na linha 71.

Cópia de segurança antes de tocar: `radar-ia.sh.bak_20260821` (8996 bytes).

**Tropecei uma vez, e vale a pena ficar registado:** na primeira tentativa pus
**aspas duplas** dentro do texto das regras. Como o prompt vive dentro de
`PROMPT="..."`, a primeira aspa fechou a string a meio e o script rebentou com
`line 87: nome: No such file or directory` e `PROMPT: unbound variable`.
Repus pela cópia e refiz só com plicas.

**Lição:** o `bash -n` disse **SINTAXE OK** com a string partida — porque o
ficheiro continuava a ser bash válido, só com outro significado. `bash -n` não
chega; é preciso validar o **conteúdo da variável**. Passei a contar as aspas
dentro do bloco `PROMPT`: tem de haver exactamente **1** (a de abertura).

### Prova ao vivo — corrida `RADAR_FORCE=1`

```
[2026-08-21T17:13:55+0100] MODELO OK: gemini/gemini-3.6-flash (rc=0, 1922 bytes)
[2026-08-21T17:13:55+0100] arquivo gravado: /opt/data/radar/2026-34.md (16345 bytes)
[2026-08-21T17:13:55+0100] TELEGRAM rc=0 ... "message_id": "4517"
```

Saída do batedor, com as três regras a disparar:

```
Radar de IA da semana 2026-34.

ja tens: Hermes com os tres bots
ja tens: agent-skills
ja tens: Supabase
...
O HeyGen Avatar IV ... E um servico comercial pago por subscricao ...
e serve para: Bora Studio.
...
O LFM2.5-DSpark ... E totalmente gratis para descarregar, mas nao corre no teu
hardware. ... e serve para: poupar dinheiro em modelos e APIs.
```

- **Regra A (inventário):** 3 rejeições. Era isto que recomendava o Agent-Reach duas vezes.
- **Regra B (preço):** o HeyGen é pago → foi para *Bora Studio*, **não** para "poupar dinheiro".
- **Regra C (hardware):** a frase exigida, à letra.

O `2026-34.md` anterior ficou guardado em `_guardado-antes-das-regras-2026-34.md`.

## BLOCO 2 — já estava fechado ✅

Confirmado pela sessão anterior. Semana 33 não existe e não se recupera (feeds ao
vivo, sem janela de datas; `_execucoes.log` começa a 20/08).

## BLOCO 3 — JÁ EXISTIA ✅

A proposta `ordem-20260811160435-2540` foi executada a **17/08** (`ref-fd100e`):

> *"F1 (blindagem anti-mentira: 5 medidas VERIFICADAS no loop vivo) ... a prova
> material já barra fecho sem entrega (provado nos 2 lados da sonda), M5 fechou
> **502 ordens travadas** históricas com ledger e backup (0 apagadas)."*

Os "2 lados da sonda" são as duas ordens-canário que a proposta exigia: a que
passa e a que é barrada.

**Não fiquei pela palavra do relatório.** Confirmei ao vivo:

| Medida | Estado | Prova |
|---|---|---|
| M1 prova material | já existia | **7** ocorrências de prova material / `prova_incompleta` no `carteiro.sh` vivo |
| M2 um só ficheiro | já existia | sem espelho no `cortex-brain` |
| M3 entrada real | já existia | relatório de 17/08 |
| M4 log real anexo | **já existia, com reserva** | ver abaixo |
| M5 nada pendente | já existia | 502 ordens fechadas |

**A reserva do M4:** a medida dizia "proibir `2>/dev/null` nos caminhos do loop" e
ainda há **53** no `carteiro.sh`. Amostrei-os: são guardas de "ficheiro pode não
existir" (`grep`/`awk` em ficheiros opcionais), não silenciamento de erros de
execução. **6** aparecem em linhas do caminho de execução e mereciam uma passagem
dedicada. Não declaro esta medida fechada a 100%.

## BLOCO 4 — a premissa estava ERRADA ✅ CORRIGIDO

A ordem dizia *"o `cortex_nightly.py` não corre desde 8 de Julho"*. **Corre todos
os dias.** O cron está vivo (`5 7 * * *`) e o log foi escrito **hoje às 07:05**.

O que enganava: o `_debt.md` mostra `ultima_confirmacao: 2026-07-08` e a secção
*"Primeira geração (parcial — 2026-07-08)"*. Quem olhou para ali concluiu que
estava morto.

**A causa real, na própria fonte do script:**

```
DRY-RUN por defeito: PROPOE (escreve um relatorio); so aplica com --apply
--apply → move inbox vencido p/ _descartado + reescreve _debt.md
```

Corria em **dry-run**: via 445 páginas para descartar e não descartava nenhuma.
Daí o cérebro crescer seis semanas. E o `_debt.md` só é reescrito no `--apply` —
por isso a data ficou congelada.

**Números reais que a ordem pedia** (corrida de hoje):

```
# Cortex nightly — 2026-08-21
## Divida (0 paginas)
## Inbox aging (>14d): 445
## Zona vermelha (so PROPOSTA, nunca auto): 11
## Contradiction scan — 0 contradicoes
```

**Apliquei**, com cópia antes (`inbox-antes-do-apply-20260821.tgz`, 618 KB):

| | |
|---|---|
| inbox antes | **649** ficheiros |
| inbox depois | **204** |
| movidos p/ `_descartado` | **445** |
| soma | 204 + 445 = **649** — nada se perdeu |
| `_debt.md` | `2026-07-08` → **`2026-08-21`** |

`--apply` **move**, não apaga — é a regra dos três baldes do projecto.

## BLOCO 6 — NÃO SE LIGA ❌ (premissa também errada)

A ordem partia de *"o Agent-Reach lê conteúdos da web sem taxas de API"*.
**Não lê.** O CLI instalado não tem comando de extracção:

```
{setup, install, configure, doctor, uninstall, skill, format,
 transcribe, check-update, watch, version}
```

Não há `fetch`, `read`, `extract` nem `get`. O único comando de conteúdo é
`transcribe` — *"Whisper via **Groq/OpenAI**"*, chave paga.

No código: `GROQ_API_KEY` ×16 (em `xiaoyuzhou.py`, transcrição de podcasts),
`TWITTER_AUTH_TOKEN`, `GITHUB_TOKEN`. Endpoints: `api.groq.com`,
`api.openai.com` e **`mcp.exa.ai`** — o Exa é justamente um dos extractores pagos
que já estavam bloqueados.

**O buraco do `web_extract` continua aberto.** O Agent-Reach dá acesso a
*plataformas* com sessão (LinkedIn, Twitter, GitHub), não a páginas quaisquer.

## BLOCO 5 — NÃO INSTALADO ⏸️ (dinheiro passa, hardware não)

**A porta do dinheiro PASSA.** O README mostra BYOK explícito:

> *"The BYOK proxy at `POST /api/proxy/{anthropic,openai,azure,**google**,ollama,
> senseaudio}/stream` — paste `baseUrl` + `apiKey` + `model`, with presets for
> OpenAI, Atlas Cloud, Anthropic, Azure OpenAI, **Google Gemini**, Ollama..."*

Corre com o `GEMINI_API_KEY` que ele já tem. **0 EUR novos, sem cartão.** O
`od mcp install claude` existe (e até suporta `hermes`). O OpenDesign Cloud
("one recharge") é **opcional**.

**A porta do hardware NÃO passa.** A arquitectura é `Next.js 16 + daemon Express
local`, e o **MCP stdio server vive dentro desse daemon** — não há modo "só MCP".
Instalação: `docker compose up -d` ou `pnpm install`.

- PC: 4 GB, ~300 MB livres → fora de questão.
- VPS: 4 GB / 1 core, 2,3 GB livres → **é onde corre o loop do Hermes inteiro**.

Não meto um stack Next.js na máquina que segura o loop. É a mesma Regra C que
acabei de escrever no batedor: o achado não se esconde, só não se vende como
usável. **Fica proposto, com janela dedicada e plano de recuo.**

---

## PAINEL ADMIN

Nenhum bloco criou entidade nova para gerir — **não precisa** de ecrã novo.

## O QUE FICA POR FAZER

1. **M4 do bloco 3** — 6 `2>/dev/null` em linhas do caminho de execução do
   `carteiro.sh`, por auditar uma a uma.
2. **Bloco 5** — decidir se vale uma janela dedicada para o daemon na VPS.
3. **`web_extract`** — continua sem solução; o Agent-Reach não serve.
4. **Dívida de outra missão:** a captura no ecrã da persistente do TVDE a parar
   (código já em produção na 540; falta o telemóvel com carregador de parede).
5. **5 commits locais** parados de propósito — vão de boleia com a próxima
   alteração de código a sério.
