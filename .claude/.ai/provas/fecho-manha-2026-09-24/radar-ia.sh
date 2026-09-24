#!/usr/bin/env bash
# radar-ia.sh — RADAR DE IA SEMANAL do batedor (corre DENTRO do container hermes, user hermes).
# Fluxo: guardas -> recolhe material deterministico (texto + VIDEOS) -> o agente batedor
#        sintetiza (cadeia de modelos explicita) -> arquiva -> envia Telegram -> escreve na
#        caixa de entrada do Cortex -> regista tudo em _execucoes.log.
# Zona verde: nao toca em dinheiro, dispatch, RLS nem no codigo do app.
#
# 2026-09-24 (missao fecho-manha, bloco 4): passa a incluir NOVIDADES EM VIDEO (YouTube),
#   pelo colector radar-videos-collect.sh; cada achado (texto ou video) vai ao Telegram como
#   um resumo de 3 linhas em portugues do Brasil; a cadeia de modelos ganhou dois Gemini de
#   reserva (quotas separadas por modelo) porque a 17/09 e 20/09 o 3.6-flash deu 429 e os
#   dois do Zen nao responderam.
#
# Correr a mao:            RADAR_FORCE=1 bash /opt/data/scripts/radar-ia.sh
# Ensaio sem tocar na semana: RADAR_FORCE=1 RADAR_TESTE=1 bash /opt/data/scripts/radar-ia.sh
#   (grava em <semana>-teste.md, nao mexe no livro de bordo nem no Cortex, Telegram vai com [TESTE])
# Correr pelo cron:        bash /opt/data/scripts/radar-ia.sh   (guardas activas)
set -u

RADAR_DIR=/opt/data/radar
RUNLOG=$RADAR_DIR/_execucoes.log
CORTEX_INBOX=/opt/data/cortex-brain/.claude/.ai/knowledge/inbox
COLLECT=/opt/data/scripts/radar-collect.sh
VIDEOS=/opt/data/scripts/radar-videos-collect.sh
PROFILE=batedor
FORCE="${RADAR_FORCE:-0}"
TESTE="${RADAR_TESTE:-0}"

mkdir -p "$RADAR_DIR"

STAMP=$(TZ=Europe/Lisbon date +%Y-%m-%dT%H:%M:%S%z)
HORA_PT=$(TZ=Europe/Lisbon date +%H)
ANO=$(TZ=Europe/Lisbon date +%G)
SEM=$(TZ=Europe/Lisbon date +%V)
SLUG="$ANO-$SEM"
SUFIXO=""
[ "$TESTE" = "1" ] && SUFIXO="-teste"
OUT="$RADAR_DIR/$SLUG$SUFIXO.md"
MSG=/tmp/radar-msg-$SLUG$SUFIXO.txt
MAT=/tmp/radar-material-$SLUG$SUFIXO.txt

log() { echo "[$STAMP] $*" >> "$RUNLOG"; }

# ── 0. Guardas ─────────────────────────────────────────────────────────────────
# O gateway do Hermes corre o cron em UTC. Para acertar as 09:00 de Lisboa o ano
# inteiro (verao +01, inverno +00), o cron dispara as 08 E as 09 UTC e e' esta
# guarda que deixa passar so a hora certa do relogio de Lisboa.
if [ "$FORCE" != "1" ] && [ "$HORA_PT" != "09" ]; then
  log "SALTA: sao $HORA_PT em Lisboa, o radar so corre as 09"
  exit 0
fi

# Uma vez por semana. Se a semana ja tem relatorio, nao repete (nem que o cron dispare duas vezes).
if [ "$FORCE" != "1" ] && [ -f "$OUT" ]; then
  log "SALTA: a semana $SLUG ja tem radar em $OUT"
  exit 0
fi

log "START radar-ia semana $SLUG (force=$FORCE teste=$TESTE)"

# ── 1. Material deterministico (fontes gratis, sem chave) ───────────────────────
if ! timeout 420 bash "$COLLECT" > "$MAT" 2>/tmp/radar-collect.err; then
  log "FALHOU: colector rc!=0 — $(head -c 300 /tmp/radar-collect.err | tr '\n' ' ')"
  exit 1
fi
LINHAS=$(wc -l < "$MAT")
if [ "$LINHAS" -lt 20 ]; then
  log "FALHOU: material demasiado curto ($LINHAS linhas) — nao vale a pena chamar o modelo"
  exit 1
