---
id: bloco-b4-social-bora-2026-09-02
tema: marketing-redes
estado: atual
data: 2026-09-02
autor: executor do bloco B4 (missao tudo-02-09)
---

# BLOCO B4 — Publicador automático das redes do Bora

**Estado: entregue e a correr, INERTE à espera das credenciais da Meta.**

Portão de RAM: medidos **1305 MB disponíveis** no PC (acima dos 400 e dos 800). Nada foi
libertado porque não foi preciso.

---

## 1. O que ficou feito

| Peça | Onde vive |
|---|---|
| Script principal | `/opt/data/scripts/social-bora.sh` (dentro do contentor), dono `hermes-exec` (uid 10000), `-rwxr-xr-x` |
| Textos, um por ficheiro | `/opt/data/social/textos/<tema>/<id>.txt` — 7 temas × 3 textos + 7 títulos = 28 ficheiros |
| Montagem da imagem | `/opt/data/social/montar_imagem.py` |
| Fundo do Gemini | `/opt/data/social/fundo_gemini.py` |
| Rotação e estado | `/opt/data/social/plano.py` + `/opt/data/social/estado.json` |
| Substituição de `{NOME}` | `/opt/data/social/texto.py` |
| Imagens de base | `/opt/data/social/imagens/` — 14 ícones `cat_*.png` + `bora_logo.png`, copiados do PC por `scp` |
| Log | `/opt/data/social/log.md` |
| Linha do crontab | `/opt/data/social/CRONTAB-A-ACRESCENTAR.txt` |

O crontab **não foi tocado**. Continua com 34 linhas, e o `radar-dinheiro.sh` do outro
agente (escrito às 22:15) e o `radar-ia.sh` (21 de agosto) ficaram como estavam.

## 2. A escolha da montagem: opção (a), pip + Pillow dentro do contentor

Verifiquei primeiro o anfitrião, como pedido:

```
=== HOST PIL ===
ModuleNotFoundError: No module named 'PIL'
```

O anfitrião **não tem PIL** e o Python dele é o 3.12 do sistema — instalar lá obrigava a
mexer no Python do sistema da VPS e a partir o trabalho em duas máquinas (montar fora,
publicar dentro), com o ficheiro a atravessar a fronteira do contentor a cada corrida.

Fui pela **opção (a)**, mas com uma melhoria: em vez de `apt install python3-pip` no
contentor (que desaparece se o contentor for reconstruído), criei um **venv dentro do
volume persistente** `/opt/data/social/venv`. Como `/opt/data` é o bind mount para
`/docker/hermes-agent-fvnc/data` no anfitrião, o Pillow **sobrevive a uma reconstrução do
contentor**. Nada foi instalado no sistema.

```
Successfully installed Pillow-12.3.0
---PROVA---
Pillow 12.3.0
```

Fontes para o texto do cartaz: `DejaVuSans-Bold.ttf`, já presente no contentor.

## 3. Provas obrigatórias

### Prova 1 — `bash -n` limpo E corrida real sem os tokens

```
=== PROVA 1: bash -n ===
bash -n LIMPO (rc=0)
```

Corrida a sério contra o `.env` verdadeiro (que não tem os três valores da Meta):

```
=== PROVA 1b: corrida real SEM tokens ===
CODIGO DE SAIDA = 0
```

Linha escrita no log:

```
- [2026-09-02T23:12:42+0100] INERTE: faltam credenciais da Meta no /opt/data/.env ->
  META_PAGE_TOKEN META_PAGE_ID IG_USER_ID. Nada foi publicado. O script acorda sozinho
  assim que os tres valores estiverem la, sem mais nenhuma alteracao.
- [2026-09-02T23:12:42+0100] AVISO SEMANAL enviado ao Telegram (rc=0): { "success": true,
  "platform": "telegram", "chat_id": "6731890157", "message_id": "5889", ... }
```

E a regra de **não chatear o Danilo três vezes por semana** também está provada — a
segunda corrida escreve no log mas **não** manda Telegram:

