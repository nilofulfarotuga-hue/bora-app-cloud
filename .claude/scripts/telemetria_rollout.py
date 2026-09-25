# -*- coding: utf-8 -*-
"""
telemetria_rollout.py — Fase 5.2: TELEMETRIA UNIVERSAL de skills.

Para cada .claude/skills/*/SKILL.md (só 1 nível — referencias/ e scripts/ ficam intactos):
  1. Frontmatter: garante as 6 chaves de telemetria (versao, execucoes, sucessos,
     falhas, ultima_execucao, criada_por), aninhadas sob `metadata:` — o mesmo
     padrão de .claude/skills/diretor-criativo/SKILL.md. Preserva tudo o que existe.
  2. Fim do ficheiro: acrescenta a secção "Telemetria" (detetada pelo título) se faltar.

Idempotente: correr 2x não duplica nada. Preserva encoding UTF-8 (+BOM se houver)
e fins de linha (CRLF/LF) de cada ficheiro. Valida o frontmatter após escrever;
se a validação falhar, reverte o ficheiro e reporta.
"""

import codecs
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]  # .claude/scripts/ -> repo root
SKILLS_DIR = REPO / ".claude" / "skills"

TELEMETRY_KEYS = ["versao", "execucoes", "sucessos", "falhas", "ultima_execucao", "criada_por"]
TELEMETRY_VALUES = {
    "versao": "1.0",
    "execucoes": "0",
    "sucessos": "0",
    "falhas": "0",
    "ultima_execucao": "null",
    "criada_por": "pre-telemetria (rollout 2026-07-10)",
}

SECTION_TITLE_RE = re.compile(r"^#{1,6}\s*(?:\d+[\.\)]\s*)?.*telemetria", re.IGNORECASE | re.MULTILINE)

SECTION_TEXT = """## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo."""


def read_file(path):
    """Lê bytes e devolve (texto normalizado a \\n, newline, bom, tinha_newline_final)."""
    data = path.read_bytes()
    bom = data.startswith(codecs.BOM_UTF8)
    if bom:
        data = data[len(codecs.BOM_UTF8):]
    nl = "\r\n" if b"\r\n" in data else "\n"
    text = data.decode("utf-8")
    trailing_nl = text.endswith(("\n", "\r\n"))
    text = text.replace("\r\n", "\n")
    return text, nl, bom, trailing_nl


def write_file(path, text, nl, bom, trailing_nl):
    if trailing_nl and not text.endswith("\n"):
        text += "\n"
    if nl == "\r\n":
        text = text.replace("\n", "\r\n")
    data = text.encode("utf-8")
    if bom:
        data = codecs.BOM_UTF8 + data
    path.write_bytes(data)


