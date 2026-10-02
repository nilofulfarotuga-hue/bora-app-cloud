# Assistente de Negócio no WhatsApp ("funcionário digital")

Missão de 2026-10-01. Primeiro cliente: **Barbearia Mister Navalha** (modo teste).

## Peças

| peça | onde vive | o que faz |
|---|---|---|
| `assistant_tenants` (+ `assistant_contacts`, `assistant_messages`, `assistant_tasks`) | Supabase | um cliente por linha: modo, allowlist, blocklist, dono, ficha, perguntas aprendidas, motor, orçamento |
| `assistente_vagas/marcar/desmarcar/remarcar/minhas_marcacoes/aviso_enviado` | Supabase (service role) | a agenda — usa `get_available_slots`, a MESMA lógica de vagas da app |
| `admin_assistente_resumo`, `admin_assistente_limpar_testes` | Supabase (admin) | painel |
| `servidor.py` (`assistente-negocio.service`, 127.0.0.1:8795) | VPS `/opt/assistente-negocio` | recebe da porta, fila de saída própria, rotinas de minuto a minuto |
| `assistente.py` → `atender(evento)` | idem | o cérebro: uma única entrada, usada pela porta e pelas simulações |
| `ligar.js` | VPS `/root/whatsapp-bora` (cópia em `ferramentas/whatsapp-loja/vps/`) | a porta Baileys: pergunta primeiro ao assistente "é teu?"; se não for, segue o caminho antigo da Bora (que continua pausado) |

## Encaminhamento

1. Grupo → nunca.
2. Número na blocklist do cliente → silêncio.
3. Modo `teste` → só a allowlist. Modo `ligado` → todos os que escrevem para a sessão (cuidado: a sessão de hoje é o número da Bora). Modo `desligado` → nada.
4. Tudo o que não é de um assistente segue exatamente o caminho antigo (cérebro da Bora, `envio_ligado=false`).
5. Saída: dupla rede — `enfileirar()` recusa números fora da allowlist e `/pendentes` volta a verificar antes de dar à porta.
6. A fila do assistente não obedece ao interruptor da Bora (`ENVIO_DESLIGADO`/`envio_ligado`); só ao modo do cliente.

## Cérebro

- Motor: `motor` do cliente (pago) primeiro; depois `motores_reserva`. Motor que responde 403/429 fica de castigo uns minutos. Se cair a meio de uma resposta, o histórico de ferramentas passa a texto para o motor seguinte (o Gemini recusa chamadas feitas por outro motor).
- Custo real por mensagem em `assistant_messages.custo_eur` (motores grátis = 0). Tecto `orcamento_mensal_eur`; aos 80 % avisa no Telegram; aos 100 % só motores grátis.
- Filtro pessoal/negócio antes de responder (motor barato; poupado a meio de uma conversa de marcação).
- "Vou verificar" sem tarefa é impossível: se a resposta promete voltar sem `perguntar_ao_dono`, a tarefa cria-se sozinha.
- Pergunta ao dono: mensagem com código `P123` para `dono_destino`; o dono responde a citar ou com `P123 resposta`; o cliente recebe e a resposta fica em `knowledge.perguntas_aprendidas`. Vigia: 30 min → lembra o dono; +60 min → diz ao cliente que ainda espera; +12 h → expira e avisa no Telegram.
- Dono escreveu à mão na conversa (do telemóvel do negócio) → assistente calado 12 h nessa conversa.
- Depois de cada marcação confirmada, segunda mensagem curta com `knowledge.ficha.apos_marcacao` (uma vez por marcação; `motivo = apos_marcacao:<id>`).

## Áudios (adendo 2, 02/10)

- Nota de voz do cliente → `voz.ouvir()`: Groq `whisper-large-v3-turbo` (grátis) → reserva `faster-whisper` base local
  (`/opt/assistente-negocio/.venv-whisper`; o ffmpeg descodifica para PCM porque o `av` rebentava). O texto segue pelo
  MESMO `atender()`; a entrada fica registada como `🎤 <transcrição>` com `motivo=audio:<motor>`.
- **Adendo 3 (02/10):** cliente mandou áudio → resposta **SÓ em áudio** (nada de texto; as horas lêem-se por extenso; a
  mensagem da app diz "misternavalha ponto boraguarda ponto com"). Cliente escreveu → só texto. Voz **masculina**
  `pt-PT-DuarteNeural` → ogg/opus mono 48 kHz → `assistant_messages.media_path`; a porta envia como PTT. Se a voz falhar,
  vai em texto.
- Áudio pessoal → silêncio (o filtro corre sobre a transcrição). Áudio que não se percebe → pede para repetir ou escrever.
- **Chamadas de voz: NÃO.** O Baileys não as atende. Passo futuro, com a API oficial do WhatsApp (Cloud API).

## Motores (decisão do Danilo, 02/10)

Principal: OpenCode Go (`go:glm-5.2`, assinatura paga já existente). O tecto da chave Google com faturação NÃO se sobe.
Enquanto o Go devolver o limite mensal (429 `GoUsageLimitError`, medido 01–02/10), fica de castigo 1 h e respondem os
grátis: Gemini 3 Flash (dois projetos) → Flash-Lite → Groq.

## Rotinas (minuto a minuto, idempotentes pela base)

Lembrete na véspera às 18:00 (ou 2 h antes se marcada depois disso) · pedido de avaliação 1 h depois do fim · reativação aos 35 dias · lista de espera (vaga oferecida quando alguém desmarca/remarca) · resumo ao dono ao domingo 20:00 · aviso de orçamento.

## Comandos (na VPS)

```
systemctl status assistente-negocio
tail -f /opt/assistente-negocio/assistente.log
cd /opt/assistente-negocio && python3 simular.py            # conversas simuladas (não sai nada)
python3 simular.py --limpar                                   # cancela marcações de teste + esquece respostas simuladas
python3 sonda_motores.py                                      # que motores respondem agora
python3 prova_real.py 351931992662 "texto"                    # 1 mensagem real + espera pelo aviso de entrega
```

Instalar/atualizar: copiar a pasta para `/tmp/assistente-negocio` e `bash /tmp/assistente-negocio/vps/instalar.sh`
(as chaves copiam-se de `.env` para `.env`, nunca passam pelo ecrã).
