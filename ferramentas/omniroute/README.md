# OmniRoute — o roteador de IA da VPS (missão `omniroute-23-10`, 23/10/2026)

Um só endereço que reparte os pedidos dos agentes por vários fornecedores de IA e, quando um
esgota ou cai, desce sozinho para o seguinte. Substitui o Motor Bora como porta principal dos
agentes; o Motor Bora fica de pé como **reserva** (último nível de cada combo) pelo menos até 30/10.

Cópia versionada. **O que corre é o da VPS**, em `/opt/omniroute/` (`srv1786862.hstgr.cloud`).

## Onde vive

- Contentor `omniroute` (`diegosouzapw/omniroute:3.8.52`), `restart: always`, dados em
  `/opt/omniroute/data` (sobrevive a recriar o contentor). Segredos em `/opt/omniroute/.env` (0600).
- Porta 20128: **só** `127.0.0.1` do host e a rede docker `hermes-agent-fvnc_default`
  (o Hermes chama `http://omniroute:20128/v1`). Nunca `0.0.0.0`.
- Do PC chega-se pelo Tailscale: `http://100.120.181.115:20128/v1`. O Tailscale vive **dentro**
  do contentor do Hermes; o reencaminhamento é `tailscale serve --tcp 20128 tcp://omniroute:20128`
  (só tailnet; fica gravado no estado do Tailscale, em `/opt/data/tailscale`).
- Palavra-passe do painel: `OMNIROUTE_PASSWORD` em `/opt/data/.env`. Chave dos agentes:
  `OMNIROUTE_API_KEY` no mesmo ficheiro e no `.env` de cada perfil ligado.

## Regras que ficaram no desenho

- Só fornecedores por **chave de API**. Nada de contas Claude/ChatGPT/Gemini web, nada de
  revendedores (Kiro, Qoder, g4f), nada de "TLS stealth" (`ENABLE_TLS_FINGERPRINT=false`).
- O OpenCode Go é chamado com identidade **própria e honesta** (`bora-agentes/1.0`, sessão por
  conversa), como a documentação do Go pede a clientes que não são o OpenCode.
- O OpenCode Zen grátis **não entra**: a OpenCode só o permite dentro do próprio OpenCode, e usá-lo
  aqui obrigava a fingir ser o cliente deles.
- Compressão (Caveman/RTK) desligada; cache de respostas desligada nas chaves (a cache, tal como o
  recuo, esconde um nível morto numa prova).
- As chaves das máquinas (`agentes-bora`, `conselho-juiz`, `pc-opencode-danilo`) só podem pedir os
  modelos e combos daqui — os fornecedores "sem chave" que o OmniRoute traz de fábrica dão 403.

## Combos (estratégia `priority`: desce só quando o nível falha)

Ver `or_combos.py`. `agentes` (Emerson e 5 bots, PC), `privado` (torre: só OpenCode Go, Cloudflare
Workers AI e Groq, que não treinam com os dados), `rapido`, `volume`, `visao`, e as três vozes do
Conselho (`voz-glm`, `voz-qwen`, `voz-minimax`). Os nomes antigos (`perfil:raciocinio`, `glm-5.2`, …)
estão mapeados para os combos, por isso quem os pede continua a funcionar.

## Quando a chave do OpenCode Go for renovada

A 23/10 a chave estava **expirada** (o próprio OpenCode do PC diz "This API key has expired").
Com chave nova: actualizar a ligação `opencode-go-1` (`PUT /api/providers/<id>` com `apiKey`) e
correr `or_prova.py opencode-go/glm-5.2 opencode-go/qwen3.8-max` — o Go volta ao topo sozinho.

## Provas e manutenção

- `or_prova.py modelo…` chama cada nível **sozinho** (sem combo, sem cache). `--ferramentas`
  e `--grande` simulam um pedido real do Hermes (~11 mil tokens).
- `or_descida.py` estraga de propósito as chaves do Gemini, mostra quem responde, e repõe-nas.
- `or_estado.py` (cron `*/10`) escreve `public.omniroute_estado`, que o ecrã `/admin/motores` lê.
- Desfazer o Hermes: `or_ligar_hermes.py --desfazer`; o Emerson: `or_patch_emerson.py --desfazer`.
