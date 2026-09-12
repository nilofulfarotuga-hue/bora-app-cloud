---
id: pre-flight-multiagent
title: Checklist Pré-Voo Multiagente
zona: vermelha
tipo: security/procedural
atualizado: 2026-08-09
---

# Checklist Pré-Voo Multiagente

> **Correr antes de qualquer execução multiagente do Cortex** (fase a fase, ou antes de uma missão que envolva workers em paralelo/routing/fallback). Lei do Pré-Voo: **simular antes de agir**. Nada desta lista altera nada — só lê e valida. Se um item falhar, **PARA** e resolve antes de avançar.

## 1. Ambiente — Trava ativa
- [ ] `CORTEX_WRITE_ENABLED=false` (dial cauteloso; o cortex-mcp recusa escritas diretas sem dial).
- [ ] `permissions.deny` em `bora_app/.claude/settings.json` presente e completo (ver [[red-model]]).
- [ ] `permissions.deny` em `~/.claude/settings.json` **espelha** o do projeto (gap histórico).
- [ ] Hooks `protege-dinheiro.sh` e `protege-banco.sh` presentes e executáveis (`ls -la .claude/hooks/`).
- [ ] `RED_MODEL.md` é o único source-of-truth; sem drift vs settings/hooks/server.mjs.

## 2. Kill switch
- [ ] `robot_b_enabled` (Supabase `platform_settings`) = estado pretendido. Se **false**, nenhum runtime autónomo corre — confirmar intenção.
- [ ] Feature flags da fase ativa (`USE_BUS`, `CORTEX_ROUTER_ENABLED`, `CORTEX_FALLBACK_ENABLED`, `MAX_PARALLEL_WORKERS`, `USE_WORKTREES`, `OBSERVABILITY_ENABLED`) = valor documentado da fase; **default false** em prod.

## 3. Branch e backups
- [ ] Branch `autonomous-night/fase<N>-<slug>` ativa (`git -C bora_app branch --show-current`).
- [ ] Backup `.claude/_backups/<fase>/<ts>/` criado para ficheiros que vão ser alterados (settings, hooks, server.mjs, juiz).
- [ ] `git status` limpo (sem mudanças não-commitadas que se possam perder com worktree/merge).

## 4. BD — sem $ tocados
- [ ] Nenhuma migração da fase toca tabelas da [[red-model]] §4 (`FINTABLE`).
- [ ] Migrações têm `DOWN` (DROP ... CASCADE).
- [ ] RPCs novas são `SECURITY DEFINER` e `REVOKE ... FROM public/anon` (padrão `robot_*`/`autonomy_*`).

## 5. Workers e isolamento (F6+)
- [ ] `MAX_PARALLEL_WORKERS` respeitado (default 3).
- [ ] Worktrees terão `settings.local.json` com o mesmo deny que o pai (herança da Trava).
- [ ] `executor-lock` é por worktree, não global, quando paralelismo ativo.

## 6. Modelos e autoridade (F3+)
- [ ] `authority_level='critical'` → Opus 5 obrigatório; indisponível → **PAUSA + humano** (nunca fallback auto).
- [ ] `authority_level='normal'` indisponível → GLM 5.1 auto-procede **só se** `CORTEX_FALLBACK_ENABLED=true`, com log em `llm_call_log`.
- [ ] Nenhuma tarefa `$` é auto-executada (`RED_ORDER` no cortex-mcp manda propor).

## 7. Consenso e Guardian (F5+)
- [ ] Tarefas com `requires_consensus=true` têm `voting_deadline` e `required_voters`.
- [ ] Guardian escuta `escalate`/consenso rejeitado → alerta maestro.
- [ ] Nenhuma acção do Executor corre sem Critic+Consensus+Guardian (para `requires_*=true`).

## 8. Observabilidade (F7+)
- [ ] `llm_call_log` ativo e gravando todas as chamadas routed.
- [ ] `agent_events` ativo; eventos de `fallback`/`panic` (critical) alertam maestro.
- [ ] Custo acumulado do dia < budget definido (default <$10/dia).

## 9. Decisão humana
- [ ] Danilo ciente da fase que vai correr e do kill switch para parar.
- [ ] Condição de rollback definida (branch + DOWN migration + flag off).
- [ ] Após a fase: auditoria ([[*criterios-porta*]]) antes de avançar para a próxima.

---

## Critérios de porta (pós-fase)
Após cada fase, tudo verde antes de avançar:
1. Auditoria manual (Danilo): Trava intacta, sem `$` tocados, logs limpos.
2. `pytest scripts/e2e/test_phase<N>_*.py` verde.
3. Maestro flow `.maestro/flows/fase<N>_*` verde.
4. `anti_trapaca.py` exit 0 na fixture da fase.
5. `skills-doctor` sem erros.
6. `git status` limpo na branch da fase.
7. Kill switch test: `robot_b_enabled=false` → nada corre.
8. **Assinatura humana** → merge e próxima fase.

---

*Pré-voo não é burocracia — é o que impede que um agente com erro destrua BD/git/dinheiro. Anda-se uma fase de cada vez, testa-se, assina-se.*