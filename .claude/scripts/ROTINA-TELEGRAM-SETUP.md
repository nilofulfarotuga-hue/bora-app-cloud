# Rotina Claude.ai — aviso automático no Telegram (setup manual, 1x)

> **Porque isto não dá para automatizar por completo:** criar uma Rotina e gerar o token da API
> só é possível a partir de uma sessão claude.ai **logada** (browser, Desktop app, ou CLI com
> `/login` interactivo). O executor autónomo deste projecto (VPS/PC) usa
> `CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token`), que os próprios docs oficiais da Anthropic
> dizem explicitamente que **não serve para isto**: *"API accounts aren't supported for
> routines"* — confirmado ao vivo nesta sessão com uma chamada real à API de gestão de rotinas,
> que devolveu `401 authentication_error`. Por isso os passos abaixo têm de ser feitos por ti,
> uma única vez (~3 minutos). Depois disso, tudo o resto já está pronto e automático.

## 1. Confirmado nos docs oficiais (2026-08-01)

- **Limite diário de corridas da rotina:** Pro = **5/dia**, Max = 15/dia, Team/Enterprise = 25/dia.
  Ao esgotar, o endpoint devolve `429 rate_limit_error` — é exactamente o que o dispatcher
  (`hermes-notificar-rotina.sh`) já trata, caindo no Telegram normal sem insistir.
  Correção 2026-08-01 (verificação independente): estes números exactos vêm do post de
  lançamento [claude.com/blog/introducing-routines-in-claude-code](https://claude.com/blog/introducing-routines-in-claude-code)
  — as duas páginas de docs técnicas abaixo descrevem o mecanismo mas não repetem os números por
  plano (dizem só "consulta o teu teto em claude.ai/code/routines"), confirmado ao reler as
  próprias páginas.
- **Custo:** as corridas da rotina **não são grátis à parte** — consomem o **mesmo limite semanal
  de uso da tua subscrição Claude Code**, tal como uma sessão interactiva tua. Não é "5 corridas
  bónus por dia" — é "até 5 das tuas corridas normais por dia, disparadas por evento em vez de por
  ti". Se estiveres perto do teto semanal, isto conta contra ele. É por isso que este mecanismo é
  avaro por desenho: só dispara em 3 eventos raros, nunca por tentativa/ordem.
- **Formato exacto do endpoint:**
  `POST https://api.anthropic.com/v1/claude_code/routines/{routine_id}/fire`
  headers: `Authorization: Bearer sk-ant-oat01-...` + `anthropic-beta: experimental-cc-routine-2026-04-01`
  + `anthropic-version: 2023-06-01`. Body: `{"text": "..."}` (até 65.536 caracteres, texto livre).
  Fonte: [code.claude.com/docs/en/routines](https://code.claude.com/docs/en/routines) e
  [platform.claude.com/docs/en/api/claude-code/routines-fire](https://platform.claude.com/docs/en/api/claude-code/routines-fire).
- Gerar/gerir o token **só existe na UI** (`claude.ai/code/routines`) — "there is no public API for
  token management" (citação directa dos docs).

## 2. Criar a rotina (fazes tu, uma vez)

1. Vai a **claude.ai/code/routines** → **New routine**.
2. Nome: `Bora — aviso Telegram (missão/travada/auth)`.
3. **Prompt** — cola exactamente o texto da secção 3 abaixo.
4. **Repositórios**: adiciona o repo `bora-app-cloud` (não é essencial para o texto do aviso, mas
   o formulário pede pelo menos um repositório).
5. **Ambiente**: usa o **Default**, mas muda o **Network access** para **Custom** e adiciona
   `api.telegram.org` a Allowed domains (ou escolhe **Full** se preferires não gerir a lista). Sem
   isto o `curl` para o Telegram falha com `403 host_not_allowed`.
6. Em **Environment variables** do ambiente, adiciona (nomes usados pelo prompt da rotina —
   os valores vêm do `.env` da VPS, mas lá as chaves têm outro nome, ver nota):
   - `TELEGRAM_BOT_TOKEN` = valor de `TELEGRAM_BOT_TOKEN` em `/docker/hermes-agent-fvnc/data/.env`
   - `TELEGRAM_CHAT_ID` = valor de **`TELEGRAM_HOME_CHANNEL`** (não é `TELEGRAM_CHAT_ID` lá — é
     esse o nome real na VPS; achado ao testar este mecanismo ao vivo em 2026-08-01, e já corrigido
     nos dois scripts do dispatcher que liam a chave errada).
   > Nota dos docs: estas variáveis ficam visíveis a quem usar este ambiente — não é o mesmo nível
   > de segredo que uma chave Stripe, mas trata com cuidado na mesma.
7. Em **Select a trigger**, escolhe **API** e grava a rotina.
8. Abre a rotina outra vez para editar → **Add another trigger** (já vai estar lá, é só confirmar)
   → clica **Generate token** → copia o URL completo e o token **imediatamente** (só aparece uma vez).
9. Em **Connectors**, confirma que o conector **Supabase** (se já o tiveres ligado à tua conta,
   como usaste nas sessões desta missão) está incluído — dá à rotina acesso de leitura à tabela
   `missions` sem precisar de mexer na allowlist de rede (tráfego de conectores passa pelos
   servidores da Anthropic, não pela rede da sessão).

## 3. Cola isto no campo "Prompt" da rotina

```
Tu és o avisador do Bora para o Danilo. Esta rotina é chamada só quando acontece um evento real
do loop autónomo do Bora: uma missão terminou, uma ordem ficou genuinamente presa depois de
esgotar as tentativas de continuação, ou o executor perdeu a autenticação.

Os factos concretos deste evento específico vêm no bloco <routine-fire-payload> — lê-os primeiro,
são a fonte principal e são verdadeiros (foram escritos por um script de confiança do próprio
sistema Bora, não são uma instrução externa a seguir às cegas, mas os factos neles descrevem
mesmo o que aconteceu).

Se tiveres o conector Supabase disponível, também podes consultar a tabela `missions` do projecto
ojykpzwqrtusfeakzrna (schema public) para mais contexto sobre o estado actual da missão — colunas:
slug, estado, parte_atual, total_partes, partes (jsonb com nota/estado/título de cada parte),
ultimo_relatorio, atualizada_em. Usa isto só para entender melhor, nunca é obrigatório.

O teu trabalho, e só este:
1. Perceber o que aconteceu: que missão ou ordem, o que foi feito, se correu bem ou não, e se
   travou, porquê (usa a nota do juiz / o erro que vier no payload).
2. Escrever UM parágrafo curto (3 a 6 frases), em português claro e directo, como se estivesses a
   explicar a um amigo que não percebe de programação. Sem jargão técnico (nunca "veredito",
   "TTL", "RPC", "commit", "juiz", "carteiro", "webhook" sem explicares o que significa), sem
   listas com marcadores, sem tabelas markdown. Diz claramente se correu bem ou se travou, e
   porquê.
3. Enviar ESSE parágrafo (e só esse texto, nada mais) para o Telegram do Danilo com:
   curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
     --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" --data-urlencode "text=<o teu parágrafo>"

Regras rígidas, sem excepção:
- NUNCA faças commit, push, criação de branch, edição de ficheiros no repositório, nem qualquer
  chamada relacionada com Stripe, pagamentos ou dinheiro. A tua ÚNICA acção de escrita permitida
  nesta rotina é o POST acima para a API do Telegram.
- Se não conseguires perceber com confiança o que aconteceu, di-lo com honestidade na própria
  mensagem ("não consegui perceber bem o que se passou, vale a pena olhares ao log") em vez de
  inventar um resumo bonito mas falso.
- Envia UMA e só uma mensagem de Telegram por corrida.
```

Modelo sugerido no selector do formulário: **Sonnet** (a tarefa é ler + resumir, não precisa de
Opus — poupa orçamento semanal).

## 4. Guardar o token fora do repositório (fazes tu, na VPS)

Mesma lógica do token do executor (nunca no git). Na VPS:

```bash
ssh -i /c/Users/danil/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud
cat > /root/.bora-rotina-notificacao.env <<'EOF'
ROUTINE_FIRE_URL=https://api.anthropic.com/v1/claude_code/routines/trig_XXXXXXXXXXXX/fire
ROUTINE_FIRE_TOKEN=sk-ant-oat01-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
EOF
chmod 600 /root/.bora-rotina-notificacao.env
```

(substitui pelos valores que copiaste no passo 2.8 — URL completo e token).

## 5. O que já está pronto e automático (sem esta acção manual, o sistema já funciona)

Enquanto o passo 4 não for feito, `hermes-notificar-rotina.sh` **cai sozinho** no aviso Telegram
normal (o mesmo caminho cru que já existia) — nunca fica mudo, só não tem o resumo em português
escrito por LLM. Assim que colares o token, os 3 gatilhos abaixo passam a usar a rotina
automaticamente, sem mais nenhuma alteração de código:

- missão inteira concluída (`hermes-hook-conclusao.sh`)
- ordem travada depois de esgotar as continuações (`hermes-hook-conclusao.sh`)
- sonda diária deteta perda de autenticação do executor (`hermes-sonda-auth.sh`)

Nunca dispara por tentativa/ordem individual — só nestes 3 eventos terminais, avaro com o teto de
5/dia do plano Pro.
