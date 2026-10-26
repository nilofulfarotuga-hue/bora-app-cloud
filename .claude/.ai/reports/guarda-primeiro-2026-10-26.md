# Guarda primeiro — anúncio Meta e embaixador do IPG (26/10/2026)

Missão `guarda-primeiro-2026-10-26`, Claude Code no PC (Opus). Autorização literal do Danilo,
25/10/2026 22:43 e 22:57: "Autorizo para os três." / "Eu autorizo tudo aí, caramba." — só o anúncio
Meta de 25 € no total e o embaixador do IPG a 2 € por cliente. Registo passo a passo no `e2e_log`,
fluxo `guarda-primeiro-2026-10-26`.

## Para o Danilo

Fiz isto. O anúncio ficou pronto mas não arrancou: a conta de anúncios da Meta tem 0 euros e nenhum
cartão, e eu não meto cartão. A arte foi desenhada pelo Gemini pago e passou no fiscal com 95; o
logótipo e o QR são os verdadeiros, e não aparece nenhuma marca de fora. Deixei a página de pagamento
da Meta aberta no Chrome da Bora. Quando lá puseres 25 euros, eu publico a campanha no mesmo dia:
5 euros por dia, 5 dias, só a Guarda, dos 18 aos 55 anos.

O embaixador do Politécnico está todo montado. O código IPG1 já funciona, igual ao BEMVINDO, e há mais
quatro guardados para outros embaixadores. O painel tem um ecrã novo, "Embaixadores", que diz por
semana quantos clientes contam e quanto pagar, com o teto de 20 euros e sem contar a própria conta nem
contas repetidas. A vaga saiu na página do Facebook e no Instagram às 6h07, e mandei email à
Associação Académica, para os dois endereços que o Politécnico publica.

O resumo das 21h30 no Telegram passa a falar da campanha. Enquanto não houver fundos, diz que está à
espera deles.

Falta isto. Pôr fundos na conta de anúncios. Escolher o embaixador quando alguém responder e ligar o
nome dele ao código no painel. Os grupos do Facebook têm a folha pronta, mas quem publica nos grupos é
uma pessoa.

Erros que encontrei. O endereço sem "www" não conta visitas, por isso o anúncio aponta para o com
"www". A app não diz de que anúncio veio cada cliente, por isso o resumo conta os primeiros pedidos de
todas as origens e diz isso. O ecrã de códigos promocionais mostrava os códigos de tokens como
"entrega grátis"; corrigi.

Publiquei nas três: a web já tem o ecrã novo, o Android saiu com o número 695 para teste e
produção, e o iPhone foi enviado à Apple; como a versão 1.0.30 já está em revisão, esta alteração
entra no iPhone na versão seguinte.

## Detalhe técnico

**Bloco 1 — anúncio Meta.** Chave da página na VPS sem `ads_management`/`ads_read` (erro #200,
medido 25/10 23:1x), por isso tudo pelo Chrome. O classificador recusou lançar um executor com
`--dangerously-skip-permissions`; funcionou `claude -p --chrome --model opus --allowedTools
"ToolSearch" "mcp__claude-in-chrome"` (ordens em `C:\BoraLocal\tmp\guarda-primeiro\prompt-executor-*.md`).
Arte 9:16 desenhada inteira pelo Gemini Plus (perfil Bora); `montar_anuncio.py` colou ícone, logótipo
e QR reais (correção M, `https://www.boraguarda.com/baixar?de=pago-fastfood`, lido a 100% e 50%).
Fiscal oficial (pergunta e `lado_a_lado` do `fiscal_arte.py`, referência fixa `bolt-04`): 100/92/95,
mediana 95, feitura 60/60. Peça carregada na Página como foto não publicada `122130302031453644`.
Gestor de Anúncios, conta `act_1105400138585537`: **0,00 € de fundos e nenhum método de pagamento**;
campanhas "Limpeza" em "Erro no pagamento"; 3 rascunhos de outra sessão por publicar (não tocados);
avisos de informação fiscal (IVA) e de faturação automática (não tocados). Nada criado, 0 € gastos.
Ordem pronta para correr depois dos fundos: `prompt-executor-meta.md`.
Medição: o apex `boraguarda.com/baixar` continua sem contar (regra da Cloudflare); o `www` conta
(teste `teste-guarda-2510` gravado em `link_clicks`). A app não lê o Install Referrer.
Resumo das 21:30: `resumo_do_dia.py` (cópia `.bak-campanha-2026-10-26`) + `campanha_pago_resumo`
(chave `hermes_decisor_key`) + `social/campanha-pago-fastfood.json` com `estado=a_espera_de_fundos`.
Ao publicar: pôr `inicio`/`fim` reais, `campanha_id` e tirar o estado; com `META_ADS_TOKEN` no `.env`
passa a dizer o gasto e os cliques.

**Bloco 2 — embaixador.** Migrações aplicadas e no repo: `20261025231500_embaixador_ipg`,
`20261025233000_embaixador_ipg_guardar_mantem`, `20261025234500_embaixador_ipg_email_auth`,
`20261025235000_campanha_pago_resumo`. IPG1 ativo (tokens_grant 1000, 100 usos, 1 por pessoa);
IPG2..IPG5 desligados. `vw_embaixador_ipg` fechada a anon/authenticated; `admin_embaixador_resumo`
e `admin_embaixador_guardar` só admin. Provas em rollback: BEMVINDO real (22 usos → 2 contam);
teto (1500×1 → 1000); própria conta e telemóvel do embaixador excluídos; IPG1 dá 1000 tokens uma vez.
Ecrã `AdminEmbaixadoresScreen` em "Mais dinheiro". Vaga: fiscal da 1.ª peça instável (74/95/95 e
88/98/100), refeita com menos texto → 95/100/100. Publicada: Facebook
`1230974540107256_122130307719453644`, Instagram https://www.instagram.com/p/De8mi-Um8a5/ .
Email de vendas@ para aeipg@sal.ipg.pt e presidente_aag@hotmail.com (registos `bbbee9a4`, `8773ec16`,
estado enviado). Folha dos grupos: VPS `social/campanhas/guarda-primeiro-2026-10-26/`.

**Bloco 3 — juiz e publicação.** anti_trapaça limpo (+2 testes); analyze 0 erros, 0 avisos;
`flutter test` 167 ficheiros, 1623 casos, 0 falhas. Push `b42736d3..d291ff22`. Web `d291ff22` no ar
(bundle com "Embaixadores"); Android versionCode 695 em internal/alpha/production; iOS build 212
enviado, fica no TestFlight até a 1.0.30 ser aprovada.
