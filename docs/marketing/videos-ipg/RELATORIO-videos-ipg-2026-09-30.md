# Vídeos IPG — relatório (sessão `videos-ipg-30-09`, 30/09/2026)

> Motor: Claude Code no PC do Danilo (Opus). Porta única. Nada publicado, nada pago.
> RAM medida ao arrancar: **462 MB disponíveis** (portão leve 400). Não compilei Flutter;
> o trabalho foi de montagem de vídeo com ffmpeg/PIL. Houve momentos a **290 MB**, e um
> modelo local do Ollama (qwen 7B, 1,5 GB) estava em uso por outra tarefa, por isso não
> lhe mexi. O Chrome pendurou-se várias vezes por isso.

## Resultado numa linha por bloco

| Bloco | Estado | Prova |
|---|---|---|
| 1 · 5 vídeos (7 ficheiros) | **Feito** | 7 mp4 1080×1920, 15,4–18,1 s, com voz e música; fiscal ≥80 em todos (tabela abaixo) |
| 2 · Aprovação | **Parado à espera do Danilo** | Telegram message_id 8811–8817 `ok:true`; pasta aberta no ecrã |
| 3 · Publicação orgânica | **Não começado** (espera aprovação) | Legendas prontas em `LEGENDAS.md` |
| 4 · Campanha paga raio IPG | **Não começado** (espera aprovação) | — |
| 5 · Provas e fecho | Feito em parte | BEMVINDO verificado; relatório; código no repositório; Córtex não, porque o conector não tem sessão |

## Os 7 ficheiros (em `Desktop\Bora\videos-ipg\`)

| Ficheiro | Duração | QR lido | Máquina | Olho (Codex gpt-5.5) | Total |
|---|---|---|---|---|---|
| 1-fast-food-PAGO.mp4 | 16,6 s | `?de=pago-ipg` | 45/45 | 38,1 | **83** |
| 1-fast-food-ORGANICO.mp4 | 18,1 s | `?de=ipg-fastfood` | 45/45 | 40 | **85** |
| 2-supermercado-PAGO.mp4 | 15,6 s | `?de=pago-ipg` | 45/45 | 38 | **83** |
| 2-supermercado-ORGANICO.mp4 | 17,0 s | `?de=ipg-mercado` | 45/45 | 36,8 | **81,8** |
| 3-goola-acai.mp4 | 15,5 s | `?de=ipg-goola` | 45/45 | 36 | **81** |
| 4-sabores-de-casa.mp4 | 17,8 s | `?de=ipg-sabores` | 45/45 | 40,3 | **85,3** |
| 5-lavagem-auto.mp4 | 15,4 s | `?de=ipg-lavagem` | 45/45 | 45,5 | **90,5** |

- **Máquina** = `fiscal_video.py` na VPS (movimento ≥12, ≤4 s por plano, 1080×1920, áudio).
- **Olho**: o juízo de IA do próprio `fiscal_video.py` deu 69/100 ao Goola na 1.ª corrida.
  Depois esgotou a quota grátis do dia (HTTP 429) e os modelos de reserva deram 503, o que
  dá "SEM VEREDITO". O Gemini web pago estava inacessível, porque o Chrome se pendurava.
  **Substituí o olho pelo Codex (ChatGPT Plus, gpt-5.5)**, com a mesma pergunta, a mesma
  grelha de 3 faixas (referência Glovo / filme antigo / peça) e os mesmos pesos. É outro
  motor, que não fez os vídeos: serve de verificador. As respostas estão em
  `provas-fiscal/*.codex.txt`.
- As grelhas de fotogramas de cada vídeo foram vistas por mim (`saidas/*-grelha.jpg`).
- Duas peças (2 orgânico e 4 Sabores) chumbaram primeiro com 78,5 e foram refeitas:
  menos "Bora" nos textos do meio, cartão final de 3 s e Torre de Menagem com 2,2 s.

## Como estão feitos
- Planos Veo: 2 **novos hoje** (estudante com fome na residência; frigorífico vazio) + banco da VPS.
- **Ecrãs reais da app** (pedido do Danilo): capturados do `app.boraguarda.com` num telemóvel
  simulado (Playwright, 1170×2532), sem login e sem dados pessoais. Goola: loja → Goola Bowl →
  3 toppings → "Ver carrinho €9,22". Sabores: loja → Copo Mega → 5 acompanhamentos → €14,00.
  Fast food: ficha "Asas de frango x6". Supermercado: ficha "Maçã Fuji IGP Alcobaça". Lavagem:
  a grelha real de categorias, com o mosaico "Bora Motorista" desfocado (o carro TVDE está
  proibido na publicidade). Tudo dentro de um telemóvel desenhado, com toques animados.
