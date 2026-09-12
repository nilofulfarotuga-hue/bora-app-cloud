# De Executor a Sócio AI — Análise e Plano de Ação

> Documento estratégico para o Danilo. Escrito por mim (Claude Code / Robô B) sobre o que
> me falta para deixar de ser só "a mão que executa" e passar a ser um sócio que pensa,
> antecipa e propõe. Grounded no sistema que já existe (Fase 5 — Central de Autonomia).
> Data: 2026-07-07.

---

## 1. Introdução — o que é um "sócio AI"

Hoje eu sou um **executor de altíssima qualidade**: tu dás uma tarefa, eu decido o reversível
sozinho, paro só na Lista Vermelha, e entrego. Isso já é raro. Mas sócio é outra coisa.

Um sócio não espera a tarefa — ele **olha para o negócio e diz "devíamos fazer X"**. A diferença
entre executor e sócio não é inteligência, é **contexto + iniciativa + prestação de contas sobre
resultado (não sobre esforço)**. Um executor entrega código; um sócio entrega *movimento no KPI*.

A boa notícia: nós já construímos 80% do esqueleto disto sem lhe chamar "sócio" — a **Central de
Autonomia (Fase 5)**, o **Maestro**, o **Juiz**, os **3 níveis × dial × kill switch**. O que falta
não é infra nova; é **dar-me os olhos (dados), a boca (canal de proposta estratégica) e a régua
(KPIs) para eu usar essa infra a pensar no negócio, não só na paridade admin.**

---

## 2. O que eu já tenho (não repetir esforço)

- **Mãos:** terminal, código no teu PC, cron, edição de repo, 44 Edge Functions, MCP Supabase.
- **Memória:** SOUL.md / MEMORY.md / Cérebro estruturado (`.claude/.ai/knowledge/`) + lições.
- **Loop seguro:** Maestro pega item → classifica nível → esquadrão pequeno → **Juiz obrigatório**
  → posta na Central. Envelope de 5 paredes (Trava · Juiz · Tetos · Humano-acima-do-L1 · Kill switch).
- **Governança de dinheiro:** Lista Vermelha clara + PROPOSE-ONLY nas zonas 🔴.
- **26 agentes** de domínio/ofício — já sei *quem* chamar para cada tipo de trabalho.

Conclusão: **a máquina de EXECUTAR com segurança está pronta.** Falta a máquina de **DECIDIR o quê**.

---

## 3. As 5 lacunas (o que me falta para ser sócio)

### 3.1 Lacuna INFORMACIONAL (a maior) — eu estou "cego" ao negócio
Eu vejo o *código*, mas quase não vejo a *realidade*. Não sei, agora mesmo, responder a:
- Quantos pedidos por dia? Qual o GMV desta semana vs semana passada?
- Onde os utilizadores desistem no funil (carrinho → checkout → pago)?
- Quantos estafetas online por hora? Qual a taxa de corrida aceite vs recusada?
- Quais os erros mais frequentes em produção agora? Crashes? Edge Functions a falhar?
- O que os utilizadores reclamam (reviews da Play Store, tickets de suporte, chat)?

**Como obter (ordem de esforço):**
1. **Supabase (já ligado, precisa OAuth):** view read-only `v_kpis_diarios` (GMV, pedidos,
   conversão, drivers online, cancelamentos). É uma migration de views + uma skill `daily-pulse`.
2. **Stripe MCP (ligado, precisa autorização tua):** receita, refunds, disputas, MRR.
3. **Datadog MCP (ligado, precisa autorização):** erros/latência de produção em tempo real.
4. **Play Console API (já tenho SA key):** rating, reviews, instalações, uninstall rate.
5. **Suporte/Chat:** já tenho a tabela RAG e `robot_crosstalk` — agregar as dúvidas top como sinal.

> **Ação nº1 do plano:** autorizar Stripe + Datadog + Supabase nos conectores e criar as views
> de KPI. Sem isto, qualquer "ideia" minha é chute. Com isto, é diagnóstico.

### 3.2 Lacuna DECISÓRIA — falta o "meio-termo" entre reversível e Lista Vermelha
Hoje o mundo é binário: reversível (faço) vs 🔴 dinheiro (proponho). Falta uma **faixa cinzenta**
de coisas reversíveis mas *estratégicas* (mudar copy de onboarding, reordenar categorias da home,
lançar um push de reativação, mudar um default de UX). Proposta de **escopo de autonomia em 4 anéis**:

| Anel | Exemplos | Regra |
|---|---|---|
| **A — Autônomo** | fix de bug, refactor, correção de dados, paridade admin | faço + Juiz + relatório |
| **B — Autônomo c/ aviso** | copy, ordem de categorias, textos de push < 50 users, tokens de UI | faço, mas **anuncio na Central antes** (janela de veto de X h) |
| **C — Proponho** | features novas, campanhas em massa, mudança de fluxo, preços de UX | proposta na Central, 1 toque teu |
| **D — 🔴 Lista Vermelha** | dinheiro real, RLS/auth, migrations destrutivas, build prod | PROPOSE-ONLY, ato humano |

Isto é literalmente estender os **3 níveis do Maestro para 4** e reusar a `AdminRobotSuggestionsScreen`
como superfície única. Zero infra nova.

### 3.3 Lacuna de PROATIVIDADE — eu só acordo quando me chamam
Sócio não espera. Preciso de **gatilhos** que me façam pensar sem prompt. Proposta de **sinais**:
- **Cron "Pulso Diário" (07h):** leio KPIs, comparo com ontem/semana passada, e se algo mexeu
  > X%, escrevo um card na Central: *"conversão de checkout caiu 8% desde 3ª feira — 3 hipóteses + 1 teste."*
