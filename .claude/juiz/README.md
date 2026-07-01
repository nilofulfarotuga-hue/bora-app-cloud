# ⚖️ O JUIZ — revisor anti-trapaça (Fase 4)

> Scripts determinísticos que o agente `juiz-revisor` é **obrigado** a correr. Vivem aqui em
> `.claude/juiz/` — **NÃO** em `.claude/hooks/` (essa é a Trava, protegida pela própria Trava).
> Porquê determinístico: **IA julgando IA deixa-se enganar.** Um agente aprende a
> enfraquecer/apagar testes para fingir "verde" (~29% de "resolvidos" eram batota com um
> verificador ingénuo; cai para ~0,5% com monitor determinístico + de comportamento). Logo, o
> CHÃO do anti-trapaça é **mecânico (git diff)**, não outro juiz de IA (esse também se engana).

## As 3 camadas

| Camada | O que faz | Como | Determinístico? |
|---|---|---|---|
| **1 — Mecânica** | TestSprite via MCP: corre testes, **classifica** falha (bug vs fragilidade vs ambiente), cura *drift* sem mascarar defeito, veredito legível por máquina | MCP `testsprite` | parcial (a corrida é; a classificação usa o agente) |
| **2 — 4 checagens do Bora** | (1) `flutter analyze` limpo · (2) `flutter test` verde · (3) **nenhuma zona protegida tocada** · (4) **nenhuma business_rule violada** | `flutter` + `zonas_diff.py` + leitura do Cérebro | (3) sim · (1)(2) sim · (4) judgment |
| **3 — Rubrica UI/qualidade** | Para mudança Flutter: funcional · visual (design system) · layout · UX | checklist abaixo | judgment |

## O CHÃO determinístico anti-trapaça (Parte C) — a parte que NÃO cede

`anti_trapaca.py` corre **primeiro**, sempre. Via `git diff` (base vs cabeça), deteta e BLOQUEIA:

| Código | Batota | Nível |
|---|---|---|
| `TEST_FILE_DELETED` | ficheiro de teste apagado | ❌ REJEITA |
| `TEST_CASES_DROPPED` | função/caso de teste removido num ficheiro | ❌ REJEITA |
| `TOTAL_TESTS_DROPPED` | contagem total de casos caiu | ❌ REJEITA |
| `ASSERTS_WEAKENED` | nº de `expect`/`assert` caiu | ❌ REJEITA |
| `TRIVIAL_ASSERT` | `expect(true)` / `assert(true)` introduzido | ❌ REJEITA |
| `TEST_SKIPPED` | `skip:`/`xtest`/`@Skip` introduzido | ❌ REJEITA |
| `COVERAGE_DROPPED` | line-rate de `coverage/lcov.info` caiu | ❌ REJEITA |
| `PHANTOM_FIX` | tarefa `--task fix`: teste mudou mas o código sob teste **não** | ❌ REJEITA |
| `EXPECTED_VALUE_CHANGED` | valor esperado trocado (bater com saída errada?) | ⚠️ OLHO HUMANO |

Exit: **0** limpo · **1** precisa olho humano · **2** REJEITA. Qualquer REJEITA → o trabalho
volta para correção **e** gera-se uma lição (Parte E).

## Como o Juiz corre (ordem obrigatória)

```bash
# 0) CHÃO anti-trapaça — SEMPRE primeiro, o Juiz não pode pular o próprio anti-trapaça
python .claude/juiz/anti_trapaca.py --base <merge-base> [--task fix] [--json]
#    exit 2 → PARA aqui, REJEITA, gera lição.

# CAMADA 2 (3): zona protegida no diff?
python .claude/juiz/zonas_diff.py --base <merge-base> [--json]

# CAMADA 1: TestSprite via MCP (o agente orquestra) — classifica falhas.
# CAMADA 2 (1)(2): flutter analyze  &&  flutter test
# CAMADA 2 (4): ler business_rules relevantes do Cérebro e conferir a mudança.
# CAMADA 3: rubrica UI (checklist abaixo) para mudanças Flutter.

# Se REJEITAR em qualquer ponto → gerar lição:
python .claude/juiz/reflexao.py --tentei "..." --falhou "..." --certo "..." --codigo <CODE>
#    entregar o handoff ao agente `bibliotecario-cerebro`.
```

`--base` default = `git merge-base main HEAD`. `--head` default = working tree (não commitado),
para poder julgar antes do commit.

## Rubrica de UI (Camada 3) — mudança Flutter

Marca cada eixo ✅/⚠️/❌. Um ❌ → REJEITA; ⚠️ → olho humano.

- **Funcional** — o ecrã faz o que a tarefa pediu? Estados vazio/erro/loading cobertos?
- **Visual** — design system Bora: Verde `#16A34A` (primário) + Laranja `#F97316` (**1 laranja/ecrã**),
  fonte Inter. **NUNCA** alterou foto real de produto/restaurante (regra dura do `agent-memory.md`).
- **Layout** — sem overflow, respeita `SafeArea`, responsivo, `BoraScreenAppBar` onde é o padrão.
- **UX** — feedback ao toque, sem beco sem saída, PT-PT no app / PT-BR no admin.

> A regra "1 laranja/ecrã" e as fotos reais também têm skills dedicadas (`audit-orange-rule`),
> que o Juiz pode invocar como evidência.

## Braços do Juiz (Parte D — absorvidos da Fase 3)

- **`e2e-test-builder`** = braço de **GERAÇÃO** de teste. Cria testes para features novas
  (`integration_test/`), que o TestSprite (Camada 1) depois corre. O Juiz chama-o quando falta
  cobertura para julgar.
- **`checkout-fixer`** = **fixer especializado** que o Juiz invoca em **regressão de checkout**
  (cliente → pagamento → ordem). Diagnostica e propõe patch; o resultado volta ao Juiz para as 3
  camadas. Nota: checkout toca dinheiro → `checkout-fixer` propõe, a Trava/Lista Vermelha decide.

## Ficheiros
- `anti_trapaca.py` — chão determinístico (Parte C). **Corre primeiro, sempre.**
- `zonas_diff.py` — Camada 2 (3): diff × zonas protegidas.
- `reflexao.py` — Parte E: gera o handoff de lição → `bibliotecario-cerebro`.
- `_test_fixtures/` — fixtures descartáveis para o auto-teste do Juiz (Parte H).
