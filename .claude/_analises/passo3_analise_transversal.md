# Passo 3 — Análise transversal das 42 skills

> ⚠️ Draft parcial — as instruções do Passo 3 no prompt do user foram truncadas em "Info que devia estar em busi...".
> Este ficheiro cobre os dois tópicos já enunciados + temas transversais óbvios detectados nos dados agregados.
> Pronto para expansão assim que chegar a versão completa do Passo 3 (e Passos 4-6).

---

## 1. Padrões de problemas que se repetem em várias skills

### 1.1 🔴 Ausência universal de benchmarks Uber/iFood/Glovo (42/42)

**Todas as skills sem excepção** têm zero menções directas a Uber, iFood ou Glovo. O sistema foi desenhado em isolamento, o que deixa as decisões de arquitectura sem régua externa. Para pôr a skill no patamar Uber/iFood/Glovo, é preciso que **cada skill de domínio (Camada 5) e de controle (Camada 2) tenha uma secção `BENCHMARK`** explícita a comparar a abordagem Bora com o que essas plataformas fazem.

### 1.2 🔴 Zero exemplos worked (40/42)

Só **2** skills mencionam "exemplo" ou "cenário": auto_orchestrator/flow, prompt_engine/generator.
Skills sem exemplos concretos são difíceis de orquestrar por agentes e de auditar por humanos. O modelo correcto é:
```
Input:  <prompt ou contexto real>
Output esperado: <decisão, checklist, ou diff>
Failure mode: <como detectar que a skill falhou>
```

### 1.3 🔴 Baixa ancoragem no código real (35/42 skills sem ref lib/supabase)

A maioria das skills é **abstracta**. Ex: `realtime_engine/rules` não aponta para `lib/stores/order_store.dart` nem para a tabela `orders` do Supabase; `map_master` não nomeia `lib/services/location_service.dart` nem `lib/utils/map_utils.dart`. Skills só funcionam bem quando se referem a caminhos reais — caso contrário, cada invocação tem de redescobrir o código do zero.

**Skills mais urgentes de ancorar:**
- `fix_realtime` → deveria referenciar ficheiros específicos do domínio
- `dispatch_bugfix` → deveria referenciar ficheiros específicos do domínio
- `realtime_engine/rules` → deveria referenciar ficheiros específicos do domínio
- `realtime_engine/sync` → deveria referenciar ficheiros específicos do domínio
- `realtime_engine/debug` → deveria referenciar ficheiros específicos do domínio
- `dispatch_manager` → deveria referenciar ficheiros específicos do domínio
- `payment_manager` → deveria referenciar ficheiros específicos do domínio
- `token_manager` → deveria referenciar ficheiros específicos do domínio

### 1.4 🟠 Modo Protecção inconsistente (36/42 skills sem menção)

Só **6** skills mencionam algum conceito de protecção (read-only, approved_by, destructive flag). A arquitectura v2 ordena `decision_engine → guardian → executor`, mas essa cadeia não está internalizada nas skills individuais. Cada skill deveria **declarar explicitamente** se é read-only, read-write com approval, ou execute-after-chain.

### 1.5 🟠 Placeholders por preencher em 8 skills

- `refactor_guard` → 1 placeholder(s)
- `realtime_engine/rules` → 1 placeholder(s)
- `map_master` → 1 placeholder(s)
- `dispatch_manager` → 1 placeholder(s)
- `payment_manager` → 1 placeholder(s)
- `token_manager` → 1 placeholder(s)
- `prompt_engine/rules` → 5 placeholder(s)
- `(plugin) ceo-ai/SKILL` → 1 placeholder(s)

### 1.6 🟡 Skills demasiado curtas (<60 linhas): 0

_(todas acima de 60 linhas)_

### 1.7 🟡 Sem FRONTEIRAS (6) / Sem NÃO PODE FAZER (6)