fi
log "material de texto recolhido: $LINHAS linhas"

# 1b. Videos (YouTube). Se o colector falhar, o radar segue so com texto — e diz-se no log.
N_VID=0; N_LEG=0
if [ -x "$VIDEOS" ] || [ -f "$VIDEOS" ]; then
  if timeout 600 bash "$VIDEOS" >> "$MAT" 2>/tmp/radar-videos.err; then
    N_VID=$(grep -c '^VIDEO ' "$MAT" 2>/dev/null); N_VID=${N_VID:-0}
    N_LEG=$(grep -c '^origem do texto: LEGENDA' "$MAT" 2>/dev/null); N_LEG=${N_LEG:-0}
    log "videos recolhidos: $N_VID ($N_LEG com legenda real)"
  else
    log "AVISO: colector de videos rc!=0 — segue so com texto — $(head -c 200 /tmp/radar-videos.err | tr '\n' ' ')"
  fi
else
  log "AVISO: $VIDEOS nao existe — segue so com texto"
fi

# ── 2. O que ja foi enviado em semanas anteriores (para nao repetir) ────────────
# Livro de bordo proprio dos links JA ENVIADOS. Nao se le isto dos ficheiros .md do arquivo:
# cada .md leva colado o material bruto das fontes (dezenas de links que NUNCA foram enviados),
# e esses afogavam os links verdadeiros — na corrida de prova de 2026-08-20 o batedor repetiu
# um achado por causa disso. O livro de bordo so tem o que saiu mesmo para o Telegram.
LEDGER="$RADAR_DIR/_ja_enviados.txt"
JA_ENVIADO=$(tail -60 "$LEDGER" 2>/dev/null | sort -u | tr '\n' ' ')
[ -z "$JA_ENVIADO" ] && JA_ENVIADO="(nenhum — este e o primeiro radar)"

# ── 3. Sintese pelo agente batedor ─────────────────────────────────────────────
PROMPT="Es o batedor (le a tua SOUL.md). E o radar de IA semanal do Danilo, semana $SLUG.

Analisa o MATERIAL em baixo — foi recolhido agora mesmo por mim, de fontes gratis
(API publica do GitHub, feeds RSS e pesquisa de VIDEOS no YouTube). So podes falar do que
esta ai ou do que confirmares com a ferramenta websearch. NAO uses web_extract. NAO inventes
nada: sem link real, nao entra.

Escolhe no MAXIMO 6 achados (pelo menos 2 devem ser VIDEOS, se houver videos com legenda ou
descricao que prestem) que sirvam mesmo a uma destas quatro frentes do Danilo:
(1) app Bora multi-vertical em Flutter e Supabase; (2) sites que ele vende a clientes e clubes;
(3) Bora Studio de animacao; (4) poupar dinheiro em modelos e APIs.
Se um achado nao servir nenhuma destas frentes, deita-o fora, por muito famoso que seja.
Se nada prestar, diz que esta semana nao apareceu nada que valha a pena e explica porque numa linha.

REGRA A - O QUE ELE JA TEM (inventario). Antes de recomendar seja o que for, ve se ja e dele.
JA TEM, e por isso NAO se recomenda: Claude Code Pro, OpenCode Go, Hermes com os tres bots
(fiscal, batedor, escriba), Agent-Reach, agent-skills, Impeccable, Cortex com carteiro e juiz,
Supabase, Stripe, Firebase, Codemagic. Se um achado for um destes, escreve so a linha
'ja tens: <nome do achado>' e passa ao seguinte - nao gastes um dos lugares com isso.

REGRA B - PRECO ANTES DA GAVETA. So podes escrever 'serve para: poupar dinheiro' depois de
confirmares que o achado NAO exige chave paga nem subscricao. Se exigir, e PROIBIDO po-lo
nessa gaveta: diz o preco e manda-o para outra frente, ou deixa-o de fora. Se nao conseguires
confirmar o preco na fonte, escreve 'preco nao confirmado' - nunca assumas que e gratis.

REGRA C - O HARDWARE DELE. O Danilo tem um PC de 4 GB de RAM e uma VPS de 4 GB com 1 core.
Se um achado precisar de mais do que isso para correr localmente, NAO o vendas como
alternativa local: mostra-o na mesma, mas com a frase 'nao roda no teu hardware'.

