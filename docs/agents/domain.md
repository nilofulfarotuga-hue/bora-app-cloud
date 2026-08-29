# Documentos de dominio — como os agentes os consomem

Layout: **single-context** (o repo nao e monorepo — nao ha `pnpm-workspace.yaml`
nem `packages/*/src`).

## Ler antes de explorar o codigo

- **`CONTEXT.md`** na raiz do repo — o vocabulario real do Bora (parceiro vs
  nao-parceiro, comissao, dispatch, tokens, zona verde/vermelha, ordem, carteiro,
  juiz, Cortex, Hermes).
- **ADRs**: `.claude/.ai/knowledge/wiki/decisoes/` — **nao** `docs/adr/`. As decisoes
  do Bora ja vivem no Cerebro e sincronizam para o Obsidian; abrir `docs/adr/` criaria
  gemeos desalinhados, que e precisamente o que o `PADRAO_BORA.md` proibe.

Se algum destes nao existir, **segue em silencio**. Nao assinales a ausencia nem
proponhas cria-los a frente. O `domain-modeling` cria-os quando um termo ou uma
decisao e mesmo resolvida.

## Usa o vocabulario do glossario

Quando a tua saida nomear um conceito do dominio (titulo de bilhete, proposta de
refactor, hipotese, nome de teste), usa o termo tal como esta definido no
`CONTEXT.md`. Nao derives para sinonimos que o glossario evita de proposito —
confundir "parceiro" com "nao-parceiro" e erro grave, mexe em dinheiro.

Se o conceito ainda nao estiver no glossario, e sinal de uma de duas coisas: ou estas
a inventar linguagem que o projeto nao usa (repensa), ou ha um buraco real (anota
para o `domain-modeling`).

## Marca o que e deducao

O `CONTEXT.md` do Bora distingue o que veio de fonte escrita do que foi deduzido.
Tudo o que for deducao esta marcado `POR CONFIRMAR`. **Nao trates um `POR CONFIRMAR`
como facto** — e uma pergunta a espera de resposta do Danilo.

## Assinala conflitos com ADRs

Se a tua saida contradisser um ADR existente, di-lo em vez de o atropelar em silencio:

> _Contradiz a decisao X, mas vale a pena reabrir porque…_
