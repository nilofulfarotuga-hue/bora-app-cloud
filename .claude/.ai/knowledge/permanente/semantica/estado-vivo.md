---
tema: estado-vivo · escopo: projeto · estado: atual · atualizado: 2026-09-05
id: estado-vivo
tipo: foto
origem: [reescrito pela Claude.ai 2026-09-05 a pedido do Danilo — foto geral + cascata de ferramentas]
ultima_confirmacao: 2026-09-05
zona: verde
confianca: alta
---

# 📸 Estado Vivo do Bora (gémeo digital lite)

> **ÚNICA página do Cérebro que se REESCREVE.** Quem precisa da "foto da empresa" lê ESTA página.
> Foto operacional ao minuto: o daily-pulse escreve `/opt/data/estado-vivo.md` na VPS.

## ⚙️ CASCATA DE FERRAMENTAS — qual usar e por que ordem (2026-09-05)

Vale para TUDO o que gera imagem ou vídeo: filme das filhas (Bora Studio), artes das
redes, cartazes, mini-sites de clientes, propaganda.

**VÍDEO**
1. **Veo, dentro do Gemini web** (gemini.google.com, sessão iniciada no Chrome do PC, pelo
   agente de clique). Disponível desde 05/09 — o Danilo passou a ter o plano Google AI Plus.
   É a via principal.
2. **Bora Studio na GPU do Kaggle** (Wan I2V) quando o Veo estiver sem limite ou o plano
   for cancelado. A quota semanal do Kaggle renova ao sábado.
3. Nunca: Sora (descontinuado), Higgsfield (sem créditos), nem serviço novo de fora.

**IMAGEM**
1. **API do Gemini** enquanto houver quota (o tecto do projecto não se mexe).
2. **Gemini web / Nano Banana Pro pelo clique** quando a API der 429 ou cap. Com o plano
   novo os limites subiram muito.
3. **ChatGPT web pelo clique** (sessão iniciada no Chrome) como terceira via — gerar nos
   dois e ficar com o melhor.
4. Regra provada em 4 reprovações: **a IA desenha a peça INTEIRA** (composição, molduras,
   atmosfera); o script só cola por cima logos reais, ecrãs reais da app e QR reais.
   Nunca o contrário.

**MOTORES DE TEXTO/CÓDIGO** — o mais barato que dê conta com segurança:
FREE/rascunho → OpenCode · volume (telas, bugs simples, refactors leves) → plano Go dentro
do Claude Code · zonas protegidas e raciocínio pesado multi-ficheiro → OPUS · o mais
crítico → FABLE. O loop automático corre SEMPRE no Claude Code.

## 🔒 PORTÕES DE QUALIDADE (não publicar nada sem passar)

- `fiscal_arte.py` — peça vs referência, nota separada em FEITURA (60) e MARCA (40).
  **Abaixo de 80 não publica.** Provado nos dois sentidos: peça fraca 46, peça boa 86.
- `fiscal_video.py` — metade máquina (movimento, cortes, formato, som), metade olho.
  Régua medida em 6 reels reais do Glovo: movimento ≥12, máx. 4s por plano, 9:16, 7–20s,
  com som. Filme antigo do Bora: 13/45. Glovo: 40/45.
- Referências reais em `/opt/data/social/referencias/` (50 peças) e `referencias-video/`
  (6 reels), colhidas da **Biblioteca de Anúncios da Meta** — melhor que o feed, porque só
  lá está o que as marcas escolheram mesmo pôr a correr.
- `juiz_visao.py` estava partido (chamava modelos do Gemini já desligados) e passava tudo
  em silêncio. Corrigido 05/09. Lição: script que falha para o lado seguro parece funcionar.

## Snapshot 2026-09-05

**Redes sociais** — Facebook e Instagram do Bora no ar (`@boraappbora`), 8 publicações,
3 seguidores. Publicador automático na VPS com a cadência nova: 5 reels/semana (seg–sex
18h), 4 de feed, stories quase diários. A ligação à Meta está viva e provada com
publicação real hoje às 10:49. A app "Bora Social" está em **modo de desenvolvimento** —
enquanto assim for, o robô de atendimento a clientes é impossível (exige app publicada e
revisão da Meta). Travão instalado: ao 3.º erro seguido de autenticação pára e recua para
de hora a hora, em vez de bater de 10 em 10 minutos.

**Cadência e alcance** — falta pôr a **etiqueta de local "Guarda"** a sério (o `location_id`
da API); hoje só há hashtags, e sem ela o Instagram não sabe a que mercado a conta
pertence. O `rotacao.md` continua com uma linha por dia enquanto a cadência publica a loja
do dia 2x por semana — a fila atrasa-se e hoje um parceiro ficou para trás.

**Loop/orquestração** — tecto por tentativa baixado para 1h (era 4h05 e entupia a fila).
Armadilha aberta: cancelar ordem em execução NÃO liberta o `flock` — é preciso matar o
processo também. `.vps-exec.rc=97` não é avaria, foi desligado de propósito em Julho.
O juiz recebia o prompt truncado a 27% pelo tecto de 8191 caracteres do `cmd`; corrigido,
agora chega byte a byte.

**TVDE** — o travão de reserva passou de 20 minutos fixos a cálculo por rota. Corrigidos
três defeitos em cadeia do caso do Valdemir (o ecrã trocava de corrida sozinho com
passageiro a bordo). O mapa do motorista a travar e a não recalcular continua em aberto.

**Empresa** — a câmara respondeu: não divulga iniciativas de fora; os incentivos municipais
exigem criar 3 postos de trabalho; o aviso SICE fecha a 30/09 mas exige empresa já
constituída. O que desbloqueia tudo continua a ser a contabilista.

## Campos fixos (o daily-pulse preenche todos, por esta ordem)
build atual e track · testadores ativos (12×14d) · pedidos/receita da semana · tickets
abertos · erros/cron failures 24h · custo estimado de IA do dia · ordens ativas/travadas ·
último deploy.
