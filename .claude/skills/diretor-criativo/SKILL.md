---
name: diretor-criativo
description: Diretor criativo do Bora — gera campanhas de marketing completas (estratégia → copy anti-slop → artes via nano-banana → adaptação por canal → auto-crítica) SEMPRE ancoradas no brand-brain. Use quando o Danilo pedir campanha, post, banner, anúncio ou material de marca. Nunca publica — entrega a pasta da campanha; publicação é da skill social-publisher após aprovação.
metadata:
  type: marketing
  versao: 2
  execucoes: 1
  sucessos: 1
  falhas: 0
  ultima_execucao: 2026-07-10
  criada_por: missao-noturna-2026-07-09
  changelog_v2: 2026-07-10 evolution-engine (prova real Fase 5) — restrições pré-geração vindas das 5 reprovações do gate na campanha bora-chegou-a-guarda; Juiz aprovou (anti-trapaça CLEAN, só adiciona restrições)
---

# Diretor Criativo — pipeline de campanha

> Dono humano: Danilo. Dono agente: `diretor-criativo` (agentes: ver `.claude/agents/`).
> Fronteira: `catalogo-visual` = imagens de PRODUTO/categoria; esta skill = MARCA/campanha.

## Pipeline (ordem obrigatória)

### 1. Brief
Recebe: objetivo (awareness/instalação/candidatura/parceria), persona(s)-alvo, ocasião,
canal(is), prazo. Se faltar o objetivo, assume awareness local e regista a assunção.

### 2. Brand-brain SEMPRE
Ler `.claude/.ai/knowledge/permanente/semantica/brand-brain.md` INTEIRO antes de qualquer
palavra ou pixel. Números só de lá (ou de `business_rules.md` por secção). Violação das
"Regras DURAS" = peça morta.

### 3. Estratégia (por peça)
`objetivo → persona → dor → gancho → promessa (verificável!) → CTA concreto`.
Uma peça = UMA persona = UM gancho. Escrever em `estrategia.md`.

### 4. Copy com filtro anti-slop
Escrever PT-PT no tom do brand-brain. Passar SEMPRE pelo filtro:
`referencias/stop-slop/SKILL.md` (regras + quick checks; scoring ≥35/50) adaptado a PT-PT
(sem travessão decorativo, sem "não é X, é Y", sem tríades metronómicas, voz ativa, "tu").
Disclaimer de ganhos onde a regra manda.

### 5. Artes via MCP nano-banana
Para cada conceito: gerar com `mcp__nano-banana__gemini_generate_image` (aspect ratio via
`set_aspect_ratio`): **feed 1080×1080 (1:1) · story 1080×1920 (9:16) · banner 1200×628
(~1.91:1)**. Prompt de imagem inclui: paleta (verde #16A34A dominante, fundo #F0F2EF,
UM acento laranja #F97316), tipografia Inter (ou "sem texto na imagem" e o texto entra
por cima depois), cena LOCAL (Guarda: Sé, muralhas, serra, comércio de rua — nunca skyline
genérica), sem gradiente roxo, sem glassmorphism, sem cara de stock-IA.
Logo: NUNCA pedir à IA para desenhar o logo — reservar zona limpa e compor com
`assets/branding/bora_logo.png`.

**Restrições pré-geração (v2 — OBRIGATÓRIAS em todos os prompts de imagem).** Aprendidas
das 5 reprovações do gate na campanha "O Bora chegou à Guarda" (2026-07-10) — prevenir na
geração é mais barato do que refazer:
- **ZERO texto embutido na imagem** (qualquer palavra/letreiro legível entra depois, por
  composição) — exceção única: sinalética de fundo desfocada e ilegível;
- **PT-PT nos elementos de cena**: nunca "LANCHONETE"/brasileirismos em fachadas ou objetos;
- **Matrículas SEMPRE ilegíveis/ausentes** (desfocadas ou fora de quadro);
- **Volante à ESQUERDA** (Portugal — condução à direita) em qualquer interior de veículo.
Falha em qualquer uma destas no gate → registar em `falhas` da telemetria (não só refazer).

### 6. Adaptação por canal
IG feed (1:1, copy curto + hashtags locais #Guarda #BoraApp), IG/FB story (9:16, CTA
grande), FB post (banner 1200×628 + texto), WhatsApp Status (9:16 simplificado).

### 7. Auto-crítica (gate antes de entregar)
Checklist: [ ] anti-slop visual (catálogo `avoid-ai-design/references/ai-tells-catalog.md`
— zero P0) · [ ] anti-slop prosa (stop-slop ≥35/50) · [ ] brand (verde dominante, 1 laranja,
Inter, logo intacto) · [ ] TODOS os números batem com brand-brain/business_rules · [ ]
PT-PT sem brasileirismos · [ ] disclaimer de ganhos presente onde preciso · [ ] CTA concreto.
Peça que falha → refazer (máx 2 iterações; à 3ª falha regista e segue).

### 8. Output
```
marketing/campanhas/<slug>/
  estrategia.md          (objetivo/persona/gancho por peça)
  copy.md                (copy final por peça e canal + score anti-slop)
  feed/  story/  banner/ (PNGs por conceito: <persona>-c<1|2|3>.png)
  calendario-sugerido.md (datas/horas sugeridas — 12h30/19h30 Lisboa, dias alternados)
```
NUNCA publica. Entrega + pergunta se agenda via `social-publisher` (que exige aprovação).

### 9. Telemetria (obrigatório no fim)
Incrementar `execucoes` e `sucessos`/`falhas` + `ultima_execucao` no frontmatter desta
skill, e acrescentar linha em `.claude/.ai/knowledge/wiki/skills-metrics.md`:
`| diretor-criativo | <data> | <campanha> | <n peças> | <resultado> |`

## Admin Panel Needed?
Sim — proposta registada: `AdminMarketingScreen` (PT-BR): listar campanhas geradas,
estado (rascunho/aprovada/agendada/publicada), pré-visualização das artes, botão aprovar →
social-publisher. **Especificada, NÃO construída** (fila do admin).
