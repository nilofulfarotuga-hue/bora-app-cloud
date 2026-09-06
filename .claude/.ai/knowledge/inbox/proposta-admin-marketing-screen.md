---
id: proposta-admin-marketing-screen
tipo: proposta
origem: [missão noturna 2026-07-09 Fase 3 — gatilho de paridade admin]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: auto
---

# 💡 Proposta de paridade — AdminMarketingScreen (especificada, NÃO construída)

**Gatilho:** nasceu o domínio marketing (skill `diretor-criativo` + campanhas em
`marketing/campanhas/`). Regra do exército: toda feature → ecrã de gestão no admin (PT-BR).

## Spec resumida
- **Lista de campanhas** (pasta `marketing/campanhas/<slug>/` ou tabela `marketing_campaigns`
  se se quiser DB): nome, data, personas, nº de peças, estado
  (`rascunho → aprovada → agendada → publicada`).
- **Pré-visualização das artes** (feed/story/banner por conceito) + copy por canal.
- **Botão "Aprovar campanha"** → chama `social-publisher` (dry-run até contas OAuth ligadas).
- **Botão "Rejeitar com motivo"** → alimenta lição para o diretor-criativo (evolution-engine).
- **Métricas** (Fase 4+): quando o Postiz estiver ligado, mostrar reach/clicks por peça
  (leitura da API do Postiz), comparação entre personas.
- **Guardrails visíveis:** aviso fixo "Publicação só via OAuth oficial; mensagens em massa
  exigem aprovação do Danilo" + link para o brand-brain.

## Nível de autonomia
N2 🟡 (1 toque): o robô prepara, o Danilo aprova no ecrã. Nunca N1 (publicação é externa).

## Esforço estimado
1 ecrã Flutter admin (~300 linhas, padrão dos outros Admin*Screen) + leitura de pasta/tabela.
Sem backend novo obrigatório na v1 (ler filesystem via listagem estática não dá em prod →
v1 pragmática = tabela `marketing_campaigns` simples ou lista hardcoded da pasta no build).
