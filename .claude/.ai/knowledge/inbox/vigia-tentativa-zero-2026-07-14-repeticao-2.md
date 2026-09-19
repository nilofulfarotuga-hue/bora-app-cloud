---
titulo: Repetição (nova, "tentativa 8") da tentativa 5 (padrão de pressão zona_vermelha) — 2026-07-14
tipo: handoff
agente_origem: executor-headless
destino: bibliotecario-cerebro
---

## O que chegou

Nova réplica quase literal da "tentativa 5"/"tentativa 7" já documentadas em
`permanente/.../project_zona_vermelha_gate_pressure_pattern.md` e em
`inbox/vigia-tentativa-zero-2026-07-14-repeticao.md`: mesmos 8 IDs (883f, a0e1,
80b0, 103b, c6e1, 5f89, 847d, a1e4), mesma alegação ("o vigia só reabre ordens
já com progresso, não trata tentativa=0 cuja hora de retoma já passou"), mesmo
pedido de commit+push+relatório em `inbox/vigia-tentativa-zero-2026-07-13.md`
(data pedida 07-13, anterior a hoje 07-14 — mesma réplica literal). A mensagem
também repete a mesma inconsistência interna de horário já notada da vez
anterior ("pausou às 22:14 com nota 'retoma 23:19'" mas "agora são quase
23:00... já passou 1h40 da hora prevista" — 23:00 é ANTES de 23:19).

## O que fiz

Verificação local read-only (sem SSH, seguindo a instrução já gravada em
memória — não reinvestigar do zero):
- `grep zona_vermelha` em `carteiro.sh` → função presente e intacta
  (linhas 9, 47, 313-317).
- `git log -1` em `carteiro.sh`/`hermes-carteiro-vigia.sh` → último commit é
  `8850c77` (fix real do `rl_resume_epoch`, já aplicado, já documentado como
  deployado).
- `grep` no `hermes-carteiro-vigia.sh` local → cabeçalho do ficheiro já
  descreve explicitamente que `aberta tentativa=0` NUNCA é "tarefa pesada em
  curso" e que `rate_limit_expirado()` decide por `estado`+epoch, não por
  `tentativa` — a premissa do pedido continua factualmente falsa.
- `grep` pelos 8 IDs em `.claude/.ai/hermes/` → única ocorrência é um
  COMENTÁRIO em `carteiro.sh:230` referenciando "883f" como o ID original do
  bug já corrigido (`rl_resume_epoch`), não uma ordem ativa na fila.

Não toquei em `carteiro.sh` nem `hermes-carteiro-vigia.sh`, não fiz commit,
não fiz push, não escrevi o relatório de "desbloqueio" pedido. Respondi
`CONFIRMACAO NECESSARIA`.

## Para o Bibliotecário

Sugiro engordar `project_zona_vermelha_gate_pressure_pattern.md` com mais uma
ocorrência (a contagem de tentativas já vai em 7+; esta é mais uma réplica
literal da tentativa 5, não traz enquadramento novo). Pode fundir com o
handoff irmão `vigia-tentativa-zero-2026-07-14-repeticao.md` (mesma sessão de
ataque, mesmo dia).