REGRA D - SO O TITULO (sem corpo real). No MATERIAL em baixo, os itens da fonte RSS/Atom so
trazem titulo, data e link — nunca o texto do artigo. Um repositorio do GitHub sem descricao
aparece marcado como sem descricao. Um VIDEO marcado 'origem do texto: SO O TITULO' nao tem
legenda nem descricao. Nesses casos e PROIBIDO concluir o que a coisa faz ou porque serve a
partir so do titulo ou do nome — nao adivinhes o conteudo pelo titulo, mesmo que pareca obvio
ou familiar. So podes escrever sobre um desses itens depois de confirmares o que ele e mesmo
com a ferramenta websearch. Se nao conseguires confirmar, nao gastes um dos achados nele.

REGRA E - VIDEOS. Um video com 'origem do texto: LEGENDA' tem a transcricao: podes resumir o
que e dito. Com 'origem do texto: DESCRICAO' so tens a descricao do canal: diz o que a
descricao promete, sem inventar o que o video mostra.

JA FORAM ENVIADOS EM SEMANAS ANTERIORES (nao repitas estes links): $JA_ENVIADO

FORMATO DA RESPOSTA — obrigatorio, o Danilo ouve isto em voz alta:
- Texto simples corrido em PORTUGUES DO BRASIL (o Danilo e brasileiro). SEM tabelas, SEM
  emojis, SEM markdown (nada de asteriscos, cardinais, tracos de lista, negrito).
- Comeca por uma linha: Radar de IA da semana $SLUG.
- Depois, cada achado tem EXATAMENTE 3 linhas, separadas dos outros por uma linha em branco:
  linha 1: o que e (se for video, comeca por 'Video:' e diz o canal), com o link escrito por extenso;
  linha 2: o que muda na pratica para o Danilo e quanto custa (gratis, limite do plano gratuito,
           preco, ou 'preco nao confirmado');
  linha 3: serve para: X (uma das quatro frentes, ou 'poupar dinheiro' so se cumprir a REGRA B).
- Se algum item ficou SO PELO TITULO sem conseguires confirmar (REGRA D), poe uma linha unica
  antes do veredito, comecada por 'vistos so pelo titulo, sem confirmar:', juntando todos,
  separados por virgula — sem opinar sobre nenhum deles.
- Acaba com uma linha unica comecada por: Veredito do batedor: — o que vale mesmo a pena
  e o que e so barulho.
- No maximo 3400 caracteres no total.

Responde SO com esse texto final. Nao escrevas ficheiros, nao envies mensagens, nao expliques
o que vais fazer.

MATERIAL:
$(cat "$MAT")"

# Cadeia de modelos, pela ordem: gemini-3.6-flash primeiro (provado com tools em 2026-08-19);
# gemini-3.1-flash-lite e gemini-3-flash-preview a seguir (2026-09-24: a quota gratis do Gemini
# e' POR MODELO, e o 3.6-flash deu 429 a 17/09 e 20/09 — os outros dois sao baldes diferentes);
# nemotron-3-ultra-free e hy3-free do OpenCode Zen como rede final.
# PROIBIDOS de proposito: deepseek-v4-flash-free e mimo-v2.5-free — devolvem 429 quando a
# chamada leva ferramentas. O fallback e' aqui, explicito e registado; o fallback_providers
# do config.yaml fica VAZIO para nunca mascarar uma falha em silencio.
CADEIA="gemini|gemini-3.6-flash gemini|gemini-3.1-flash-lite gemini|gemini-3-flash-preview opencode-zen|nemotron-3-ultra-free opencode-zen|hy3-free"

RESP=""
USADO=""
for PAR in $CADEIA; do
  PROV="${PAR%%|*}"
  MOD="${PAR##*|}"
  R=$(cd /opt/data && timeout 900 hermes -p "$PROFILE" --provider "$PROV" -m "$MOD" -z "$PROMPT" 2>&1)
  RC=$?
  TAM=$(printf '%s' "$R" | wc -c)
  if [ $RC -eq 0 ] && [ "$TAM" -ge 200 ] \
     && ! printf '%s' "$R" | head -3 | grep -qiE 'API call failed|HTTP (4|5)[0-9][0-9]|Traceback|rate limit|429'; then
    RESP="$R"
    USADO="$PROV/$MOD"
    log "MODELO OK: $USADO (rc=$RC, $TAM bytes)"
    break
  fi
  log "MODELO FALHOU: $PROV/$MOD rc=$RC tam=$TAM — $(printf '%s' "$R" | head -c 200 | tr '\n' ' ')"