- **Marca na embalagem, colada por script** (`colar_logo_embalagem.py`, nunca pedida à IA):
  sacos e caixas com Bora; na versão ORGÂNICA, como o Danilo pediu por voz, o saco leva o
  nome da loja em letra simples com o Bora por baixo ("Burger King"/"McDonald's"/"Continente"
  + Bora). Nas PAGAS: zero nomes e zero logos de terceiros. Parceiros reais (Goola, Sabores
  de Casa) com o logo real deles + Bora.
- Voz edge-tts (PT-PT Raquel/Duarte; PT-BR Francisca no Sabores de Casa). Música Kevin
  MacLeod (CC BY 4.0), com o crédito nas legendas.

## ⚠️ Riscos para o Danilo decidir
1. **Nomes de marcas em sacos (versões orgânicas 1 e 2).** Foi pedido teu por voz. A ordem
   escrita dizia "sem embalagem deles". Não há logo deles (só o nome em letra simples), mas um
   saco com "McDonald's" pode ler-se como embalagem oficial. As versões PAGAS não têm nada disso.
2. A lavagem (vídeo 5) repete a mesma imagem da espuma. O Veo atingiu o limite diário depois
   de 2 vídeos e o Chrome não deixou descarregar mais imagens. Amanhã, com o Veo livre, dá
   para trocar por planos do carro limpo e da entrega das chaves.
3. O Veo põe uma pequena estrela ✦ do Gemini no canto; não a tirei (é a marca de "feito com IA").

## Erros encontrados pelo caminho (REPORTADOS, não corrigidos)
1. **`boraguarda.com/baixar` deixou de contar visitas desde 23/09.** Hoje é um redirecionamento
   302 no Cloudflare (Android → Play, iPhone → App Store, PC → Play) e **não grava nada**: 3
   visitas de teste deram 0 linhas em `link_clicks`/`site_visits`; a última linha é de
   23/09 17:41. As origens `ipg-*`, `pago-ipg` e `google-ipg` não vão ser medidas até se repor
   o registo. (Avisado no Telegram às 13:47.)
2. **Preço não atualiza com a quantidade na app:** na ficha "Maçã Fuji", com 3 unidades o botão
   continua a mostrar €2,71 (devia dar €8,13). Captura em `_material/app/ct-passo2.png`.
3. **O reel publicado a 08/09 (`2026-09-08-veo-promo-9x16.mp4`) tem uma caixa de estafeta com
   "Guardapio" escrito**, uma marca inventada pela IA, não Bora (≈7 s, mota junto à Torre).
4. **O Codex está configurado com `gpt-6-sol`** (`~/.codex/config.toml`), que a conta ChatGPT
   não aceita. A via "codex" do `delegar.ps1` está partida. Funciona com `-m gpt-5.5`.
5. Dois ficheiros de skills em `~/.agents/skills` com o YAML inválido: `contas-e-navegadores` e
   `distribuir-trabalho` (o Codex recusa carregá-los).
6. O Chrome do perfil Bora tem a aba da automação em segundo plano dentro da janela "Pausa para
   o Lanche"; quando não é a aba ativa, congela (menus não abrem). Ctrl+9 com a janela à frente
   resolve por uns minutos.
7. A 2.ª imagem do Gemini (carro limpo) não descarregou: suspeito do bloqueio de "várias
   transferências" do Chrome. Não pude confirmar sem controlo do ecrã (recusado).

## BEMVINDO (SELECT de 30/09)
`tokens_grant`, 1000 (= €5), máx. 1 por pessoa, sem mínimo. **17 usados de 300 → 283 livres.**
Não foi preciso subir o tecto.

## Painel admin — correspondência
O ecrã de visitas/campanhas **não vai mostrar a origem `ipg`** enquanto a /baixar não voltar a
gravar visitas (erro 1). Depois de reposto, `site_visits.origem` já aceita `ipg-*`/`pago-ipg`
(regra `^[a-z0-9-]{1,48}$`). Vale a pena um filtro "Campanha IPG" nesse ecrã. Não mexi.

## PARA O DANILO
- Responde no Telegram, vídeo a vídeo: "aprovado" ou o que queres mudar.
- Diz se os sacos com nome de marca (versões orgânicas) ficam ou saem (risco 1).
- Blocos 3 e 4 só arrancam depois disso. O botão final de pagamento será sempre teu.
- O Córtex MCP precisa de ser reautorizado nas definições do conector (não tem sessão).

## Onde está tudo
- Vídeos finais: `Desktop\Bora\videos-ipg\*.mp4`; legendas `LEGENDAS.md`.
- Motor de montagem `montar_ipg.py` + `planos/*.json` + `render_e_fiscal.sh`; captura da app
  `_material/app/{explorar,estados}.py`; envio Telegram `enviar-video-telegram.sh` (também em
  `/opt/data/scripts/` na VPS).
- Cópia do código no repositório: `docs/marketing/videos-ipg/` (ramo `autonomous-night-2026-04-29`).
