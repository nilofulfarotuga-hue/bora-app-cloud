---
name: juiz-dsh
description: "Como o Dipsy (dsh) faz commits: todo o commit passa pelo Juiz anti-trapaça do repo antes de existir, através do script dsh-commit.ps1, e é recusado se o Juiz falhar. Nunca git commit à mão, nunca git push. Usar sempre que o Dipsy tiver de gravar trabalho no git, ou quando o Danilo pedir para guardar, commitar ou juntar mudanças."
---

# Juiz antes de cada commit do Dipsy

O Dipsy não tem a tranca do Claude Code. A guarda dele barra `git commit` à mão e `git push`. O único caminho é este
script, que corre o Juiz do repo (`.claude/juiz/anti_trapaca.py` e `zonas_diff.py`) **antes** de o commit existir:

```
powershell -NoProfile -File C:\Users\danil\.dsh\dsh-commit.ps1 -Mensagem "tipo: o que mudou" -Caminhos ficheiro1,ficheiro2 [-Repo <pasta>] [-Tarefa feature|fix]
```

## O que ele faz
1. Recusa mensagens curtas, caminhos com asteriscos, `.` ou fora do repo, e qualquer segredo (`.env`, chaves, `secrets`).
2. Monta um índice temporário só com os ficheiros pedidos. O trabalho de outras sessões nunca entra no julgamento
   nem no commit.
3. Corre o Juiz anti-trapaça (teste apagado ou enfraquecido, asserção a menos, conserto-fantasma) e o das zonas
   protegidas (preços, despacho, Stripe, tokens, RLS). Se qualquer um sair com código diferente de 0, **não há commit**.
4. Só se os dois passarem faz o commit, só desses ficheiros. Regista tudo em `C:\Users\danil\.dsh\juiz-dsh.log`.
5. Nunca faz push. Enviar para o servidor é do Claude Code, depois de o Danilo dizer.

## Regras
- Lista os ficheiros um a um (`-Caminhos a,b`). Nunca `git add -A` nem `git add .`.
- Se o script recusar, **não contornes**: lê o motivo, corrige o que ele aponta (por exemplo, repor o teste que
  apagaste) e repete. Se o motivo for zona protegida, para e diz ao Danilo.
- Mensagem no formato `tipo: o que mudou e porquê` (feat, fix, docs, test, chore), em português.
- Tarefa de conserto: usa `-Tarefa fix` para o Juiz apanhar o conserto-fantasma (mexer só no teste).
