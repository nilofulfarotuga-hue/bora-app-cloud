# C2 — o que falta: 12 linhas no `.claude/settings.json` (ato humano)

> 2026-07-20 · A Trava (`protege-dinheiro.sh:55`) bloqueia o agente de editar
> `.claude/settings.json`. Por desenho. Esta é a parte que o Danilo cola à mão.

## 1. Cola isto no `.claude/settings.json`

O ficheiro já tem um bloco `"hooks"` com `PreToolUse`. **Acrescenta a chave
`SessionStart` DENTRO do `"hooks"` que já existe** (não cries um segundo `"hooks"`):

```json
"SessionStart": [
  {
    "matcher": "startup|resume|compact",
    "hooks": [
      {
        "type": "command",
        "command": "bash /c/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/knowledge/_tools/injeta-digest.sh"
      }
    ]
  }
]
```

Fica com esta forma:

```json
{
  "hooks": {
    "PreToolUse": [ ...o que já lá está, intocado... ],
    "SessionStart": [ ...o bloco acima... ]
  }
}
```

## 2. Porque é que o script não vive em `.claude/hooks/`

A Trava protege `.claude/hooks/**` inteiro. O injetor é zona 🟢 verde (só lê um
ficheiro e imprime JSON), por isso vive ao lado do consolidador que o alimenta:
`.claude/.ai/knowledge/_tools/injeta-digest.sh`. O `settings.json` aponta para lá.

## 3. Já testado (antes de te pedir seja o que for)

| Cenário | Resultado |
|---|---|
| Digest presente | JSON válido, `additionalContext` = 9.470 B, canário `fe8e8508` |
| Digest **ausente** | `rc=0`, zero bytes → sessão arranca na mesma ✅ |
| Digest **vazio** | `rc=0`, zero bytes → sessão arranca na mesma ✅ |
| Sem Python utilizável | `rc=0`, zero bytes (fail-open) |
| Saída não-JSON | descartada, `rc=0` (fail-open) |
| CR bytes no `.sh` | 0 (regra `*.sh eol=lf`) |

Três armadilhas do Windows apanhadas a construir isto (todas comentadas no código):
1. `command -v python3` devolve o **stub da Microsoft Store** — não basta encontrar
   o interpretador, é preciso provar que corre.
2. `stdout` nasce **cp1252** e rebenta em qualquer `→`/acento vindo do digest.
   Resolvido com `reconfigure(utf-8)` + `ensure_ascii=True` (JSON puro ASCII).
3. O próprio log tinha de ser best-effort, senão o erro dele vazava para o stderr do hook.

## 4. A prova que corro assim que colares (não antes)

1. Crio uma ordem real na fila (`cortex_nova_ordem`), tarefa:
   *"Responde APENAS com o valor após DIGEST-BORA-OK no teu contexto. Se não
   existir, responde SEM-DIGEST. Não uses ferramentas."*
2. Deixo o `carteiro.sh` pegá-la pelo caminho normal (VPS → `pc-loop` →
   `run-claude-loop.cmd` → `claude -p`). **Nenhum desses ficheiros foi tocado.**
3. Provas que te mostro:
   - a saída da ordem == `fe8e8508` (canário derivado do conteúdo do digest);
   - a linha `OK bytes=... source=...` em `inbox/_reports/injecao-digest.log`
     com carimbo temporal a bater com a execução da ordem;
   - o `bora-live.log` a mostrar a ordem a correr nessa janela.

O canário é um sha256 do digest: só pode aparecer na resposta se o bloco tiver
mesmo chegado ao modelo. Não é o modelo a dizer "sim, li" — é uma prova verificável.

## 5. Se a prova falhar

Se o `claude -p` não disparar o `SessionStart`, o C2 morre nesta forma e o plano B
passa a ser injetar via `run-claude-loop.cmd` (prefixar o TASKFILE com o digest) —
mas isso mexe na esteira que funciona, e só lá vou com autorização tua.
