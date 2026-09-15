# Fix — áudio do Hermes "volta para o anterior em vez de parar"

Diagnóstico e solução (pesquisa 2026-06-29).

## Sintoma
No Telegram, quando o Hermes responde por voz (TTS), ao terminar/parar um áudio
o player **salta para o áudio anterior** em vez de parar.

## Causa (NÃO é bug do TTS nem da ponte)
É o **autoplay de mensagens de voz consecutivas do próprio cliente Telegram**.
O Telegram encadeia automaticamente voice notes/round-videos seguidas: quando uma
acaba (ou é parada), reproduz a adjacente. Há um bug conhecido e reportado há anos
em que esse salto vai para a **anterior** em vez da seguinte. É comportamento do
cliente — não existe setting do utilizador para desligar, e não se corrige no TTS.

Gatilho do lado do Hermes: o bot envia **várias voice notes seguidas** (ex.: a
resposta é dividida em vários `sendVoice`), criando a cadeia de autoplay.

## Solução (no bot do Hermes, dentro do container `hermes-agent-fvnc` na VPS)
Ordem de preferência — qualquer uma quebra a cadeia de autoplay:

1. **1 resposta = 1 voice note.** Não dividir o TTS em vários `sendVoice`
   consecutivos. Concatenar o texto e gerar/enviar UM único OGG/Opus. (Melhor fix.)
2. **Quebrar a cadeia com texto.** O autoplay só encadeia voz↔voz sem nada no meio.
   Enviar a transcrição em texto **entre** voice notes desliga o salto automático.
3. **`sendAudio` em vez de `sendVoice`.** Enviar como ficheiro de áudio (não voice
   note) não dispara o autoplay-de-voz consecutivo. Custo: perde a UI de voice note.

Recomendado: **opção 1** (single voice note por resposta) + **opção 2** como rede
(mandar sempre a transcrição em texto junto, o que também ajuda quando o áudio falha).

## Verificação extra (se persistir mesmo com 1 só voice note)
Confirmar que o pipeline TTS **não reutiliza file_id / nome de ficheiro fixo**:
- Se o bot cacheia `voice.file_id` e reenvia, o Telegram serve o áudio ANTIGO.
- Se escreve sempre `out.ogg` no mesmo path e há corrida (envia antes de acabar de
  gravar), envia o áudio anterior.
- Fix: nome de ficheiro único por mensagem (timestamp/uuid) e fazer upload do
  ficheiro novo (não reusar file_id) sempre que o texto muda.

## Onde aplicar
Código do bot que faz TTS→Telegram vive na VPS, dentro do container Docker
`hermes-agent-fvnc-hermes-agent-1` (não está no PC local). Localizar a chamada
`sendVoice`/geração de OGG e aplicar a opção 1.

## Fontes
- Telegram Desktop #3649 — pedido para desligar autoplay de voz/áudio/vídeo
- bugs.telegram.org/c/7980 — auto-jump da voice note (bug do salto)
- core.telegram.org/bots/api — sendVoice (audio/ogg, ≤1MB) vs sendAudio; reuso de file_id
