---
tema: estado-vivo · escopo: projeto · estado: atual · atualizado: 2026-09-08
id: estado-vivo
tipo: foto
origem: [reescrito pela Claude.ai 2026-09-05 a pedido do Danilo — foto geral + cascata de ferramentas; cascata de IMAGEM corrigida por medição no BoraStudio 2026-09-05; cadência das redes e executor-com-navegador actualizados 2026-09-07 pela sessão redes-hoje-07-09; cascata de VÍDEO medida e passada a config na noite de 07→08/09 pela missão cascata-video-tres-motores]
ultima_confirmacao: 2026-09-08
zona: verde
confianca: alta
---

# 📸 Estado Vivo do Bora (gémeo digital lite)

> **ÚNICA página do Cérebro que se REESCREVE.** Quem precisa da "foto da empresa" lê ESTA página.
> Foto operacional ao minuto: o daily-pulse escreve `/opt/data/estado-vivo.md` na VPS.

## ⚙️ CASCATA DE FERRAMENTAS — qual usar e por que ordem

Vale para TUDO o que gera imagem ou vídeo: filme das filhas (Bora Studio), artes das
redes, cartazes, mini-sites de clientes, propaganda.

**VÍDEO — deixou de viver nesta página (2026-09-08)**

A ordem dos motores é agora **config que o sistema lê e por onde cai sozinho**:
`canon/cascata_video.yaml`, conduzida por `agentes/cascata_video.py`. Esta secção é só o
resumo; **a fonte é o ficheiro**. Prosa não cai sozinha — quando o degrau de cima falhava,
quem descia ao seguinte era uma pessoa a ler esta página.

1. **Veo, dentro do Gemini web** (`veo_gemini_web`) — sessão Google AI Plus, pelo clique.
   **Medido a 07/09, a primeira vez que alguém o mediu:** 1280×720, 10,01 s por clipe,
   **com som** (aac 2ch 48 kHz), enquadramento travado (deslocamento 0,0–0,1%), e segurou o
   sinal das irmãs 2/2. Tempo até ao ficheiro: 546 s e 183 s. Faz também **9:16 vertical**.
2. **Bora Studio na GPU do Kaggle** (`kaggle_wan_i2v`, Wan I2V) — grátis, quota semanal, renova
   ao sábado. Medido: 768×432 em 158 dos 190 clipes do disco, 5,04 s, **sem som nenhum**
   (0/190), deslocamento até 4,5%, e perdeu o sinal das irmãs 1 vez em 2 — no `b2_s04` o rosa
   da Tabita caiu de 2,485% para 0,148%. ⚠️ **Sem quota desde 07/09**: corridas 356 a 360
   recusadas pela própria plataforma.
3. **Vibes (Meta / Movie Gen)** (`vibes_meta`) — acrescentado, **nunca chegou a gerar**.
   `estado: bloqueado_porta_legal`: o login exige *criar uma conta da Meta e aceitar os Termos*,
   que é acto legal e só o Danilo o faz, num clique, uma vez. Fica **vivo na config, não
   apagado**. Ver `prova-motores-video-2026-09`.
4. Nunca: Sora (descontinuado), Higgsfield (pago, R-E), nem serviço novo de fora.

**A ordem confirmou-se pela medição — não mudou.** A diferença é que antes era prosa e agora
tem números por baixo. E há duas leis no ficheiro: **nunca se remove um degrau** (morre com
data e causa, há um `mortos:`), e **a ordem só muda com medição** (`reordenar()` levanta erro
sem números). Prova de que cai sozinha: `agentes/prova_cascata_video.py`, 4/4.

**IMAGEM**
1. **API do Gemini** enquanto houver quota (o tecto do projecto não se mexe).
   ⚠️ **Medido a 05/09, no BoraStudio:** com a chave do projecto **sem faturação**, a geração
   de imagem dá **429 nos três modelos** (`gemini-3.1-flash-image`, `gemini-3-pro-image`,
   `gemini-2.5-flash-image`). Não é quota gasta — é `limit: 0`, quota que nunca existiu.
   O TEXTO e a VISÃO dessa chave funcionam (148 chamadas boas nesse dia).
2. ⚠️ **O Google AI Plus NÃO dá quota de API.** É subscrição do *app* Gemini
   (gemini.google.com). O botão "Atualizar" ter desaparecido e o Veo aparecer na barra
   lateral são reais e **não mudam uma linha** do `generativelanguage.googleapis.com`.
   Não voltar a contar com ele para desbloquear a API — está medido.
   **Gemini web / Nano Banana Pro pelo clique** continua a ser via válida, mas os seus
   limites **não estão medidos**; quem a usar mede e escreve aqui.
3. **ChatGPT web pelo clique** (sessão iniciada no Chrome) como terceira via — gerar nos
   dois e ficar com o melhor.
