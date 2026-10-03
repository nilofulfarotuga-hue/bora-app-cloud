---
id: knowledge-debt
tipo: conceito
origem: [gerado por _tools/cortex_nightly.py]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# 💳 KNOWLEDGE DEBT — o cartão de dívida do cérebro

> **AUTO-GERADO** por [[_tools/cortex_nightly]]. **Não editar à mão** — é recalculado a cada corrida.
> Lista as páginas em dívida: `confianca < 50%` **OU** não confirmadas há **> 180 dias**
> **OU** `origem: [NAO_VERIFICADO]`. Quanto maior a lista, mais o cérebro precisa de curadoria.

## Como se mede (ver [[schema]] §Confiança)
- `confianca` é **derivada**, nunca chutada: 100% no dia da `ultima_confirmacao`, decai **−1%/semana**.
- `origem: [NAO_VERIFICADO]` → arranca em **40%**.
- `validade_dias` expirado → confiança colapsa para **0%** (dívida imediata).

## Primeira geração (parcial — 2026-07-08)
> A régua completa só fica ativa **depois** do Bloco 1 (frontmatter de identidade aplicado às páginas)
> e da 1ª corrida real do `cortex_nightly`. Até lá, esta é a dívida **conhecida à mão**:

| Página / conjunto | Motivo da dívida | Ação sugerida |
|---|---|---|
| `permanente/**` sem frontmatter de identidade | `origem` ainda não carimbada (Bloco 1 faseado) | carimbar em batches → sobe confiança |
| `_importado-velho/**` (33) | arquivo histórico sem `origem` verificável | manter como arquivo; **não** promover a permanente |
| `inbox/**` (9 sessões re-alojadas) | aguardam janela de 14 dias | `cortex_nightly` decide promover/descartar |
| `INDEX.md` (linha ~78) | aponta vault velho `Desktop\Bora` (superado) | handoff `bibliotecario-cerebro` → apontar `.obsidian-vault` |

*(Contagem numérica real será preenchida pela 1ª corrida do `cortex_nightly --report`.)*
