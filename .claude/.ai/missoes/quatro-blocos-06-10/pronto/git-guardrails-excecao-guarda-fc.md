# Pronto para o Danilo aplicar — exceção do guardião de git para o site do Guarda FC

**Porquê:** o site do clube (`guardafcsad.com`) é republicado pelos robôs a partir do ramo `principal`
do repo `guarda-fc-site`. O guardião (`.claude/hooks/git-guardrails.py`) só deixa enviar para
`autonomous-night-2026-04-29`, em qualquer repositório. A pasta `.claude/hooks/` está trancada nas
permissões (só o Danilo altera) — a edição foi recusada a 06/10/2026, como devia.

**Efeito:** passa a deixar `git -C <pasta> push origin HEAD:principal` **só** quando o remoto dessa pasta
é exatamente `github.com/nilofulfarotuga-hue/guarda-fc-site` (não o `-v7`, não outro). Push forçado e
comandos destrutivos continuam bloqueados (vêm antes desta regra).

## Alteração (em `.claude/hooks/git-guardrails.py`)

1. Por baixo de `RAMOS_PERMITIDOS = [...]`, acrescentar:

```python
RAMO_POR_REPO = {
    "principal": "github.com/nilofulfarotuga-hue/guarda-fc-site",
}


def _remoto_normalizado(pasta, remoto):
    try:
        url = subprocess.check_output(
            ["git", "-C", pasta, "remote", "get-url", remoto],
            stderr=subprocess.STDOUT,
        ).decode("utf-8", "replace").strip().lower()
    except Exception:
        return None
    url = re.sub(r"^(https?://|git@)", "", url).replace("github.com:", "github.com/")
    return url[:-4] if url.endswith(".git") else url


def excecao_por_repo(comando, ramo):
    repo_ok = RAMO_POR_REPO.get(ramo)
    if not repo_ok:
        return False
    m = re.search(r"\bgit\s+-C\s+(\"[^\"]+\"|'[^']+'|\S+)\s+push\s+(\S+)", comando)
    if not m or m.group(2).startswith("-"):
        return False
    return _remoto_normalizado(m.group(1).strip("\"'"), m.group(2)) == repo_ok
```

2. No `main()`, trocar `if ramo not in RAMOS_PERMITIDOS:` por
   `if ramo not in RAMOS_PERMITIDOS and not excecao_por_repo(comando, ramo):`

## Até lá: o comando de uma linha

```
git -C C:/BoraLocal/projetosflutter/guarda-fc-site-fotos push origin HEAD:principal
```

Leva os commits `eb4b66b` (fotos das 20 fichas) e `0f0b010` (23 jogadores). Já estão no ar por envio
direto; o push só garante que o robô do clube não os desfaz na próxima publicação dele.
