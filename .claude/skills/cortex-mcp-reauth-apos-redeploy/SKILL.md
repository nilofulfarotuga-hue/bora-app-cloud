---
name: cortex-mcp-reauth-apos-redeploy
description: "Usar no arranque se o cortex_buscar/cortex_ler não responder: o OAuth do Córtex perde-se a cada redeploy da VPS. Confirmar o contentor e avisar o Danilo numa linha; não bloquear a missão."
metadata:
  versao: 1.0
  criada: 2026-09-17
  criada_por: vigia-habilidades (corrida 2026-09-17_1141)
  tema: "Córtex MCP perde autenticação a cada redeploy, repetido em pelo menos 2 sessões"
  origem: texto-automatico-nao-fala-do-danilo
  origem_corrigida_em: 2026-09-17
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# cortex-mcp-reauth-apos-redeploy

> Criada pelo vigia a 17/09/2026 a partir de texto automatico (ordens/despacho/memoria), nao de uma fala literal do Danilo - origem corrigida a 17/09/2026 (ver seccao Origem). A regra mantem-se porque foi validada.

# Córtex MCP — reautenticação após redeploy

## Quando usar
Sempre que `cortex_buscar`, `cortex_ler` ou `cortex_listar` não responderem ou vierem vazios/sem ferramentas no início de uma sessão.

## Diagnóstico rápido
1. Confirma se o contentor do Córtex na VPS está vivo (ssh + docker ps).
2. Testa `initialize` / `tools/list` diretamente no MCP.
3. Se o contentor está vivo mas as tools não aparecem à Claude.ai/Claude Code: é o padrão conhecido — o OAuth perdeu-se no redeploy.

## O que fazer
- NÃO ficar a tentar repetidamente sem avisar.
- NÃO bloquear a missão à espera — segue com o resto do trabalho e regista no relatório que o Córtex ficou sem autenticação nesta sessão (para não se perder essa informação, como já aconteceu 2x).
- Avisa o Danilo numa linha simples: "Córtex sem sessão, precisa reautorizar o conector" — só ele consegue reautorizar.
- Regista a ocorrência (data + sessão) para o vigia de habilidades acompanhar a frequência.

## Origem (corrigida a 17/09/2026)
paginas estado-2026-09-13 e digest-2026-09-14 da claude_ai_memoria (escritas pela Claude.ai/Claude Code) - NAO e fala literal do Danilo; conhecimento operacional confirmado em 2 sessoes/dias distintos.
