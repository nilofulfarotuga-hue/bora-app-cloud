---
name: hermes-email-management-himalaya
category: email
description: Gerencia e-mails usando a CLI himalaya, incluindo listagem, leitura e exclusão.
---

### Propósito

Esta skill descreve como interagir com o cliente de e-mail `himalaya` via terminal para realizar operações básicas como listar, ler e apagar e-mails.

### Comandos Essenciais

- **Listar envelopes (mensagens resumidas):**
  - Para listar os e-mails mais recentes, ordenados por data (mais novos primeiro):
    `~/.local/bin/himalaya envelope list --output json --page-size <NÚMERO> order by date desc`
    - Use `--page-size` para limitar o número de resultados (ex: `20`), não `--limit`.
  - Para listar com filtros específicos (ex: remetente, assunto, data):
    `~/.local/bin/himalaya envelope list --output json --page-size <NÚMERO> [QUERY]`
    - Exemplos de `QUERY`: `subject "foo"`, `from "<endereco@email.com>"`, `after 2026-07-08`.

- **Mover mensagens para uma pasta:**
  - `~/.local/bin/himalaya message move "<PASTA_DE_DESTINO>" <ID_DA_MENSAGEM(NS)>`
  - **Importante:** O nome da pasta de destino deve vir **antes** dos IDs das mensagens.
  - **Nome da Lixeira do Gmail:** Utilize `"[Gmail]/Trash"` para a lixeira (entre aspas).
  - Exemplo: `himalaya message move "[Gmail]/Trash" 173 172`

- **Ler um e-mail específico por ID:**
  - `~/.local/bin/himalaya message read <id_do_email> --output json`

- **Apagar um e-mail por ID:**
  - `~/.local/bin/himalaya message delete <id_do_email>`
  - ⚠️ **CUIDADO:** Esta operação é irreversível. Sempre confirme com o usuário antes de apagar e-mails críticos.

### Pitfalls e Workarounds

- **Sintaxe de busca complexa:** A sintaxe de pesquisa do `himalaya` pode ser complexa e não intuitiva (ex: `from: Uber` pode falhar). Se a busca direta via `envelope list <query>` falhar repetidamente ou for muito complexa, a abordagem recomendada é:
  1.  Listar um número maior de envelopes (e-mails) usando `envelope list --page-size <numero_grande>`.
  2.  Filtrar os e-mails programaticamente usando Python, processando a saída JSON. Isso oferece maior flexibilidade e robustez.

### Workflow Típico

1.  **Listar e-mails:** Use `envelope list` para obter uma visão geral dos e-mails.
2.  **Identificar e-mails de interesse:** Analise o JSON retornado para encontrar IDs de e-mails relevantes (ex: filtrando por `from` ou `subject` no Python).
3.  **Ler conteúdo (se necessário):** Use `message read <id>` para obter o conteúdo completo de um e-mail e aplicar critérios mais detalhados.
4.  **Decidir ação:** Com base nos critérios do usuário (ex: guardar importantes, apagar irrelevantes), prepare as operações de exclusão.
5.  **Apagar:** Use `message delete <id>` para remover os e-mails indesejados, sempre com confirmação do usuário se a ação for destrutiva.
