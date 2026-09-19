---
id: licao-casca-sem-fio
tipo: licao
origem: [IncomingJobAlert (rodada 1 Parte 6 → rodada 2 Parte 1) · mega-fix 2026-07-18]
ultima_confirmacao: 2026-07-18
zona: verde
confianca: verificado
---

# Lição — um serviço/widget criado mas com ZERO chamadores é "casca sem fio", não é "feito"

**Problema.** Na rodada 1 criei `lib/services/incoming_job_alert.dart` (o alerta persistente
reutilizável) e dei a parte por entregue. Um `git grep IncomingJobAlert` mostrou **0 chamadas** em
todo o `lib/` — o serviço existia mas não estava ligado a nada. O pedido nº1 do Danilo (sobrepor a
tela ao chegar trabalho) continuava por cumprir, apesar de o código "existir".

**Causa real.** "Criar o componente" e "ligar o componente" são dois trabalhos distintos. É fácil
declarar vitória no primeiro e esquecer o segundo — sobretudo quando o componente compila limpo
(analyze verde não prova que é chamado).

**Regra generalizável.**
- Antes de dar por feita uma feature que introduz um serviço/widget/RPC novo, **procura os call
  sites**: `git grep NomeDoNovo` (ou o equivalente). Zero chamadores = não está feito, é casca.
- Uma peça só entrega valor quando algo a INVOCA num caminho que o utilizador percorre. Declara
  "feito" pelo call site, não pela existência do ficheiro.
- No relatório, distingue "criado" de "ligado" — se ligaste, diz onde; se não, é bloqueio aberto.

Código sem chamadores é potencial, não resultado. Ver [[licao-notify-canal-errado]] (a outra ponta:
mensagem enviada mas não roteada — também "meio ligado").