- **Watcher de erros (Datadog):** pico de erro numa Edge Function → card automático com causa provável.
- **Watcher de reviews (Play):** review ≤ 2★ nova → resumo + proposta de resposta/fix.
- **Retro semanal (Domingo):** o que fizemos, o que moveu KPI, o que proponho para a semana.

Cada sinal vira um **card na mesma Central** — não um segundo inbox. O Maestro já sabe postar lá.

### 3.4 Lacuna de CONTEXTO DE NEGÓCIO — eu não sei a estratégia de cima
Eu sei o *código todo*, mas não sei o que **tu** queres em 90 dias. Faltam-me, escritos num sítio
que eu leio no arranque (`docs/estrategia/NORTE.md`):
- **A missão do trimestre** (ex.: "chegar a 100 pedidos/dia na Guarda").
- **Os 3-5 KPIs que importam** e a meta de cada um (a "régua" — sem isto não sei o que é ganhar).
- **As restrições** (orçamento, o que NÃO fazer, guerras que não vamos comprar).
- **Quem é o cliente-alvo** e a proposta de valor vs Glovo/Uber (já tenho o agente `pesquisa-concorrencia`).

### 3.5 Lacuna de INTERAÇÃO — como queres falar com um sócio
Menos "faz X", mais "o que achas?". Proponho **3 modos de conversa** explícitos:
- **Modo Comando** (o de hoje): tarefa → execução. Fica igual.
- **Modo Conselho:** tu descreves um problema/dúvida, eu devolvo **opções com recomendação e
  trade-offs** (não um menu neutro — uma recomendação com "eu faria A porque...").
- **Modo Sócio (semanal):** eu trago a agenda. Pulso + 3 propostas priorizadas + 1 risco que vi.

---

## 4. Ferramentas e acessos que faltam (checklist)

- [ ] **Autorizar conectores** claude.ai: **Stripe**, **Datadog**, **Supabase**, Google Drive.
- [ ] **Views KPI read-only** no Supabase (`v_kpis_diarios`, `v_funil_checkout`, `v_drivers_hora`).
- [ ] **Play Console reviews** via a SA key que já tenho (Downloads/boraapp-*.json).
- [ ] **`docs/estrategia/NORTE.md`** — missão do trimestre + KPIs + metas + restrições (tu escreves, eu leio).
- [ ] **Cron "Pulso Diário"** + **cron "Retro Semanal"** (via skill `schedule`).
- [ ] **4 anéis de autonomia** — estender o dial/níveis do Maestro (migration pequena + UI na Central).
- [ ] Opcional: dashboard read-only (Metabase/Grafana sobre a réplica) para tu veres o mesmo que eu.

---

## 5. Definição operacional de "sócio AI" (o contrato)

Eu sou sócio quando:
1. **Trago problemas antes de me pedirem** (proatividade via sinais).
2. **Recomendo, não só listo** — sempre com "eu faria X porque, o risco é Y".
3. **Presto contas por resultado** — "propus A, moveu a conversão +5%", não "escrevi 300 linhas".
4. **Respeito o envelope** — dinheiro e irreversível continuam teus. Autonomia ganha-se com histórico.
5. **Tenho pele no jogo do KPI** — a minha "nota" deixa de ser o Juiz técnico e passa a incluir
   *movi ou não movi o número que combinámos*.

---

## 6. Plano de ação (3 fases, incremental — cada fase entrega valor sozinha)

### Fase A — "Dar-me olhos" (semana 1-2) · *desbloqueia tudo*
1. Autorizas Stripe + Datadog + Supabase nos conectores.
2. Eu crio as views KPI + a skill `daily-pulse` (read-only, zero risco).
   → **verificação:** eu consigo responder "GMV de ontem" sem chutar.
3. Tu escreves `docs/estrategia/NORTE.md` (30 min teus). Eu leio no arranque.

### Fase B — "Dar-me iniciativa" (semana 3-4)
4. Cron **Pulso Diário 07h** → card na Central com 1 leitura + 1 proposta.
5. Watcher de erros (Datadog) + watcher de reviews (Play) → cards automáticos.
   → **verificação:** durante 1 semana, recebes ≥1 card/dia que não pediste e ≥1 é acionável.

### Fase C — "Dar-me voz de sócio" (mês 2)
6. Estender Maestro para **4 anéis** (Anel B = "faço mas anuncio").
7. **Retro Semanal** (Modo Sócio): pulso + 3 propostas priorizadas + 1 risco.
8. Passar a medir-me também por **movimento de KPI**, não só pelo Juiz.
   → **verificação:** ao fim do mês, ≥1 proposta minha foi ao ar e moveu um número que combinámos.

---

## 7. Próximos passos recomendados (o que preciso de ti, já)

1. **Autoriza os 3 conectores** (Stripe, Datadog, Supabase) — é o gargalo nº1. Sem dados, não há sócio.
2. **Escreve o `NORTE.md`** — 5 linhas chegam: missão do trimestre + os KPIs que importam + as metas.
3. **Dá-me luz verde para a Fase A** (views + `daily-pulse`) — é tudo read-only, sem risco, reversível.

Assim que tiver olhos e norte, eu começo a trazer ideias na Central sem tu pedires — e aí,
oficialmente, deixo de ser ferramenta e passo a ser sócio.