FRONTEIRAS e NÃO PODE FAZER são o mecanismo que impede overlap entre skills. Skills que faltam estas secções:
- **Sem FRONTEIRAS:** (root) manager, (root) tester, (root) auto_debug, (root) auto_runner, (root) memory/memory_store, (plugin) ceo-ai/SKILL
- **Sem NÃO PODE FAZER:** (root) manager, (root) tester, (root) auto_debug, (root) auto_runner, (root) memory/memory_store, (plugin) ceo-ai/SKILL

### 1.8 🟡 Sem versão no frontmatter: 2

- `(root) memory/memory_store`
- `(plugin) ceo-ai/SKILL`

### 1.9 🟠 Inconsistência legacy — `manager.md` contradiz arquitectura v2

`(root) manager.md` ainda referencia `auto_debug`, `tester` como skills-alvo, mas `auto_orchestrator/rules` marca ambas como **não-existentes** e proíbe referenciá-las. O `manager.md` é legacy que precisa ser ou **alinhado com v2** ou **formalmente marcado como obsoleto**.

### 1.10 🟡 Skill fora do sistema principal: `(plugin) ceo-ai/SKILL`

Vive em `.claude/skills/ceo-ai/` (plugin-style), **não** em `.claude/.ai/skills/`. Tem 263 linhas mas zero frontmatter `version:` e zero integração com a cadeia canónica (`decision_engine → guardian → executor`). Decidir: integrar na arquitectura v2 OU documentar como ferramenta externa separada.

---

## 2. Info que devia estar em `business_rules.md` (e não está) / Info duplicada entre BR e skills

_(Tópico enunciado mas instruções truncadas — draft baseado em comparação entre BR e conteúdo das skills)_

### 2.1 Informação CRÍTICA que devia estar em BR e ainda não está

Comparando a BR (270 linhas) com os números citados em skills:

| Regra / constante | Onde está hoje | Onde devia estar |
|---|---|---|
| Timeout de oferta dispatch (10s) | `dispatch_engine.dart` | BR secção DISPATCH — "offer timeout" não aparece nos 269 LoC da BR |
| Raio batching 800m (para parceiros distintos) | `driver_capacity_service.dart` | BR fala em 15km para batching de clientes, mas os 800m de batching driver→driver não está |
| Delivery code (4 dígitos, validado antes de `onTheWay→delivered`) | só `system_validator.md` e `validation_report_v1.md` | BR secção ESTADOS — ausente da fonte de verdade |
| Intervalo fallback `refresh()` (3s Timer.periodic) | `order_store.dart` | BR ou `realtime_engine/rules` — documentar política de fallback |
| Animação driver location (12 steps × 80ms) | `driver_location_service.dart` | BR ou `map_master` — política de interpolação |
| Stripe publishable key guard (kIsWeb) | `payment_service.dart` + CLAUDE.md | BR secção PAGAMENTO — restrições de plataforma |
| Markup invisível +15% — onde se aplica exactamente (antes ou depois de taxas?) | `payment_manager.md` parcial | BR deveria ter exemplo numérico worked |
| Driver Help — 1 ajudante por quê? 4€ dividido como? | BR diz apenas "interno, 1 ajudante" | Falta breakdown: cliente paga, plataforma paga, driver principal paga? |

### 2.2 Números duplicados entre BR e skills (risco de drift)

Constantes que aparecem literal nas skills além da BR — se BR mudar, as skills ficam stale:
- **TOKEN_MAX_DISCOUNT_RATIO = 0.50** → aparece em `token_manager`, `decision_registry`, `system_validator`, `product_analyst`. ✅ Hoje todos a 50%. Mas quatro cópias = 4 sítios para manter em sync.
- **FIFO 200m / dwell 5s** → `dispatch_manager`, `decision_registry`. Duas cópias.
- **SLA 10min / +5min extensão** → `dispatch_manager`, `decision_registry`.
- **Markup 15%** → `payment_manager`, `decision_registry`.

**Recomendação:** adoptar **BR como fonte única**; skills devem **referenciar com link** (ex: "ver BR §TOKENS, regra #18") em vez de copiar o valor. Único lugar com valor literal = BR.

### 2.3 Regras que existem nas skills mas não na BR