4. **No Bora Studio a imagem NÃO passa por nenhuma destas vias:** os fotogramas geram-se na
   GPU do Kaggle com **Qwen-Image-Edit-2509** (Apache-2.0), e isso funciona sozinho — a
   corrida 319 de 05/09 entregou 12 fotogramas das 07:37 às 11:52. Um caminho por clique
   seria mais frágil e menos automático do que o que já lá está.
5. Regra provada em 4 reprovações: **a IA desenha a peça INTEIRA** (composição, molduras,
   atmosfera); o script só cola por cima logos reais, ecrãs reais da app e QR reais.
   Nunca o contrário.

**MOTORES DE TEXTO/CÓDIGO** — o mais barato que dê conta com segurança:
FREE/rascunho → OpenCode · volume (telas, bugs simples, refactors leves) → plano Go dentro
do Claude Code · zonas protegidas e raciocínio pesado multi-ficheiro → OPUS · o mais
crítico → FABLE. O loop automático corre SEMPRE no Claude Code.

## 🔒 PORTÕES DE QUALIDADE (não publicar nada sem passar)

- `fiscal_arte.py` — peça vs referência, nota separada em FEITURA (60) e MARCA (40).
  **Abaixo de 80 não publica.** Provado nos dois sentidos: peça fraca 46, peça boa 86.
- `fiscal_video.py` — metade máquina, metade olho. Régua medida em 6 reels reais do Glovo:
  movimento ≥12, máx. 4s por plano, 9:16, 7–20s, com som. Filme antigo do Bora: 13/45.
  Glovo: 40/45. **Vive na VPS e só ele dá o veredicto.** No PC mede-se só as ENTRADAS
  (`comparar_motores.entradas_da_regua_reels`) — escrever cá uma segunda régua era criar a
  segunda conta que discorda em silêncio.
- Referências reais em `/opt/data/social/referencias/` (50 peças) e `referencias-video/`
  (6 reels), colhidas da **Biblioteca de Anúncios da Meta** — melhor que o feed, porque só
  lá está o que as marcas escolheram mesmo pôr a correr.
- `juiz_visao.py` estava partido (chamava modelos do Gemini já desligados) e passava tudo
  em silêncio. Corrigido 05/09. Lição: script que falha para o lado seguro parece funcionar.
- **Uma regra só julga o artefacto de que fala (R62).** Medido outra vez a 08/09: o clipe de
  cinema do Veo, passado pela régua dos reels, dá movimento 6,78 (<12) e plano mais longo de
  9 s (>4) — **reprovaria**, e reprovaria bem, porque essa régua não é para ele.
- **Um controlo que não falha é uma prova que não prova (R63).** Se o cenário de controlo passa
  quando devia rebentar, a prova está a medir a ausência do problema, não a presença da cura.

## Snapshot 2026-09-08

**Redes sociais** — Facebook e Instagram do Bora no ar (`@boraappbora`). A ligação à Meta
está viva e provada com publicações reais a 07/09: loja do dia às 12h, story às 13h,
carrossel a seguir e o reel de categorias às 15h06, todos por relógio ou por clique.
A app "Bora Social" continua em **modo de desenvolvimento** — enquanto assim for, o robô de
atendimento a clientes é impossível (exige app publicada e revisão da Meta). Travão
instalado: ao 3.º erro seguido de autenticação pára e recua para de hora a hora.

**Cadência das redes (revista 2026-09-07, ordem do Danilo)** — toda por cron na VPS, cada
slot com a sua guarda `.<slot>-feito-<data>`: 09h10 plano dos grupos · 10h00 story da manhã
(NOVO; o `social-story.sh` aceita `SOCIAL_SLOT=manha` com guarda separada — se partilhassem
guarda, o da manhã marcava o dia como feito e o da noite saltava-se a si próprio) · 12h00
loja do dia · 15h00 formato extra (era 16h00, e passou a diário) · 18h00 reel à segunda,
quarta e sexta · 18h00 carrossel à terça, quinta e sábado (era 13h00 de segunda e quinta) ·
18h30 resumo dos grupos · 19h30 story com pergunta · 21h30 os três números · domingo 11h00
grelha da semana. O verificador das 21h30 passou a contar **cada slot** pelas guardas reais
e a dizer o que faltou, em vez de só listar o que saiu.
Backups: `/root/orquestracao/crontab.bak-cadencia-2026-09-07`,
`social-story.sh.bak-slot-2026-09-07`, `resumo_do_dia.py.bak-slots-2026-09-07`.
Continua por fazer a **etiqueta de local "Guarda"** a sério (o `location_id` da API); hoje só
há hashtags. E há gémeos a divergir: o `rotacao.md` diz que a loja do dia é 2x por semana e a
crontab diz diária — mandou a crontab, porque é o que o Danilo pediu.