def split_frontmatter(text):
    """Devolve (fm_lines, body_start_line_idx) ou (None, 0) se não houver frontmatter."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, 0
    for i in range(1, len(lines)):
        if lines[i].strip() in ("---", "..."):
            return lines[1:i], i + 1
    return None, 0  # frontmatter aberto sem fecho -> tratar como inexistente (não mexe)


def has_key(fm_lines, key):
    pat = re.compile(r"^\s*" + re.escape(key) + r"\s*:")
    return any(pat.match(ln) for ln in fm_lines)


def telemetry_block(indent):
    return [indent + "{}: {}".format(k, TELEMETRY_VALUES[k]) for k in TELEMETRY_KEYS
            if k in TELEMETRY_VALUES]


def add_missing_keys(fm_lines):
    """Acrescenta as chaves em falta sob `metadata:` (padrão diretor-criativo).
    Devolve (novas_fm_lines, alterou)."""
    missing = [k for k in TELEMETRY_KEYS if not has_key(fm_lines, k)]
    if not missing:
        return fm_lines, False

    meta_idx = None
    for i, ln in enumerate(fm_lines):
        if re.match(r"^metadata\s*:\s*$", ln):
            meta_idx = i
            break

    new = list(fm_lines)
    if meta_idx is not None:
        # fim do bloco metadata = última linha seguida ainda indentada (ou blank dentro)
        end = meta_idx + 1
        child_indent = "  "
        j = meta_idx + 1
        while j < len(new) and (new[j].startswith((" ", "\t")) or new[j].strip() == ""):
            if new[j].strip():
                end = j + 1
                m = re.match(r"^(\s+)\S", new[j])
                if m and j == meta_idx + 1:
                    child_indent = m.group(1)
            j += 1
        ins = [child_indent + "{}: {}".format(k, TELEMETRY_VALUES[k]) for k in missing]
        new[end:end] = ins
    else:
        block = ["metadata:"] + ["  {}: {}".format(k, TELEMETRY_VALUES[k]) for k in missing]
        new.extend(block)
    return new, True


def simple_yaml_check(fm_lines):
    """Validação: tenta PyYAML; senão, check estrutural leniente."""
    fm_text = "\n".join(fm_lines)
    try:
        import yaml  # type: ignore
        parsed = yaml.safe_load(fm_text)
        return isinstance(parsed, dict) and parsed
    except ImportError:
        pass
    except Exception:
        return False
    for ln in fm_lines:
        if not ln.strip():
            continue
        if ln.startswith((" ", "\t")):       # continuação/indentado (metadata, block scalar)
            continue
        if ln.lstrip().startswith("#"):
            continue
        if re.match(r"^[A-Za-z_][\w\-]*\s*:", ln):
            continue
        return False
    return True


def validate_file(path):
    """Após escrever: o ficheiro começa com frontmatter --- bem formado?"""
    try:
        text, _, _, _ = read_file(path)
    except Exception:
        return False
    fm, _ = split_frontmatter(text)
    if fm is None:
        return False
    ok = simple_yaml_check(fm)
    return bool(ok) and all(has_key(fm, k) for k in TELEMETRY_KEYS)


def process(path):
    """Devolve (status, detalhes). status: 'skipped' | 'changed' | 'reverted' | 'error'."""
    original = path.read_bytes()
    text, nl, bom, trailing_nl = read_file(path)
    fm_lines, body_start = split_frontmatter(text)
    changed_fm = False
    changed_section = False
    details = []

    lines = text.split("\n")

    if fm_lines is not None:
        new_fm, changed_fm = add_missing_keys(fm_lines)
        if changed_fm:
            lines = ["---"] + new_fm + ["---"] + lines[body_start:]
            details.append("frontmatter+chaves")
    else:
        # sem frontmatter -> bloco novo no topo só com telemetria (padrão metadata)
        block = ["---", "metadata:"] + ["  {}: {}".format(k, TELEMETRY_VALUES[k]) for k in TELEMETRY_KEYS] + ["---", ""]
        lines = block + lines
        changed_fm = True
        details.append("frontmatter novo")

    new_text = "\n".join(lines)

    if not SECTION_TITLE_RE.search(new_text):
        new_text = new_text.rstrip("\n") + "\n\n" + SECTION_TEXT + "\n"
        trailing_nl = True
        changed_section = True
        details.append("secção telemetria")

    if not changed_fm and not changed_section:
        return "skipped", "já completo"

    write_file(path, new_text, nl, bom, trailing_nl)

    if not validate_file(path):
        path.write_bytes(original)
        return "reverted", "validação falhou — revertido"

    return "changed", "+".join(details)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    if not SKILLS_DIR.is_dir():
        print("ERRO: pasta de skills não encontrada: {}".format(SKILLS_DIR))
        return 1

    skill_files = sorted(SKILLS_DIR.glob("*/SKILL.md"))  # só 1 nível
    total = len(skill_files)
    changed, skipped, problems = [], [], []

    for f in skill_files:
        name = f.parent.name
        try:
            status, det = process(f)
        except Exception as exc:  # nunca deixar meio-escrito
            try:
                pass
            finally:
                problems.append("{}: EXCEÇÃO {}".format(name, exc))
            continue
        if status == "changed":
            changed.append(name)
            print("[ALTERADO] {} ({})".format(name, det))
        elif status == "skipped":
            skipped.append(name)
            print("[SKIP]     {} ({})".format(name, det))
        else:
            problems.append("{}: {}".format(name, det))
            print("[PROBLEMA] {} ({})".format(name, det))

    print()
    print("=== RESUMO ===")
    print("Total de skills:  {}".format(total))
    print("Alteradas:        {}".format(len(changed)))
    print("Skipped:          {}".format(len(skipped)))
    print("Problemas:        {}".format(len(problems)))
    if changed:
        print("Alteradas: " + ", ".join(changed))
    if skipped:
        print("Skipped:   " + ", ".join(skipped))
    if problems:
        for p in problems:
            print("  !! " + p)

    # validação final de todos os alterados
    bad = [n for n in changed if not validate_file(SKILLS_DIR / n / "SKILL.md")]
    if bad:
        print("FALHA NA VALIDAÇÃO FINAL: " + ", ".join(bad))
        return 2
    print("Validação final: todos os SKILL.md alterados começam com frontmatter --- bem formado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
