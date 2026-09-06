---
name: marketing-loop
description: Loop semanal de aprendizado de marketing — lê métricas do Postiz, compara variações/personas, grava aprendizados no Córtex (camada 14d) e sugere a próxima campanha com dados. Use quando o Danilo pedir "como foi o marketing esta semana" ou no cron semanal do Hermes (domingo à noite). Sem Postiz/contas/dados → modo no-op registado (nunca inventa métricas).
metadata:
  type: marketing
  versao: 1
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: missao-noturna-2026-07-09
---

# Marketing Loop — ciclo semanal (domingo à noite)

## Pipeline
1. **Fonte de dados:** API do Postiz (`POSTIZ_URL`/`POSTIZ_API_KEY` de `infra/postiz-pc/.env`)
   → posts publicados nos últimos 7-14 dias + métricas por post (reach/likes/comments/clicks
   conforme a rede expõe).
2. **Sem dados** (Postiz off, contas não ligadas, 0 posts publicados) → **modo no-op**:
   grava `inbox/marketing-aprendizados-<data>.md` com uma linha "no-op: <motivo>" e envia
   1 linha ao Telegram. FIM. Nunca inventar números.
3. **Com dados — comparar:**
   - por PERSONA (cliente/estafeta/parceiro/TVDE): qual gancho puxa mais?
   - por CONCEITO (c1/c2/c3 da mesma persona): qual arte performa?
   - por CANAL e por HORÁRIO (12h30 vs 19h30).
4. **Aprendizado** → `inbox/marketing-aprendizados-<data>.md` (frontmatter padrão, camada
   14d — o bibliotecário decide o que promove a permanente): 3-5 factos com números +
   1 recomendação acionável cada.
5. **Sugerir próxima campanha:** brief curto para o `diretor-criativo` baseado no que
   funcionou (persona vencedora → dobrar; perdedora → gancho novo). NÃO executa a campanha —
   deixa o brief no relatório.
6. **Telegram (via Hermes):** resumo de 5 linhas máx.

## Cron
Host da VPS, domingos 21h30 Lisboa (script `/root/marketing-loop-weekly.sh` → docker exec
hermes one-shot que corre este pipeline em modo análise). Instalado na missão 2026-07-10.

## Guardrails
- READ-ONLY sobre o Postiz; nunca agenda/publica (isso é o social-publisher, com aprovação).
- Métricas citadas têm SEMPRE fonte (post ID); sem fonte → não entra no aprendizado.

## Telemetria (fim)
Frontmatter + linha em `wiki/skills-metrics.md`.

## Admin Panel Needed?
Métricas entram na proposta `AdminMarketingScreen` (secção métricas) — sem ecrã próprio.