**Grupos do Facebook** — 25 grupos no ficheiro de estado, 19 com escrita permitida. Publicar
num grupo **exige sempre um navegador a clicar** (a via automática morreu em 2024) e por isso
só sai com o PC do Danilo ligado, na sessão dele, com o Chrome aberto. Cuidado com o ficheiro
de estado: diz `joined: true` para grupos onde o botão "Aderir ao grupo" ainda aparece — a 07/09
uma publicação falhou por isso. Regras: máx. 5 por dia, ≥20 min entre elas, texto diferente,
uma por grupo por semana, parar tudo ao primeiro aviso da Meta.

**Loop/orquestração — o executor passou a ter navegador (2026-09-07)** — causa medida, não
suposta: o lançador vivo `run-claude-loop-pcnovo-limpo.cmd` (em
`C:\BoraLocal\Desktop-PC-antigo\produtividade-ia\hermes-bridge`) corria `claude -p` **sem a
bandeira `--chrome`**. Sem ela o executor responde literalmente `SEM-NAVEGADOR`; com ela ganha
as 20 ferramentas `mcp__claude-in-chrome__*`. Não era MCP em falta, nem Chrome fechado, nem
perfil errado. De caminho repôs-se a detecção de `[MODELO: OPUS]`, que esse lançador tinha
perdido (tinha sonnet cravado).
**Relógio do dia no PC:** 5 tarefas no Agendador do Windows, sessão `danil`, sem elevação —
`BoraBancoPecas` 08h00, `BoraGruposManha` 09h30, `BoraGruposTarde` 14h30, `BoraGruposNoite`
18h30, e `BoraGuardaChrome` ao logon e de 15 em 15 min (mantém o Chrome vivo, senão a ordem
corre e não faz nada). Gatilho: `orquestracao/disparar-ordem-fixa.cmd <nome>`, que escreve a
ordem fixa de `orquestracao/ordens-fixas/` no ficheiro de tarefa e chama o executor. Não passa
pelo carteiro da VPS de propósito: o carteiro só corre à hora certa (`:17`) e atrasaria cada
ordem até 60 minutos, estragando a regra dos 20 minutos entre publicações.
Provado a 07/09: às 15h37 uma ordem disparada por esse gatilho abriu o Facebook no Chrome
real, gravou uma captura de 606 KB no disco e escreveu a linha 1342 no `e2e_log`. Às 16h02
uma segunda ordem, a sério, disparou sozinha; o PC entrou em suspensão a meio e a ordem
**retomou quando o PC acordou**.
Armadilhas antigas que se mantêm: cancelar ordem em execução NÃO liberta o `flock` — é preciso
matar o processo também; `.vps-exec.rc=97` não é avaria, foi desligado de propósito em Julho.
⚠️ **A VPS esteve inalcançável na noite de 07→08/09**: `100.71.105.7` (Tailscale) deu timeout
com as três chaves. Quem depender dela conte com isso e verifique antes.

**Campanha paga (07/09)** — "Bora Guarda - trafego - 5 EUR dia - 2 dias", conta
`act_1105400138585537`. Com o intervalo em **Máximo**: os três níveis Activos, resultados
traço, **gasto 0,00 €** desde sempre. O dinheiro não é o travão — 10 € de fundos disponíveis,
modo "Fundos disponíveis", limite diário da Meta 17,28 €, pagamento manual de 10 € do dia 5
marcado Pago. A explicação está num email da Meta de 07/09 às 8h15: **o anúncio só foi
aprovado hoje de manhã**; esteve em revisão desde o dia 5. Objectivo fica em TRÁFEGO porque
"instalações" exigiria o SDK da Meta dentro da app Flutter. Criativo de vídeo pronto e à
espera: versão paga do reel carregada na Página como publicação **não publicada**, id
`1034605486304474`. Regras estudadas em `docs/redes/META-REGRAS-2026-09-07.md`.
⚠️ O Gestor de Anúncios **não estabiliza no PC do Danilo** — abre ao fim de ~1 min na vista de
campanhas e nunca assenta na de conjuntos. Quem lá for, conte com isso.

**Bora Studio (filme)** — a fábrica não está parada: corre sozinha de 15 em 15 min. A 05/09
corrigiu-se o portão de fotogramas (ver R62 acima) e mediu-se o verdadeiro estrangulamento:
39 dos 128 planos param no penteado das duas irmãs. A roupa identifica-as sempre certo
(verde = Tailine, rosa = Tabita, medido 20/20, e aguenta-se até nos planos onde o cabelo
falha); o penteado é que anda atribuído à irmã errada. A cor subiu à `assinatura_inegociavel`
e cada irmã ganhou âncora de imagem recortada de um plano aprovado.
**08/09:** a cascata de vídeo passou a config (acima) e mediu-se pela primeira vez o Veo
contra o Kaggle nos mesmos planos. Um achado que toca directamente no problema das irmãs: o
Wan perdeu o sinal de cor de uma delas num dos dois planos; o Veo não. Ver
`prova-motores-video-2026-09`.

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
