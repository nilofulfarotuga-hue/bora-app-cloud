---
name: buzz
description: Poe varios modelos do plano OpenCode Go a debater a MESMA tarefa ate consenso (ronda 0 as cegas, depois concordar/refutar), e le o relatorio para tu decidires como juiz. Usa quando o Danilo disser "buzz", "poe os modelos a discutir", "debate isto", "segunda opiniao dos outros modelos", ou quando uma decisao for suficientemente importante para merecer mais do que uma cabeca. NAO aplica nada - so produz relatorio.
metadata:
  type: orchestration
---

# /buzz — debate multi-modelo, tu es o juiz

O `buzz.py` faz os modelos do plano OpenCode Go discutirem entre si. Tu (Opus) ficas
de fora do debate e entras no fim como juiz. O debate inteiro corre no plano fixo do
Go ($10/mes) — não gasta o plano Claude.

## Como correr

```bash
python "C:/Users/danil/Desktop/ferramentas/buzz/buzz.py" --tarefa "<a tarefa>" --pasta "<pasta do projeto>" --rondas 3
```

Argumentos:

| Argumento | Para que serve |
|---|---|
| `--tarefa` | obrigatório. O que queres que eles decidam. |
| `--pasta` | pasta do projeto. O relatório é escrito lá. Por defeito, a pasta atual. |
| `--ficheiros` | `a.md,src/b.js` — conteúdo que os modelos devem ver (30 KB máx por ficheiro). |
| `--rondas` | rondas de debate depois da ronda às cegas. Por defeito 3. |
| `--modelos` | por defeito `glm-5.2,qwen3.7-max,kimi-k3`. Não uses `qwen3.8-max` — está em baixo do lado do fornecedor. |

O script é sequencial e demora: conta ~1 min por modelo por ronda. Corre-o em
background e vai fazendo outra coisa.

## O que fazer com o resultado

1. Lê o `BUZZ_RELATORIO_<data>.md` que aparece na pasta do projeto.
2. **Vai primeiro à secção 2 — "Divergências que sobraram".** É onde está o desacordo real.
   Consenso sem divergência às vezes só quer dizer que se copiaram uns aos outros.
3. **Verifica no código/site o que eles afirmam.** Os modelos do debate não leram o
   repositório nem abriram o site — só receberam texto. Trata as afirmações como
   hipóteses, não como factos.
4. Só depois decides: o que se aplica, o que fica de fora, e porquê. Diz ao Danilo
   as duas listas.

## Regras

- O buzz **nunca aplica** nada. Escreve um relatório e morre. Aplicar é decisão do juiz.
- Não entres tu no debate. O valor está em eles não te verem — se vissem a tua
  resposta, limitavam-se a confirmá-la.
- Se um modelo falhar com `GoUsageLimitError`, o limite semanal do plano acabou. O
  relatório diz quais falharam; um debate com menos de 2 modelos vivos não vale nada.
- Serve para qualquer pasta: `bora_app`, `guarda-fc-site`, mini-sites, PartsFlow.
  Não tem nada do Bora escrito lá dentro.
