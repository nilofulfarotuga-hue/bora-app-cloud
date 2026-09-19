"""Helpers partilhados pela skill onboard-partner-restaurant.

Carrega env, lê a bora-knowledge (consulta obrigatória), e expõe wrappers para
invocar Edge Functions e a REST do Supabase. Mantido propositadamente simples.

Uso típico:
    from _shared import Ctx, log
    ctx = Ctx.load(commit=False)
    ctx.require_knowledge()
"""
from __future__ import annotations

import base64
import json
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import requests
except ImportError:  # pragma: no cover
    requests = None

# raiz do skill = .../onboard-partner-restaurant ; raiz do repo = .../bora_app
SKILL_DIR = Path(__file__).resolve().parents[1]
SKILLS_DIR = SKILL_DIR.parent
KNOWLEDGE_DIR = SKILLS_DIR / "bora-knowledge" / "knowledge"

REQUIRED_KNOWLEDGE = [
    "05-business-rules.md",
    "07-database-key-tables.md",
    "08-edge-functions.md",
    "10-protected-zones.md",
]


_EMOJI_ASCII = {
    "✅": "[OK]", "⚠️": "[!]", "❌": "[X]", "🎯": "[*]", "🔒": "[#]",
    "🚀": "[>>>]", "🟠": "[laranja]", "🟢": "[verde]", "ℹ️": "[i]",
    "📸": "[foto]", "🖼️": "[img]", "📝": "[doc]", "🐛": "[bug]", "✨": "[novo]",
    "🔧": "[fix]", "📦": "[pkg]", "👋": "[ola]", "🆕": "[novo]", "🛵": "",
}


def log(msg: str, level: str = "INFO") -> None:
    """Log para stdout, resiliente a consolas cp1252 (Windows).

    Em UTF-8 nativo preserva emojis; em cp1252 (que rebenta em emojis) degrada
    elegantemente: substitui emojis conhecidos por equivalentes texto e usa
    errors='replace' para o resto. Nunca crasha por UnicodeEncodeError.
    """
    line = f"[{level}] {msg}"
    try:
        print(line)
        return
    except UnicodeEncodeError:
        pass
    safe = line
    for emo, rep in _EMOJI_ASCII.items():
        safe = safe.replace(emo, rep)
    enc = getattr(sys.stdout, "encoding", None) or "utf-8"
    print(safe.encode(enc, "replace").decode(enc))


def _load_dotenv() -> None:
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    for candidate in (SKILL_DIR / ".env", SKILLS_DIR.parents[1] / "backend" / ".env"):
        if candidate.exists():
            load_dotenv(candidate)


@dataclass
class Ctx:
    """Contexto de execução: env + flags + cache da knowledge."""
    commit: bool = False
    supabase_url: str = ""
    anon_key: str = ""
    service_role_key: str = ""
    google_maps_key: str = ""
    openai_key: str = ""
    knowledge: dict = field(default_factory=dict)

    @classmethod
    def load(cls, commit: bool = False) -> "Ctx":
        _load_dotenv()
        return cls(
            commit=commit,
            supabase_url=os.environ.get("SUPABASE_URL", "").rstrip("/"),
            anon_key=os.environ.get("SUPABASE_ANON_KEY", ""),
            service_role_key=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""),
            google_maps_key=os.environ.get("GOOGLE_MAPS_API_KEY", ""),
            openai_key=os.environ.get("OPENAI_API_KEY", ""),
        )

    def require_knowledge(self) -> None:
        """Falha cedo se a bora-knowledge não existir. Carrega para self.knowledge."""
        if not KNOWLEDGE_DIR.exists():
            log(f"bora-knowledge não encontrada em {KNOWLEDGE_DIR}. Abortar.", "ERROR")
            sys.exit(2)
        missing = [f for f in REQUIRED_KNOWLEDGE if not (KNOWLEDGE_DIR / f).exists()]
        if missing:
            log(f"Ficheiros knowledge em falta: {missing}", "ERROR")
            sys.exit(2)
        for f in REQUIRED_KNOWLEDGE:
            self.knowledge[f] = (KNOWLEDGE_DIR / f).read_text(encoding="utf-8")
        log(f"bora-knowledge lida ({len(self.knowledge)} ficheiros).")

    # --- Supabase helpers (só usados em --commit) -------------------------
    def _edge(self, fn: str, payload: dict, token: str) -> dict:
        url = f"{self.supabase_url}/functions/v1/{fn}"
        r = requests.post(url, json=payload, timeout=60, headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "apikey": self.anon_key,
        })
        r.raise_for_status()
        return r.json()

    def invoke_register_partner(self, body: dict, partner_jwt: str) -> dict:
        return self._edge("register-partner", body, partner_jwt)

    def invoke_upload_asset(self, restaurant_id: str, kind: str, file_path: Path,
                            content_type: str, partner_jwt: str) -> dict:
        b64 = base64.b64encode(file_path.read_bytes()).decode("ascii")
        return self._edge("upload-restaurant-asset", {
            "restaurantId": restaurant_id, "kind": kind,
            "fileBase64": b64, "contentType": content_type,
        }, partner_jwt)

    def rest(self, method: str, path: str, token: str, body=None) -> requests.Response:
        url = f"{self.supabase_url}/rest/v1/{path}"
        return requests.request(method, url, timeout=60, json=body, headers={
            "Authorization": f"Bearer {token}",
            "apikey": self.anon_key,
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        })


def read_pipeline_json(onboard_dir: Path) -> dict:
    """Lê o estado intermédio escrito pelos passos anteriores do pipeline."""
    p = onboard_dir / "_preview" / "pipeline.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def write_pipeline_json(onboard_dir: Path, data: dict) -> None:
    preview = onboard_dir / "_preview"
    preview.mkdir(parents=True, exist_ok=True)
    (preview / "pipeline.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
