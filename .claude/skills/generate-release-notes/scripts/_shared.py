"""Helpers S4-C (release). Só git read-only — não usa o motor Supabase."""
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]  # …/skills/<skill>/scripts → bora_app


def log(msg: str, level: str = "INFO") -> None:
    line = f"[{level}] {msg}"
    try:
        print(line)
    except UnicodeEncodeError:  # consola Windows cp1252 vs emojis
        enc = sys.stdout.encoding or "utf-8"
        print(line.encode(enc, "replace").decode(enc))


def run_git(args: list[str]) -> str:
    """Corre um comando git read-only no repo e devolve stdout (str)."""
    try:
        r = subprocess.run(["git", "-C", str(REPO_ROOT)] + args,
                           capture_output=True, text=True, timeout=60,
                           encoding="utf-8", errors="replace")  # Windows: evitar cp1252 em acentos
        if r.returncode != 0:
            return ""
        return r.stdout
    except Exception as e:  # noqa: BLE001
        log(f"git falhou ({' '.join(args)}): {e}", "WARN")
        return ""
