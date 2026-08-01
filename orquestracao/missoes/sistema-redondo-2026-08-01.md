--- missao ---
id: sistema-redondo-2026-08-01
tipo: missao
cor: ⚫ Mission (arquiva ao concluir — loops.md)
estado: em_curso
autor: claude-code (Opus) via CEO-AI
criada: 2026-08-01
dono: maestro-autonomia
zona: verde (Partes 4/6 tocam ficheiros sensíveis de segredos/infra — ver notas)
--- fim ---

# 🔵 Missão: Sistema Redondo

## Objetivo declarado pelo Danilo (critério de sucesso)
A noite de 31/07 devolveu o loop a funcionar (dedup, lotes, `reviewed_at`, auth do executor
resolvida, juiz a devolver veredito, aprovação a executar sozinha, sonda diária). Esta missão
fecha as lacunas que ainda impedem o Danilo de simplesmente pedir a Claude.ai e o sistema
resolver sozinho.

## Partes (uma de cada vez — cada uma fecha com prova própria + relatório em ficheiro)

> **FECHO: `.claude/.ai/reports/sistema-redondo-FECHO-2026-08-01.md`** (2026-08-01, sessão Opus).
> 7 partes fechadas, 2 com pendências reais. Espelho de leitura em `public.missions` (o ficheiro manda).

| # | Parte | Estado |
|---|---|---|
| 1 | Classificador de zona + verificação do Juiz cegos a NEGAÇÃO (ordens 3cb4/228a) | ✅ FECHADA E VIVA — deployada VPS+PC, hash igual nos 3 lados, 15/15 e 11/11 verdes |
| 2 | Expor no cortex-mcp: listar propostas 🔴 pendentes + aprovar por id | ✅ FECHADA E VIVA — 25/25; aprovar por chat **não** emite `audit_id` (gate do dinheiro intacto) |
| 3 | `hermes-bridge` do PC sob versão/sync para a VPS + resolver limitação L1 (`/opt/data/.local/bin`) | ✅ FECHADA — 11/11 sem drift; L1 provada e resolvida (`bin-versoes/`) |
| 4 | `executor.lock` vs sessão interativa do Danilo — fila em vez de bloqueio; medir RAM real | ✅ FECHADA — o lock **nunca** bloqueou; a causa é RAM (291 MB livres de 3902). Pré-voo de RAM aplicado |
| 5 | Confirmar fix b64stdin no `pc_judge` do C4; fechar continuação-por-teto em produção; `/ctx doctor`/`/ctx stats` no executor | 🟡 3 de 4 — b64stdin ✅, juiz mudo ✅ (causa achada, 10/10). **Por fazer:** continuação-por-teto nunca nasceu em produção; `/ctx` não corre em lado nenhum |
| 6 | Refazer o trabalho perdido da ordem-228a (settings corrigido + auditoria verify_jwt) | ✅ NÃO PRECISOU — os 2 artefactos sobreviveram no disco com conteúdo real |
| 7 | Fechar C3 do motor de conhecimento (cartão admin) + confirmar bug de scroll + estado da skill CEO-AI | ✅ FECHADA — C3 (`4b111f4`) e scroll (`255c8ac`) já feitos. Skill stale: diz 51, real 60 deployed / 54 locais (não editada) |
| 8 | Investigar e REPORTAR (sem prometer solução): OAuth cortex-mcp perdido a cada redeploy + bloqueio E2E web GPU/swap | 🟡 OAuth **resolvido** (persistência em `/state`, 14/14). **E2E GPU/swap não investigado** |
| 9 | Tornar o estado das missões legível para a Claude.ai | ✅ FECHADA — tabela `missions` (espelho de leitura; o ficheiro manda) |

## Regras da missão
- O estado do git fica como o encontraste — há trabalho pendente na branch; publicar é decisão do Danilo, não desta missão.
- Prova por ficheiro, log ou SELECT — nunca pela palavra do executor.
- Divergência entre VPS, repo e PC: deployar num lado não é deployar no outro — verificar hash dos dois lados antes de dar uma parte por fechada.
- Relatório final gravado em ficheiro com o veredito de cada parte e a lista honesta do que ficou por fazer.
- Zona vermelha (Stripe/pagamentos/pricing/dispatch_engine/bora_tokens/RLS orders-wallets-ledger) = PROPOSE-ONLY; esta missão, pelo enunciado, não deveria tocar aí — se alguma parte esbarrar em dinheiro real, para e escreve "CONFIRMAÇÃO NECESSÁRIA".