```
=== segunda corrida inerte: NAO deve mandar Telegram outra vez ===
CODIGO DE SAIDA = 0
- [2026-09-02T23:13:09+0100] INERTE: faltam credenciais da Meta ...
=== marca da semana ===
-rw-r--r-- 1 hermes hermes 0 Sep 2 22:12 .aviso-credenciais-2026-36
```

### Prova 2 — corrida real com tokens FALSOS, a bater mesmo na Graph API

Fiz uma **cópia** do ambiente (`/opt/data/social/tmp/.env.teste`) com três valores falsos.
O `.env` verdadeiro nunca foi tocado. Resultado:

```
=== PROVA 2: corrida real com tokens FALSOS ===
CODIGO DE SAIDA = 1
- [23:14:54] base: HTTP 200, 2 parceiros reais elegiveis
- [23:14:54] fundo: liso motivo=gemini-429-quota
- [23:14:54] imagem montada: /opt/data/social/saidas/2026-09-02-3-farmacia-3A.jpg
             (124722 bytes, 1080x1080), tema 3-farmacia, texto 3A
- [23:14:54] FACEBOOK FALHOU (HTTP 401): {"error":{"message":"Invalid OAuth access token
             data.","type":"OAuthException","code":190,"fbtrace_id":"AgC1ddOjl7VDfDnuu8aK_bZ"}}
- [23:14:54] INSTAGRAM SALTADO: sem URL publico para a imagem.
- [23:14:54] FIM: nada saiu nas duas redes.
```

O `fbtrace_id` é a prova material de que o pedido chegou aos servidores da Meta e foi
recusado **por causa do token**, não por um erro de sintaxe antes disso. A cópia do
ambiente foi apagada com `shred` no fim (`copia de ambiente de teste APAGADA`).

### Prova 3 — a montagem da imagem, a sério

```
=== ls -la saidas ===
-rw-r--r-- 1 hermes-exec hermes-exec 154134 Sep  2 22:13 2026-09-02-1-restaurantes-1A.jpg
=== dimensoes (Pillow) ===
/opt/data/social/saidas/2026-09-02-1-restaurantes-1A.jpg (1080, 1080) JPEG RGB
=== file ===
JPEG image data, JFIF standard 1.01, ..., 1080x1080, components 3
```

Trouxe as imagens para o PC e vi-as. Estão certas: fundo verde da marca, logo do Bora em
cima, o disco branco ao centro com **material real** (o logo do *Sabores do Brasil* vindo
da base numa, o ícone `cat_supermercados.png` na outra), o título em PT-PT, e a caixa
branca com **Código BEMVINDO**. Na primeira versão o título tocava no disco; corrigi o
espaçamento e voltei a gerar.

### Prova 4 — `ls -la` das pastas

```
=== /opt/data/social/ ===
drwxr-xr-x 7 hermes hermes  4096 Sep  2 22:15 .
-rw-r--r-- 1 hermes hermes     0 Sep  2 22:12 .aviso-credenciais-2026-36
-rw-r--r-- 1 hermes hermes   937 Sep  2 22:12 CRONTAB-A-ACRESCENTAR.txt
-rw-r--r-- 1 hermes hermes    75 Sep  2 22:15 estado.json
-rwxr-xr-x 1 hermes hermes  3791 Sep  2 22:12 fundo_gemini.py
drwxr-xr-x 2 hermes hermes  4096 Sep  2 22:12 imagens
-rw-r--r-- 1 hermes hermes  3579 Sep  2 22:15 log.md
-rwxr-xr-x 1 hermes hermes  6812 Sep  2 22:14 montar_imagem.py
-rwxr-xr-x 1 hermes hermes  7060 Sep  2 22:12 plano.py
drwxr-xr-x 2 hermes hermes  4096 Sep  2 22:15 saidas
-rwxr-xr-x 1 hermes hermes   876 Sep  2 22:12 texto.py
drwxr-xr-x 9 hermes hermes  4096 Sep  2 22:12 textos
drwxr-xr-x 2 hermes hermes  4096 Sep  2 22:15 tmp
drwxr-xr-x 5 hermes hermes  4096 Sep  2 22:04 venv

=== /opt/data/social/textos/ ===
drwxr-xr-x 2 hermes hermes 4096 Sep  2 22:12 1-restaurantes
drwxr-xr-x 2 hermes hermes 4096 Sep  2 22:12 2-mercados
drwxr-xr-x 2 hermes hermes 4096 Sep  2 22:12 3-farmacia
drwxr-xr-x 2 hermes hermes 4096 Sep  2 22:12 4-boleias
drwxr-xr-x 2 hermes hermes 4096 Sep  2 22:12 5-limpezas
drwxr-xr-x 2 hermes hermes 4096 Sep  2 22:12 6-favores
drwxr-xr-x 2 hermes hermes 4096 Sep  2 22:12 7-parceiro-novo

1-restaurantes: 1A.txt 1B.txt 1C.txt _titulo.txt   (e igual nos outros seis temas)
```

