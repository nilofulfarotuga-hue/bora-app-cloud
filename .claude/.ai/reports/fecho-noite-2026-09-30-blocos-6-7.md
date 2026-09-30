# Relatório — fecho-noite-2026-09-30 · Blocos 6 e 7 (grupos do Facebook + Google Ads)

Sessão: Claude Code (Fable), PC do Danilo, 30/09/2026 22:16–22:35 Lisboa.
RAM ao arrancar: **531 MB disponíveis** (portão leve 400 MB: passa; o PC tem 14 GB).
Marcos no `e2e_log` (`fluxo='fecho-noite-2026-09-30'`): ids 2637, 2640, 2641, 2642, 2644 + fim.

## Uma linha por bloco

- **Bloco 6 — grupos do Facebook (Bora): NÃO publicado.** A publicação 1 foi composta de ponta a ponta
  na conta pessoal *Danilo Silva* (Chrome pessoal): grupo *-Guarda e Arredores-* aberto, autor confirmado
  na caixa "Criar publicação", foto carregada, texto e link escritos. O clique em **Publicar** foi negado
  pelo classificador do modo automático (*External System Writes*), a mesma barreira que trava os grupos
  desde 24/09 — desta vez **mesmo com a ordem escrita do Danilo e com a conta pessoal**. Não repeti nem
  contornei (regra da skill `bloqueio-classificador-auto-mode`). A publicação ficou **composta na janela,
  à espera só do clique**. Prova: captura `ss_42633ry3m` (janela com texto + foto + botão Publicar) e
  e2e_log 2640. Telegram 22:26 (lido de volta no `log.md` da VPS).
- **Bloco 6 — as 5 prontas (caminho de reserva da ordem):** `docs/marketing/grupos-prontos/2026-09-30/`,
  cada uma com texto, imagem e link do grupo (ver tabela). Todas com imagens e textos diferentes, 1 por
  grupo, todos os grupos sem publicação há mais de 7 dias, um de negócio (Emprego Guarda).
- **Bloco 6 — Em Dia: NÃO feito.** O mapa (`grupos.csv`) tem **0 de 454 grupos pedidos**; as regras do
  `_COMUM-EMDIA.md` (72 h depois de aceite; nunca depois das 22:00) impedem publicar hoje. Preparei os
  **5 pedidos de adesão** com resposta de entrada em `EM-DIA-adesoes-2026-09-30.md` (mesma pasta). Não os
  pedi por automação: é a mesma escrita no Facebook que o classificador acabou de negar.
- **Bloco 7 — Google Ads: TRAVADO na conta.** `boraappbora@gmail.com` (perfil Bora) **não tem conta Google
  Ads** ("Não tem contas do Google Ads. Quer criar uma?"). Criar conta e pôr cartão é acto do Danilo. Fiz o
  que a ordem manda: página **aberta à frente** no PC (janela "Google Ads - Google Chrome" confirmada por
  `GetForegroundWindow`) e Telegram 22:30 com a linha exacta. A campanha completa ficou escrita em
  `docs/marketing/google-ads/campanha-guarda-3km-2026-09-30.md` (pesquisa, raio 3 km, presença, PT,
  10 €/dia, 3 grupos de anúncios, palavras, negativas, títulos, descrições, recursos sem marcas de terceiros,
  relatório diário) — quando houver conta com cartão, monta-se em ~15 min.
- **Relatório diário do Google Ads (3 números):** não arranca sem campanha. E o 3.º número (visitas a
  `/baixar` vindas do Google) está **a zero por defeito**: `/baixar` dá 302 para o store e não regista
  visitas desde 23/09 (medido hoje de novo: `?de=google` → 302 play.google.com).

## As 5 publicações prontas (Bora)

| # | Grupo | Membros | Texto | Imagem | Link |
|---|---|---|---|---|---|
| 1 | -Guarda e Arredores- | 773 | lavagem T2 | carrossel organica-07-lavagem | ?de=qr-grupo-guarda-e-arredores |
| 2 | Jornal do distrito da Guarda | 4 mil | comida T2 | carrossel organica-02-comida | ?de=qr-grupo-jornal-distrito-guarda |
| 3 | Guarda para sempre | 4,5 mil | mercado T1 | carrossel paga-01-mercado | ?de=qr-grupo-guarda-para-sempre |
| 4 | Emprego Guarda | 20,3 mil | negócio N1 | negocio-1 | (sem link: mensagem à página) |
| 5 | Cidade.da.Guarda | 2,9 mil | açaí T3 | carrossel organica-04-acai | ?de=qr-grupo-cidade-da-guarda |

Vídeos IPG: **não vão a grupos** (lição de 07–09/09: o mp4 trava a caixa, a foto sobe em segundos).
Extraí fotogramas dos IPG aprovados (`_candidatas/ipg/frames/`); o cartão final do vídeo 5 (QR + BEMVINDO)
ficou como `extra-cartao-final-ipg-lavagem.jpg`. Os fotogramas do vídeo 2 têm Continente/Pingo Doce no
visual e não servem para anúncios nem grupos.

## Encontrado pelo caminho (só reporto)

1. O perfil pessoal do Chrome tem a conta Google Ads **Jai Agarwal** (144-763-8091, jaiagarwala.com) com
   **Visa •••• 2670** e uma campanha própria a 0 €. É conta de um cliente: não a usei.
2. O Chrome do perfil Bora navega no Facebook como a página *Bora App Guarda*; a conta pessoal
   *Danilo Silva* vive no Chrome pessoal. Ficam as duas como estavam.
3. O grupo *-Guarda e Arredores-* mostra "Aprovação de administrador pendente · 1 publicação" antes de eu
   publicar — há uma publicação antiga na fila desse grupo.
4. Córtex MCP sem autorização nesta sessão (`cortex_*` indisponível): sem `cortex_memorizar`; as lições
   ficaram na memória local do Claude Code (2 ficheiros) e neste relatório.

## PARA O DANILO

- **Grupos:** o clique em Publicar continua a ser negado pelo classificador, mesmo com a tua ordem. Duas
  saídas: (a) tu clicas — a 1.ª está composta no Chrome pessoal, as outras 4 estão na pasta (abrir grupo,
  colar texto, anexar foto); (b) pôr uma regra de permissão no Claude Code para escrita no Facebook, que
  é decisão tua (é a conta pessoal, com menos de um mês, e sustenta Bora e Em Dia).
- **Google Ads:** criar a conta em boraappbora@gmail.com e pôr o cartão (página aberta à frente), **ou**
  dizer "usa a conta do Jai" (tem cartão). Sem uma das duas não há campanha.
- **Destino da campanha:** `/baixar` redireciona para o store e não mede visitas. Antes de gastar 10 €/dia,
  decidir: URL final `boraguarda.com/?de=google` (mede) ou repor a página intermédia no `/baixar`.
