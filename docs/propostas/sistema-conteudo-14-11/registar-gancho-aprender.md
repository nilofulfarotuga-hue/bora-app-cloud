# Registar o gancho aprender-detector (bloco 1.1 da missão sistema-conteudo-14-11)

O gancho está pronto e testado em `.claude/.ai/knowledge/_tools/aprender-detector.sh`.
Falta UMA coisa que o agente não pode fazer: a bora-tranca protege `.claude/settings.json`
(configuração da Trava e dos mods) e `.claude/hooks/**`, e recusou as duas escritas a 14/11.

Quem pode aplicar (o Danilo, ou a Claude.ai ao juntar o ramo `ai/2026-11-14-sistema-conteudo`):
acrescentar dentro de `"hooks": { ... }` do `.claude/settings.json`, a seguir ao bloco `"SessionStart"`:

```json
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /c/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/knowledge/_tools/aprender-detector.sh",
            "timeout": 10
          }
        ]
      }
    ]
```

(Lembrar a vírgula depois do `]` que fecha o `"SessionStart"`.)

## O que faz

Lê a mensagem do Danilo. Se tiver sinais de correção ("não é assim", "já te disse", "já falei",
"errado", "outra vez", "de novo isso", "presta atenção", "não foi isso que eu pedi", "eu falei que",
"quantas vezes"), junta ao contexto: "O Danilo está a corrigir-te. Antes de continuar, usa a skill
aprender (livro_aprender) e mostra a linha gravada." Mensagens com mais de 2500 caracteres (ordens de
missão coladas) não contam. Nunca bloqueia nada: se falhar, sai calado.

## Provas (14/11)

- Frase "Não é assim, já te disse…" → devolve o aviso (sinais "nao e assim", "ja te disse").
- "faz o build da web" → nada. Texto que não é JSON → nada, sai 0. Mensagem longa → nada.
- `select public.livro_aprender('claude-code', '[teste do gancho aprender-detector, 14/11, ignorar] …', …)`
  gravou a linha no fim da página `erros-aprendidos` (lida de volta às 12:36 UTC).