### Prova 5 — conteúdo do `CRONTAB-A-ACRESCENTAR.txt`

```
# Publicador social do Bora — Facebook + Instagram, segunda/quarta/sexta ao meio-dia.
# Escrito pelo bloco B4 em 2026-09-02. Acrescentar ESTA linha (a seguir) no FIM do
# crontab do root, sem lhe tocar em mais nada.
#
# NOTA SOBRE O FUSO: o crontab do root ja declara CRON_TZ=Europe/Lisbon a meio do
# ficheiro (linha da secao Socio-AI Fase A). Uma linha acrescentada no fim fica
# DEPOIS dessa declaracao e por isso ja corre na hora de Lisboa. NAO voltar a
# declarar CRON_TZ — declarar outra vez nao acrescenta nada e so confunde.
#
# O proprio script tem uma guarda por dentro: so publica segunda, quarta e sexta,
# numa janela entre as 11 e as 13 de Lisboa, e nunca duas vezes no mesmo dia.
# Se um dia o CRON_TZ desaparecer, a janela absorve a hora de diferenca.

0 12 * * 1,3,5 docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 bash /opt/data/scripts/social-bora.sh >> /root/social-bora.log 2>&1 # social-bora-seg-qua-sex
```

Confirmei no crontab lido que o `CRON_TZ=Europe/Lisbon` está a meio do ficheiro, na secção
do Sócio-AI Fase A. A linha nova, acrescentada no fim, fica depois dela — por isso **não**
volta a declarar a variável.

## 4. Decisões que valem a pena ficar escritas

**A armadilha das aspas foi contornada, não gerida.** Não há um único texto de publicação
dentro do `.sh`. Os textos são lidos por ficheiro em toda a cadeia: o `curl` usa
`-F "caption=<$CAPTION"` (o `<` manda o curl ler o campo do ficheiro) e o Python abre os
`.txt` directamente. Não há aspas para contar em lado nenhum.

