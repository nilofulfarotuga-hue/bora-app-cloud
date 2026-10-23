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
- **OpenCode Go: retirado a 23/10** (o Danilo decidiu não renovar; a chave tinha expirado). Se um dia
  voltar, entra com identidade **própria e honesta** (`OPENCODE_GO_USER_AGENT=bora-agentes/1.0` no
  `docker-compose.yml`, sessão por conversa), como a documentação do Go pede.
- O OpenCode Zen grátis **não entra aqui**: a OpenCode só o permite dentro do próprio OpenCode, e
  usá-lo atrás do OmniRoute obrigava a fingir ser o cliente deles. Usa-se **no OpenCode do PC**
  (`opencode models opencode`; defeito `opencode/glm-5.3-flash-free`, que não treina com os dados).
- **Nunca 3 níveis seguidos do mesmo fornecedor** num combo: com uma chave Gemini inválida o Google
  responde 400 e o OmniRoute, ao ver 3 erros 400 iguais seguidos, desiste do combo em vez de descer
  (provado 23/10 06:59).
- Compressão (Caveman/RTK) desligada; cache de respostas desligada nas chaves (a cache, tal como o
  recuo, esconde um nível morto numa prova).
- As chaves das máquinas (`agentes-bora`, `conselho-juiz`, `pc-opencode-danilo`) só podem pedir os
  modelos e combos daqui — os fornecedores "sem chave" que o OmniRoute traz de fábrica dão 403.

## Combos (estratégia `priority`: desce só quando o nível falha)

Ver `or_combos.py`. `agentes` (Emerson e 5 bots, PC: Gemini, NVIDIA, OpenRouter, Groq, Cloudflare,
Motor Bora), `privado` (torre: só Cloudflare Workers AI e Groq, que por escrito não treinam com os
dados), `rapido`, `volume`, `visao`, e as três vozes do Conselho (`voz-glm`, `voz-qwen`,
`voz-minimax`). Os nomes antigos (`perfil:raciocinio`, `glm-5.2`, …) estão mapeados para os combos,
por isso quem os pede continua a funcionar. Depois de mudar combos: `or_chaves.py` (fecha as três
chaves aos modelos que existem).

## Recurso do carteiro (quando o plano Claude esgota)

`GO_CADEIA="omniroute zen-glm"` no `carteiro.sh` (o nome "GO_" ficou por história). Cada degrau corre
o `pc-loop-go` no contentor do Hermes → ssh `bora-pc` (PC actual, utilizador `danil`) →
`run-opencode-recurso.ps1` (caminho **real** `C:\BoraLocal\Desktop-PC-antigo\...`: o
`Desktop\produtividade-ia` é uma junção que o ssh do Windows recusa) → OpenCode com
`omniroute/agentes` ou `opencode/glm-5.3-flash-free`. Nunca se redirecciona o Claude Code.
Prova: `carteiro.sh --prova-cadeia "<tarefa>"`. Cópias em `.claude/.ai/hermes/orquestrador-carteiro/deploy/`.

## Provas e manutenção

- `or_prova.py modelo…` chama cada nível **sozinho** (sem combo, sem cache). `--ferramentas`
  e `--grande` simulam um pedido real do Hermes (~11 mil tokens).
- `or_descida.py` estraga de propósito as chaves do Gemini, mostra quem responde, e repõe-nas.
- `or_estado.py` (cron `*/10`) escreve `public.omniroute_estado`, que o ecrã `/admin/motores` lê.
- Desfazer o Hermes: `or_ligar_hermes.py --desfazer`; o Emerson: `or_patch_emerson.py --desfazer`.
- **Cicatriz 23/10:** o gateway do Telegram (`hermes gateway run`) carrega o `.env` só ao arrancar; com uma
  chave nova no `.env` dava `401` no OmniRoute e respondia pelo recuo antigo. Depois de mudar a chave,
  reinicia-se com `relancar_gateway.sh` (espera que a conversa em curso acabe — matar a meio deixa a
  mensagem do Danilo sem resposta, foi o que aconteceu às 06h22).