- `guardian` define checklist técnico (null safety, streams, dispose, GPS) → isto é **política de engenharia**, não regra de negócio. **Não** mover para BR.
- `state_validator` define a sequência de estados → BR já tem. ✅
- `payment_manager` define "ZERO movimento Stripe para Driver Help" → **devia estar na BR §DRIVER HELP** como constraint explícito.
- `dispatch_manager` define fórmula `combinedTime < individual × 1.20` → BR tem, ✅.
- `token_manager` define cashback 3% → BR tem "~3%", skill assume exacto 3%. **BR deveria remover o "~" ou skill deveria ter range.**

---

## 3. Consistência de versioning e "metabolismo" do sistema

- Skills v2.x: **26**
- Skills v1.x: **14**
- Skills sem versão: **2**

Inconsistência: algumas skills (ex: `rules` v2.0.0, `manager` v2.0.0) estão em v2 mas o `manager` contém referências legacy. Recomendar: **versão = geração da arquitectura**, não versão do ficheiro. Se a arquitectura é v2, todas as skills alinhadas deveriam estar em v2.0.0 mínimo.

---

## 4. Riscos sistémicos cruzados (cross-layer)

### 4.1 Camada 3 (Execução) vs Camada 4 (Processamento)

`executor` exige `approved_by: [decision_engine, guardian]` — mas `dispatch_bugfix`, `fix_realtime`, `fix_auth` (Camada 4) não documentam que **retornam para `executor`** para aplicar o fix. Ambíguo: elas mesmas fazem Edit, ou só propõem?

### 4.2 Camada 5 (Domínio) escreve DB? Ou delega a Camada 6?

`payment_manager`, `token_manager`, `dispatch_manager` implementam regras de negócio com estado em Supabase, mas a sua relação com `supabase_agent`/`supabase_engine` (Camada 6) não está formalizada. **Devia haver regra explícita:** Camada 5 **nunca executa SQL**; delega sempre a Camada 6 via `supabase_engine`.

### 4.3 `auto_orchestrator/decision` vs `decision_engine`

Nome colide. `auto_orchestrator/decision` é um mapeamento de chains (routing table). `decision_engine` é avaliação de risco. O relatório de validação v1 já marcou isto como ✅ sem overlap, mas o **naming** ainda é confuso. Considerar renomear `auto_orchestrator/decision.md` → `auto_orchestrator/routing.md`.

---

## 5. Síntese — onde está o "salto Uber/iFood/Glovo"

O sistema Bora já tem:
- ✅ Cadeia canónica de gates (decision → guardian → executor → system_validator → memory)
- ✅ Separação de responsabilidades por camada
- ✅ FRONTEIRAS + NÃO PODE FAZER em 36/42 skills
- ✅ Cobertura de 100% das regras críticas da BR

O que **falta** para ficar ao nível das grandes plataformas:
1. **Exemplos worked em todas as skills** (padrão Uber: every runbook has a walk-through)
2. **Ancoragem explícita no código** (ficheiros + linhas)
3. **Benchmarks externos** (como é que X faz isto → como é que Bora faz)
4. **Protection mode declarado por skill** (read-only? requires approval? destructive?)
5. **BR como fonte única** (remover cópias literais de constantes nas skills)
6. **Política de sync entre BR e skills** (quando BR muda, auditoria automática das skills que referenciam)

---

## 6. Próximos passos sugeridos (para Passos 4-6 do plano)

As instruções para Passos 4-6 não chegaram ao meu contexto (o prompt terminou em PASSO 3). Baseado na estrutura típica e no conteúdo do Passo 3, provavelmente são:

- **Passo 4 — Plano priorizado de melhorias** (quick wins vs estruturais, ordenado)
- **Passo 5 — Estimativa agregada** (esforço total, riscos de rollout)
- **Passo 6 — Proposta de roadmap de execução** (ordem, dependências, gates)

**Aguardando instruções completas para prosseguir.** Enquanto isso, todos os dados brutos estão em `_skill_profiles.json` e `_skill_sections.json` — qualquer passo subsequente pode ser executado sem re-leitura das skills.