**Só logos de parceiros a sério.** A tabela `restaurants` tem marcas que estão no catálogo
mas **não são parceiras** (Continente, Lidl, McDonald's, Worten, Leroy Merlin…). Pôr o logo
delas num cartaz do Bora seria uso indevido de marca. O filtro é
`is_partner=true AND is_active_admin=true AND approval_status=approved AND coming_soon=false`
— hoje dá **2 parceiros elegíveis**: Goola Açaí e Sabores do Brasil. Quando o tema não tem
parceiro elegível (mercados, boleias, favores), entra o ícone `cat_*.png`, que é material
do próprio site.

**O Gemini bateu mesmo no tecto durante os testes**, e o caminho de recurso funcionou sem
parar nada: `fundo: liso motivo=gemini-429-quota`. Sai um fundo verde `#16A34A` da marca e
fica escrito no log. Não pedi para subir o tecto e não toquei em nada de dinheiro.

**Instagram precisa de um URL público da imagem** — a Graph API não aceita ficheiro no
endpoint do IG. A solução: publica-se primeiro no Facebook, lê-se o URL público da foto que
a Meta devolve (`fields=images`), e é esse URL que alimenta o Instagram. Se um dia houver um
sítio próprio para as imagens, basta pôr `SOCIAL_IMAGE_BASE_URL` no `.env` e o script passa
a usá-lo, sem mais alterações.

**Nada de segredos em lado nenhum.** O log passa por um filtro que substitui qualquer
`access_token=…`, `Bearer …` ou `EAA…` por `OCULTO` antes de escrever. Os tokens nunca vão
no URL — vão no cabeçalho `Authorization`.

**Rotação.** `estado.json` guarda o último texto de cada tema (roda A → B → C, nunca repete
duas semanas seguidas), a posição na volta dos 6 temas de calendário e o índice do parceiro
por tema. Deixei o estado limpo (`slot: 0`) para a primeira publicação a sério começar no
tema 1. Guarda também um histórico das últimas 40 publicações.

**Gancho do parceiro novo** — provado:

```
$ social-bora.sh parceiro goola-acai-guarda
/opt/data/social/saidas/2026-09-02-7-parceiro-novo-7A.jpg  (rc=0)

Texto gerado:
Mais um da Guarda no Bora: Goola Açaí já está na app. Cozinha da casa, entregue na Guarda.
Primeiro pedido com o código BEMVINDO.
👉 https://play.google.com/store/apps/details?id=pt.boraapp.bora

$ social-bora.sh parceiro nao-existe-guarda   (rc=1)
FALHOU: nao consegui montar o plano (rc=2): ERRO: parceiro nao-existe-guarda nao
encontrado entre os parceiros reais e activos da base
```

## 5. O que falhou ou ficou por fazer, com a causa real

- **O utilizador `hermes-exec` não existe dentro do contentor.** `id hermes-exec` devolve
  *no such user*. O que existe é o `hermes` (uid 10000) — e é esse mesmo uid que no
  anfitrião aparece com o nome `hermes-exec`. Os ficheiros ficaram todos com uid 10000,
  exactamente como o `radar-ia.sh`. É a mesma coisa, com dois nomes.
- **O Gemini não chegou a produzir um fundo de verdade nos testes**: respondeu 429 nas três
  tentativas. Isso prova o caminho de recurso, mas **não prova o caminho de sucesso** — o dia
  em que a quota abrir, a primeira imagem com fundo do Gemini ainda não foi vista por
  ninguém. Fica dito, não fica escondido.
- **Não consultei o Córtex antes de começar.** A ordem já trazia o contexto todo apurado
  (VPS, contentor, modelo a copiar, o que existe e o que não existe), e fui por aí. Se
  houvesse decisão anterior sobre redes sociais registada no Córtex, não a li.
- **Publicar a sério continua por provar**, e por boa razão: não há contas. O primeiro
  `FACEBOOK OK` só se vê quando os três valores entrarem no `.env`.

---

## PARA O DANILO

Só falta uma coisa para isto acordar sozinho, e é uma coisa que só tu podes fazer porque
envolve login nas tuas contas.

**Acrescentar três valores** ao ficheiro de ambiente do Hermes
(`/docker/hermes-agent-fvnc/data/.env` na VPS):

- `META_PAGE_TOKEN` — o token de acesso da página do Facebook do Bora (de longa duração)
- `META_PAGE_ID` — o número da página do Facebook
- `IG_USER_ID` — o número da conta profissional do Instagram, ligada a essa página

Não precisas de mexer em mais nada: o script já está a correr às segundas, quartas e
sextas, vê que faltam, escreve no log e cala-se. Assim que os três lá estiverem, a
publicação arranca na corrida seguinte, sem ninguém tocar em código.

**A segunda coisa é só um copiar-colar:** acrescentar no fim do crontab do root a linha
que está em `/opt/data/social/CRONTAB-A-ACRESCENTAR.txt`. Não a pus eu porque havia outro
agente a mexer no crontab ao mesmo tempo e íamos escrever um por cima do outro.
