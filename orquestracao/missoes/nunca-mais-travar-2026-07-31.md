--- missao ---
id: nunca-mais-travar-2026-07-31
tipo: missao
cor: ⚫ Mission (arquiva ao concluir — loops.md)
estado: em_curso
autor: claude-code (Opus) via CEO-AI
criada: 2026-07-31
dono: maestro-autonomia
zona: verde
--- fim ---

# 🛑 Missão: Nunca Mais Travar

## Objetivo declarado pelo Danilo (critério de sucesso)
Modo automático total. Ele deixa de mandar prompt pelo Claude Code — pede à Claude.ai e o
sistema resolve. Nada pode travar, exceto zona vermelha, que notifica e espera. Quando ele
aprovar — a qualquer hora — o sistema executa sozinho.

## Invariantes (verdadeiros no fim)
| # | Invariante | Veredito |
|---|---|---|
| I1 | Nenhum achado repetido gera linha nova. Achado que persiste = mesma linha, atualizada. | ✅ PROVADO (32→1 linha) |
| I2 | Nenhuma ordem do aprovador-vermelho excede o que o executor aguenta numa corrida. | ✅ PROVADO (fila 30 → lote 8) |
| I3 | Item já triado nunca reabre o fallback. | ✅ PROVADO AO VIVO (`oldest_age=0min`) |
| I4 | `travada` não-vermelha nunca notifica o Danilo — auto-continua ou auto-arquiva. | ✅ PROVADO EM PRODUÇÃO (travada real via `mv` atómico; arquivo escrito, zero Telegram) |
| I5 | Zona vermelha notifica 1x e espera; aprovação → execução automática, sem prompt. | ✅ PROVADO PONTA-A-PONTA (item → `aplicada` sozinho) |

> **Relatório de fecho:** `.claude/.ai/reports/FECHO-nunca-mais-travar-2026-08-01.md`
> **Por fazer (sem arredondar):** ligar a Trava de segredos no `settings.json` (guard pronto e
> testado, permissão negou a edição) · corrigir o transporte do `pc-judge` (causa-raiz do juiz
> mudo: prompt por cmd.exe em vez de `--b64stdin`) · prova comparativa da Parte 2 da paridade ·
> re-triagem das 49 aprovações em quarentena.

## Causa-raiz (provada pela Claude.ai 2026-07-31 — confirmar, não re-investigar)
1. Dedup do Robot B furado → `dedup_key` ganha sufixo `-vN` → 36/25/23 versões da mesma linha.
2. Balde B (dinheiro) fica legitimamente `nova` — indistinguível de "ainda não triado".
3. `red_queue_watermark()` media `oldest_age_min` sobre TODOS os `nova` → fallback 30min eterno.
4. Ordem do fallback manda triar a fila toda → 30 itens → `SAIDA-VAZIA` → `travada` → Telegram.

Já aplicado pela Claude.ai via MCP (verificar, não repetir): fila triada 30→2; migration
`red_queue_watermark_oldest_age_only_untriaged`; os 2 Balde B com `reviewed_at` preenchido.

## 🔨 DECISÃO DO DANILO (2026-07-31) — vinculativa

**(c) — normaliza só as `nova`, não toca em nenhuma `aprovada`.**

> Motivo: as `aprovada` são autorizações do Danilo e o caminho de execução está partido — não
> se sabe o que ainda vai correr. Fundir agora apagaria trabalho autorizado.
>
> **Ajuste de prioridade (confirmado no banco pelo Danilo):** 46 linhas `aprovada` (mais antiga
> **19/06**) e o último `aplicada` é de **2026-07-14**. **Nada aprovado é executado há mais de
> 2 semanas.** As 5 aprovações que o Danilo fez hoje caíram na mesma pilha morta. Logo:
> 1. Terminar a Parte 1 (lotes ≤8 + `reviewed_at` + normalizar só as `nova`).
> 2. **SALTAR a Parte 2 da paridade** e ir direto ao **P3**: mapear e consertar `aprovada` →
>    execução. Prova com um item real aprovado a correr sozinho.
> 3. Só depois voltar à Parte 2 (tetos viram continuação + Juiz deixa de matar).
>
> **Deriva de sinónimos — não resolver com regex de sinónimos.** Atacar na origem: o
> `robot-b/index.ts:243` não deve entregar ao Gemini a lista de chaves ocupadas pedindo para não
> repetir. Deve pedir-lhe para escolher de um **conjunto FECHADO de chaves canónicas por
> categoria** e, se o achado não couber em nenhuma, devolver **"sem chave"** em vez de inventar.

## Partes (uma de cada vez, ~15 min cada — o hook-de-conclusão encadeia)

| # | Parte | Estado |
|---|---|---|
| 1 | Matar a enchente na origem (dedup, backfill, `reviewed_at` ao triar, lotes ≤8) | ✅ FECHADA — I1+I2+I3 provados |
| 3 | **`aprovada` → execução** — promovida a mais crítica das 2 missões | 🟡 CONSTRUÍDO e provado até à injeção da ordem; troço final bloqueado (ver abaixo) |

