---
id: licao-classificador-zona-menos-sensivel-a-palavras
tipo: licao
origem: [orquestracao/carteiro.sh · permanente/semantica/zonas-protegidas.md]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: auto
---

# Lição — o classificador de zona (verde/vermelha) deve ler INTENÇÃO, não só palavras

**Problema.** O filtro T3 do carteiro (`zona vermelha NUNCA no loop`) pintava de vermelho **qualquer
tarefa que apenas MENCIONASSE** um termo protegido (`stripe`, `payment`, `pricing_service`,
`bora_tokens`, `dispatch_engine`, `wallet`, `ledger`, `refund`, …). Uma ordem inofensiva como
*"testar o fluxo de pagamento"* ou *"ler o pricing_service"* era travada como se fosse mexer em
dinheiro. Consequência real: o Danilo tinha de **reescrever a mesma tarefa várias vezes**, trocando
palavras até uma versão passar por verde. Fricção pura, sem ganho de segurança.

**Causa.** `carteiro.sh` fazia `echo "$tarefa" | grep -iqE "$RED"` — presença do termo = vermelho,
sem olhar para o verbo. Leitura, teste e validação eram indistinguíveis de escrita.

**Solução (2026-07-11).** Vermelho passa a exigir **intenção de escrita**, não só a palavra:
- `RED_ALWAYS` — ações destrutivas por si só (`--force`, `force-with-lease`, `reset --hard`,
  `disable row level`) → **vermelho SEMPRE**, sem depender de verbo.
- `RED_TERMS` — os domínios de dinheiro (nomes) → vermelho **só** se houver escrita junto.
- `WRITE_INTENT` — verbos de escrita PT (`mudar/atualizar/alterar/modificar/mexer/aplicar/deploy/
  reescrever/gravar/configurar/corrigir/ajustar/…`) **OU** comandos SQL de escrita
  (`UPDATE/INSERT/DELETE/ALTER/DROP/TRUNCATE`).
- `NEG` — remove `sem corrigir`, `nao alterar`, `nunca mexer` etc. **antes** do teste de escrita
  (leitura que nega escrita ≠ escrita).

Regra final: **vermelho = `RED_ALWAYS`  OU  (`RED_TERMS` E `WRITE_INTENT`)**.
Função `zona_vermelha()` no `carteiro.sh`. Proteção real intacta: qualquer escrita genuína nesses
domínios continua vermelha, sem exceção — ver [[zonas-protegidas]] (a Trava dos hooks é o backstop duro).

## 3 exemplos antes → depois

| Frase | Antes | Depois | Porquê |
|---|---|---|---|
| "Testar o fluxo de **pagamento** e confirmar que o **webhook** do **stripe** marca a ordem paga" | 🔴 travava | 🟢 passa | só teste/leitura, nenhum verbo de escrita |
| "Ler o **pricing_service** e explicar o cálculo da taxa" | 🔴 travava | 🟢 passa | leitura, sem intenção de alterar |
| "Auditar o **ledger** e reportar entries órfãs, **sem corrigir** nada" | 🔴 travava | 🟢 passa | `NEG` neutraliza o `corrigir` negado |
| "**Mudar a lógica** de comissão no **pricing_service** para 12%" | 🔴 travava | 🔴 **continua** | verbo `mudar` + domínio $ |
| "Fazer **UPDATE** na tabela **bora_tokens**" | 🔴 travava | 🔴 **continua** | comando SQL de escrita + domínio $ |
| "**git push --force** para a main" | 🔴 travava | 🔴 **continua** | `RED_ALWAYS` (destrutivo puro) |

## Verificação
`bash .claude/.ai/hermes/orquestrador-carteiro/deploy/_zona_fn_test.sh` → **12/12 OK** (faz sourcing
da função real do carteiro, sem duplicar lógica). Ordem simulada (a) teste/leitura → 🟢; (b) mudar
lógica → 🔴.

## Regra generalizável
Um guard de "zona sensível" que casa **só por palavra-chave** gera falsos-positivos que treinam o
humano a fazer *prompt-laundering* (trocar palavras até passar). Casar por **verbo/ação** (escrita
vs leitura), com negação tratada, mantém a mesma proteção com muito menos fricção — e o backstop
duro (a Trava dos hooks) continua a apanhar qualquer escrita real que escape ao pré-filtro.

> ⚠️ Nota de deploy: esta lição alterou a **cópia no repo** (`deploy/carteiro.sh`). O carteiro **vivo**
> corre no VPS (`/root/orquestracao/carteiro.sh`) — sincronizar para lá é passo separado (fora do
> âmbito autónomo por mexer no guard de produção; ver DEPLOY.md).