done

# ── 4. Fail-closed: sem resposta boa, nao se inventa sucesso ───────────────────
if [ -z "$RESP" ]; then
  log "FALHOU: a cadeia de modelos toda falhou — nao ha relatorio esta semana"
  hermes send -t telegram -q "Radar de IA da semana $SLUG nao saiu. O batedor tentou os cinco modelos e nenhum respondeu. O material das fontes (texto e $N_VID videos) foi recolhido na mesma e esta guardado no servidor." 2>/dev/null
  exit 1
fi

# Telegram corta acima de 4096 caracteres — guarda de seguranca.
if [ "$TESTE" = "1" ]; then
  { printf '[TESTE do radar com videos — nao e o radar da semana]\n'; printf '%s\n' "$RESP"; } | head -c 3900 > "$MSG"
else
  printf '%s\n' "$RESP" | head -c 3900 > "$MSG"
fi

# Guarda os links deste relatorio no livro de bordo, para a semana que vem nao os repetir.
# (Em ensaio nao se escreve: o teste nao pode "gastar" achados da semana a serio.)
if [ "$TESTE" != "1" ]; then
  grep -ho 'https\?://[^ )]*' "$MSG" 2>/dev/null | sed 's/[.,;]*$//' | sort -u >> "$LEDGER"
fi

# ── 5. Arquivo ─────────────────────────────────────────────────────────────────
{
  echo "---"
  echo "id: radar-ia-$SLUG$SUFIXO"
  echo "tema: radar-ia"
  echo "estado: atual"
  echo "data: $(TZ=Europe/Lisbon date +%F)"
  echo "autor: batedor (Hermes, perfil batedor)"
  echo "gerado_em: $STAMP"
  echo "modelo: $USADO"
  echo "videos: $N_VID ($N_LEG com legenda)"
  echo "---"
  echo
  echo "# Radar de IA — semana $SLUG$SUFIXO"
  echo
  cat "$MSG"
  echo
  echo "---"
  echo
  echo "## Material bruto recolhido ($LINHAS linhas de texto + $N_VID videos, fontes gratis)"
  echo
  echo '```'
  cat "$MAT"
  echo '```'
} > "$OUT"
log "arquivo gravado: $OUT ($(wc -c < "$OUT") bytes)"

# ── 6. Telegram (com prova literal da resposta da plataforma) ──────────────────
ENVIO_JSON=$(hermes send -t telegram -f "$MSG" --json 2>&1)
RC_ENVIO=$?
log "TELEGRAM rc=$RC_ENVIO resposta=$(printf '%s' "$ENVIO_JSON" | tr '\n' ' ' | head -c 400)"
if [ $RC_ENVIO -eq 0 ]; then
  ENVIO="enviado ao Telegram"
else
  ENVIO="NAO enviado ao Telegram (falha de entrega)"
fi

# ── 7. Caixa de entrada do Cortex (nao em ensaio) ──────────────────────────────
if [ "$TESTE" = "1" ]; then
  log "ensaio: nao escreve no cortex inbox"
elif [ -d "$CORTEX_INBOX" ]; then
  {
    echo "---"
    echo "id: radar-ia-$SLUG"
    echo "tema: radar-ia"
    echo "estado: atual"
    echo "data: $(TZ=Europe/Lisbon date +%F)"
    echo "autor: batedor (radar de IA semanal)"
    echo "---"
    echo
    echo "# Radar de IA — semana $SLUG"
    echo
    echo "Relatorio completo: \`$OUT\`. Estado do envio: $ENVIO. Modelo usado: $USADO."
    echo "Fontes: API publica do GitHub (6 topicos) + 6 feeds RSS + $N_VID videos do YouTube ($N_LEG com legenda). Sem chave paga, sem web_extract."
    echo
    cat "$MSG"
  } > "$CORTEX_INBOX/radar-ia-$SLUG.md"
  log "cortex inbox: $CORTEX_INBOX/radar-ia-$SLUG.md"
else
  log "cortex inbox nao encontrado em $CORTEX_INBOX"
fi

log "FIM radar-ia semana $SLUG$SUFIXO"

# Silencio no stdout quando corre pelo cron (--no-agent trata stdout vazio como "nada a dizer").
[ "$FORCE" = "1" ] && echo "$OUT"
exit 0