---

### PARTE 1 — negação cega no classificador de zona + no Juiz `FECHADA`
> Relatório completo: `.claude/.ai/reports/sistema-redondo-parte1-negacao-2026-08-01.md`

**Prova viva (Danilo):**
- `ordem-20260801071337-3cb4` → classificada 🔴 vermelha porque o corpo dizia para **NÃO** mexer
  em certas áreas protegidas (falso positivo do classificador de zona, `carteiro.sh:zona_vermelha()`).
- `ordem-20260801072105-228a` → nota "a ordem pedia commit/push e NÃO há nenhum commit novo desde
  o arranque" quando o texto dizia **exatamente o contrário** (falso positivo do chão mecânico do
  Juiz, `juiz-mecanico.ps1`, bloco de commit/push).

**Causa-raiz encontrada (ver relatório):**
1. `carteiro.sh` — a lição `classificador-zona-menos-sensivel-a-palavras` (2026-07-11) já tinha
   NEG-awareness, mas `NEG='(sem|nao|não|nunca|jamais) +[a-zàáâãéêíóôõúç]+'` só apaga a palavra de
   negação **+ 1 palavra seguinte**. Frases reais em PT raramente colam o verbo logo a seguir à
   negação (`"não DEVE mexer"`, `"nunca, em circunstância nenhuma, vai ALTERAR"`) — o verbo de
   escrita sobrevive à limpeza e o termo $ continua a bater.
2. `juiz-mecanico.ps1` — o bloco `(b) ordem pedia commit/push` (defeito A, 2026-07-16) já era
   negação-aware, mas com uma **janela fixa de 24 caracteres, só para trás** do termo `commit/push`.
   Negação mais distante ou **depois** do termo (`"faz o diagnóstico; não faças commit nem push"`)
   fica fora da janela e o bloco continua a exigir commit novo no git log.

**Fix aplicado — negação por CLÁUSULA em vez de janela fixa de 1 palavra / 24 chars:**
Ambos os classificadores passam a dividir a tarefa em cláusulas (fronteira de frase `. ! ? ; \n`
**e** conjunções contrastivas `mas/porém/contudo/entretanto`, que reiniciam a polaridade). Dentro
de cada cláusula: termo $ + verbo de escrita (ou `commit/push`) **só conta se não houver negação
em qualquer ponto da MESMA cláusula** (antes ou depois do termo, sem limite de distância). Uma
negação numa cláusula anterior/seguinte (separada por `mas`/ponto) **não** apaga um termo genuíno
noutra cláusula — evita o extremo oposto (suprimir tudo por haver uma negação em qualquer lugar do
texto).

**Ficheiros tocados:**
- `.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh` — `zona_vermelha()` reescrita.
- `.claude/.ai/hermes/orquestrador-carteiro/deploy/_zona_fn_test.sh` — +3 casos de regressão
  (gap largo negação↔verbo; cláusula com `mas` que NÃO deve ser suprimida).
- `.claude/.ai/hermes/orquestrador-carteiro/deploy/juiz-mecanico.ps1` — bloco `(b)` extraído para
  a função `Get-CommitIntent`, testável isoladamente, mesma lógica de cláusula.
- `.claude/.ai/hermes/orquestrador-carteiro/deploy/_juiz_mecanico_commit_test.ps1` — novo, testa
  `Get-CommitIntent` isolado (mandato / proibição / gap largo / depois do termo / misto com `mas`).

**Prova exigida:** os dois testes (`_zona_fn_test.sh`, `_juiz_mecanico_commit_test.ps1`) verdes,
incluindo os casos novos que replicam os padrões das ordens 3cb4/228a.

**⚠️ Limitação honesta (não escondida):** a correção está na **cópia do repo**
(`deploy/carteiro.sh` + `deploy/juiz-mecanico.ps1`). O carteiro e o juiz-mecânico **vivos** correm
no VPS/PC fora deste repo (mesma limitação já registada na lição de 2026-07-11 e na Parte 3 desta
missão — `hermes-bridge` fora de versionamento). Esta parte não tem acesso SSH/docker à VPS a
partir desta sessão (sem entrada no `~/.ssh/config`, sem `docker` no PATH) — sincronizar para lá
é passo separado, tal como já era prática estabelecida. Fica registado como pendência real, não
arredondado.
