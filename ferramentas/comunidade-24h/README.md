# Gestor de comunidade 24h (Hermes, VPS)

Missão `comunidade-24h-montagem` (17/11/2026). O Hermes lê os comentários novos das contas, responde
na voz de cada uma (com um Juiz antes de publicar), mede os números todos os dias e manda um resumo
às 21:00 pelo porteiro. A alma (regras completas) vive na VPS em `/opt/data/missoes/comunidade-24h.md`.
Este repositório é público: aqui só há código genérico. A lista real das contas e os textos fixados
estão na `caixa_guardados` (privada) e vão para `/opt/data/missoes/comunidade-contas.json`.

## Peças

| Ficheiro | Onde corre | O que faz |
|---|---|---|
| `comum.py` | VPS | cofre, Supabase (chave de serviço), motor de texto (OmniRoute), e2e_log |
| `yt_oauth.py` | VPS | autoriza cada canal do YouTube (PKCE, retorno para o PC) e renova tokens |
| `pc_apanha_codigo.ps1` | PC | escuta `127.0.0.1:8765` e guarda o código de retorno para a VPS ir buscar |
| `ronda.py` | VPS | YouTube + Facebook + Instagram: ler, responder, ler de volta, registar; fila `pc-lote` |
| `metricas.py` | VPS | números do dia em `redes_metricas` (só leitura nas plataformas) |
| `resumo.py` | VPS | resumo das 21:00 pelo porteiro |
| `crontab.txt` | VPS (host) | horários |

Só biblioteca padrão do Python (corre no Python do contentor).

## Cofre (`/opt/data/cofre`, pasta 700, ficheiros 600, dono hermes)

- `supabase.json` `{url, service_key}` — o `/opt/data/.env` NÃO tem chave de serviço (medido 17/11).
- `llm.json` `{key}` — chave do OmniRoute (o OmniRoute respondeu 401 sem chave a 17/11 = vivo).
- `youtube-cliente.json` `{client_id, client_secret}` — cliente OAuth "Aplicação de computador".
- `youtube/<conta>.json` — escrito pelo `yt_oauth.py`.
- `meta/<conta>.json` `{page_id, page_token, ig_user_id?, ig_username?}` — token de Página (não expira).
- `meta-ads.json` `{ad_account_id, token}` — só `ads_read`, para LER o gasto do anúncio.

## Porque não o fluxo de dispositivo do Google

`comments.insert` exige o âmbito `youtube.force-ssl`, e o fluxo "TV e dispositivos" só aceita
`youtube` e `youtube.readonly` (documentação do YouTube Data API, consultada 17/11). Por isso o
fluxo é o de aplicação de computador: a VPS gera o endereço (`yt_oauth.py iniciar <conta>`), o
Danilo abre-o no Chrome pessoal, escolhe o canal e carrega em Permitir; o browser volta para
`127.0.0.1:8765` no PC, o `pc_apanha_codigo.ps1` guarda o código, e a VPS vai buscá-lo pela ligação
`ssh bora-pc` que já tem (`yt_oauth.py apanhar`). O código sozinho não abre nada: falta-lhe o
segredo do cliente e o verificador PKCE, que só existem no cofre da VPS.

Cuidado: o ecrã de consentimento do projeto Google tem de estar **em produção** (em "Testing" os
tokens morrem ao fim de 7 dias). Sem verificação da Google aparece "app não verificada" →
"Avançadas" → "Continuar" (até 100 utilizadores; é só o Danilo).

## Ordem para ligar (quem tem acesso à VPS)

1. Aplicar a migração `supabase/migrations/20261117193000_redes_comunidade_24h.sql`.
2. Copiar esta pasta para `/opt/data/ferramentas/comunidade-24h/` e a lista de contas para
   `/opt/data/missoes/comunidade-contas.json`; preencher o cofre.
3. `python3 ronda.py --ensaio` — tem de listar todas as contas sem ERRO (as sem token dizem "sem token").
4. Autorizar os canais do YouTube (passo do Danilo, um clique por canal) e pôr os tokens de Página.
5. Uma ronda a sério numa conta (`--conta X`), ler de volta na plataforma, e só depois o `crontab.txt`.
6. Ligar o estudo das 10:00 e as experiências de domingo pelo relógio do Hermes (agente `redes`).

## O que fica para o PC (`pc-lote`)

Sem API: fixar comentário e dar coração no YouTube; tudo no TikTok; Instagram que não seja
profissional. A ronda deixa essas linhas em `redes_interacoes` com `canal='pc-lote'` e
`estado='pc-lote'`. A 17/11 o classificador do Claude Code recusou publicar, responder, fixar e
editar comentários no navegador (docs/TRANCAS.md, e2e 10557/10565/10583): enquanto isso valer, o
lote não se liga e essas linhas ficam para a Claude.ai ou para o Danilo pela app.

## Limites (alma, ponto 6)

YouTube 20 respostas por hora e por conta, Facebook/Instagram 15, TikTok 10; pausa aleatória de
25 a 110 s entre respostas; nunca links nas respostas; insultos e spam ignorados; nada de seguir,
comentar em vídeos alheios, mensagens não pedidas, mexer em preços, anúncios ou publicações.
