---
tema: destravar-tudo · escopo: sessão · estado: atual · atualizado: 2026-07-11
tipo: relatorio
origem: [sessão "destravar tudo" 2026-07-11, exceção copy-paste pedida pelo Danilo]
zona: verde
---

# Relatório — "Destravar tudo" (2026-07-11)

Correção importante em relação à premissa do pedido: **o carteiro/campainha NÃO estavam
mortos.** `orq-campainha.service` está `active (running)` no VPS há 2 dias, o kill switch
(`orquestracao_enabled`) está `true`, e o `carteiro.log` mostra ciclos contínuos até
18:49. O problema real é **backlog**: a fila tinha **49 ordens**, processadas 1 de cada vez
(flock serializa), cada tentativa demorando 10–15+ min (executor + juiz + até 5 retries).
As 2 ordens novas (18:13 e 18:41) estavam mesmo em `tentativa: 0` — só ainda não tinham
sido alcançadas na fila, não por avaria. Por isso a exceção copy-paste fez sentido na
mesma (era mesmo mais rápido fazer direto do que esperar o backlog).

## 1. Loop antigo — verificado, nada a parar
- `schtasks` — nenhuma tarefa chamada `BoraE2E`/`bora-e2e`/`loop-noturno`/`run-tudo`/
  `BoraLoop` existe no Agendador do Windows. A única tarefa Bora agendada é
  `BoraTesteFechadoMonitor` (09:03 diário) — **não mexe em telemóveis**, só consulta a Play
  Developer API para o rastreio dos 12 testadores. Deixada como está.
- `taskkill /F /IM maestro.exe` — processo não encontrado (não estava a correr).
- Únicos `python.exe` ativos eram do `graphify-mcp` (MCP não relacionado) — não tocados.
- `adb devices`: **RZGYB1XQD2P** tinha caído para `unauthorized`. Resolvido com
  `adb kill-server` + `adb start-server`. Agora os 2 telemóveis estão `device` (livres e
  autorizados): `N75LTG5X5DSKDMV4` e `RZGYB1XQD2P`.

## 2. Carteiro/campainha — vivos; as 2 ordens presas foram executadas diretamente
Investigação completa no VPS (systemctl, docker ps, `_controlo.md`, `carteiro.log`,
`campainha.log`, cron) confirmou o loop saudável (detalhe acima). As duas ordens
`ordem-20260711184146-c349` e `ordem-20260711181356-c98b` foram lidas via Córtex e
**executado diretamente o que pediam** (ver relatórios próprios abaixo), depois marcadas
`estado: aprovada` no Córtex para o carteiro (quando as alcançar no backlog) não as
reprocessar do zero.

## 3. Monitor visual — aberto na tela
Criado `.claude/testes-e2e/monitor-bora.cmd` + `.claude/testes-e2e/tail_e2e_log.py`.
Executado: 2× `scrcpy --always-on-top` (`Bora-N75LTG5X5DSKDMV4`, `Bora-RZGYB1XQD2P`) +
1 janela `cmd` com tail de 5s das últimas 15 linhas de `e2e_log` (hora | fluxo | passo |
estado). Milestones registados em `e2e_log`.

## 4. Filtro de palavras — já estava corrigido no repo, faltava no VPS; agora deployado
A lição `wiki/licoes/classificador-zona-menos-sensivel-a-palavras.md` (2026-07-11) já
tinha reescrito `zona_vermelha()` no repo (`deploy/carteiro.sh`) para exigir **intenção de
escrita**, não só a palavra. O `diff` confirmou que essa era a ÚNICA diferença entre o
repo e o `carteiro.sh` vivo (`/root/orquestracao/carteiro.sh` no VPS) — o resto idêntico.
Feito backup (`carteiro.sh.bak-20260711190615`), copiada a versão corrigida, e validado:
**12/12 testes OK** (`_zona_fn_test.sh`) + sintaxe bash OK. Live desde agora.

Filosofia gravada em `constituicao.md` (princípio 11) e `convencoes.md`: **"não pisar em
casca de ovo com palavras — só escrita real em dinheiro é vermelha; em dúvida, pergunta
ao Danilo."**

## 5. Ponto de retoma gravado
`permanente/semantica/estado-teste-e2e.md` (novo, indexado em `INDEX.md`): o teste
`delivery-mercado-cash` chega até "abre lista de produtos"; falta tocar produto → botão + →
carrinho → cash → confirmar → `orders`. Bug pendente: entidades HTML nos nomes do
Continente (`C&atilde;o` → `Cão`). **Não recomecei o teste** — só o ponto de retoma, como
pedido.

## O que NÃO foi feito (fora do âmbito pedido)
- Não recomecei o teste E2E completo.
- Não reduzi o backlog de 49 ordens (fora do pedido; se quiseres, próximo passo natural é
  o CEO-AI priorizar/paralelizar ou o Danilo decidir o que arquivar).
- Não toquei em nada da Lista Vermelha (Stripe/pricing/tokens/dispatch) — o classificador
  mexido é o *guard* que protege essas zonas, não as zonas em si.