> **🔴 BLOQUEADOR ÚNICO (2026-07-31):** a **CLI do Claude Code não está instalada no PC**.
> `run-claude-loop.cmd:42` aponta para `…AppData\Roaming\npm\…\claude-code\bin\claude.exe`, que
> já não existe (migração para instalador nativo); a linha 53 aborta com `exit /b 4` **antes de
> emitir um byte**. Daí o `SAIDA-VAZIA` genérico — o parser nem chega ao `type:result`, por isso
> nem a FASE 1.10 o cobre (ela trata "parou a meio", não "nunca arrancou"). Provado: ponte
> VPS→PC viva (`PONTE-VIVA`) mas `pc-loop` devolve `[loop] ERRO: claude.exe nao encontrado`.
> Explica também o `JUIZ-SEM-VEREDITO` em série (o juiz corre pela mesma CLI).
> **Ação humana:** reinstalar a CLI + trocar o caminho hardcoded por `where claude` (dinâmico),
> senão a próxima migração de instalador volta a partir o loop em silêncio.
| 2 | O fallback e o travamento (cooldown ≠ gatilho, hook vivo na VPS, I4) | pendente (depois do P3) |

> **P3 mapeado (2026-07-31):** não está partido — **nunca foi construído**. Todos os leitores de
> `status='aprovada'` são escrita (`robot_approve_plan`), dedup ou métrica (`taxa_aprovacao_pct`).
> **Zero consumidores de execução**; nenhum cron faz poll de aprovados. Aprovar escreve num estado
> que ninguém lê. Construir: RPC `approved_queue_watermark()` → cron */10 → ordem com lote ≤8
> (mesma plumbing do `red_queue_watermark`, já provada) → maestro → `aplicada`.

### PARTE 1 — matar a enchente na origem  `aberta` (diagnóstico feito, fix travado por decisão)
> Relatório: `.claude/.ai/reports/paridade-e-enchente-2026-07-31.md`
> **Correção ao briefing:** a RPC `robot_create_suggestion` deduplica CORRETAMENTE. Quem inventa
> o `-vN` é o **Gemini** — `robot-b/index.ts:243` entrega-lhe as chaves ocupadas com "NÃO repetir",
> e ele cumpre à letra inventando chave nova. **Segunda fuga, maior:** deriva de sinónimos
> (7 chaves vivas para "queries lentas de cron"). Normalizar `-vN` fecha só metade de I1.
> **Bloqueio:** o backfill colide — `infra:http-timeouts-recorrentes-geral` tem 4 linhas vivas
> **`aprovada`**. Fundir às cegas apagaria aprovações do Danilo. Ver "Decisão" no relatório.
1. Eliminar a lógica que acrescenta `-vN`; atualizar a linha viva em vez de inserir.
2. Backfill do `dedup_key` das linhas **vivas** para a forma base (não apagar histórico).
3. `aprovador-vermelho` preenche `reviewed_at` sempre que tria (inclusive Balde B).
4. `hermes-aprovador-vermelho.sh` monta ordem com **máx. 8 itens** (mais antigos primeiro).
- **Prova exigida:** fixture 30+ itens → (a) zero linha duplicada, (b) ordem ≤8, (c) sem `SAIDA-VAZIA`.

### PARTE 2 — o fallback e o travamento  `pendente`
1. Separar `STALE_MIN` (gatilho) do cooldown do `STATE_FORCE` (dedupe por assinatura, como Watchdog v3).
2. Verificar AO VIVO que `hermes-hook-conclusao.sh` está ligado no ponto de veredito do
   `carteiro.sh` em produção (VPS) — atenção à divergência VPS vs repo.
3. `travada` não-vermelha sem continuações → lista de arquivo revista no daily-pulse, **zero Telegram**.
- **Prova exigida:** `travada` real não-vermelha (ficheiro criado já no teto via `mv` atómico) →
  continuação criada, zero Telegram.

### PARTE 3 — o caminho da aprovação (painel admin)  `pendente`
> REGRA PAINEL ADMIN: tudo o que muda tem correspondência no painel, autoridade total do Danilo.
1. `AdminRobotSuggestionsScreen`: estado real de triagem (triado/não, Balde A/B), Aprovar/Rejeitar
   por item e em lote. PT-BR.
2. Confirmar/corrigir o bug de scroll dessa tela (reportado 2026-07-22).
3. Fechar I5: `nova` → `aprovada` dispara execução sozinha (gatilho por watermark de `aprovada`).
- **Prova exigida:** item real aprovado a ser executado sem intervenção.

## Regras
- Zona **verde** em tudo. Não tocar em pricing, wallet, tokens, comissões, Stripe, dispatch de dinheiro.
- Antes de commit/push: verificar o que viaja junto (boleia do `paths-ignore`).
- Nunca confiar na palavra do executor: cada invariante prova-se com `SELECT` ou ficheiro/log real.
- Relatório final em ficheiro, uma secção por invariante I1–I5.

## Registo de execução
- 2026-07-31 — missão criada; Parte 1 iniciada.
