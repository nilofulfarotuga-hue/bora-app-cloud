# README — generate-release-notes

Gera notas de versão PT-PT a partir do git. Read-only; só escreve um markdown.

## Ambiente
Nenhum (git local). Sem dependências pip (stdlib + git).

## Uso
```bash
python scripts/release_notes.py                 # desde o último tag
python scripts/release_notes.py --since v1.0.0
python scripts/release_notes.py --version 231
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | `REPO_ROOT` + `run_git()` (helper read-only) |
| `release_notes.py` | git log agrupado por tipo → `RELEASE_NOTES_v{N}.md` (+ secção "Para testers") |

## Notas
- Range: `--since <ref>` ou último tag (`git describe --tags --abbrev=0`).
- Versão lida de `pubspec.yaml` (`version: x.y.z+BUILD`) — usa o `BUILD` no título salvo `--version`.
- **Não** cria tag nem faz push. Não incrementa versionCode.
