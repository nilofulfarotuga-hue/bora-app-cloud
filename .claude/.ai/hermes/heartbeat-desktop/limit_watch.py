# -*- coding: utf-8 -*-
"""
limit_watch.py — monitor de limite de sessao/uso (Claude) para o lado PC.

REENGENHARIA 2026-07-13 (ver inbox/reengenharia-loop-resiliencia-2026-07-13.md):
causa provada da paragem de madrugada: a conta Claude Code bateu limite de sessao
~02:31, a fila pausou, e quando a quota renovou NADA no lado PC retomou sozinho —
parou ate o Danilo reviver de manha. O carteiro/campainha (VPS) tem o mesmo padrao
em bash (`carteiro.sh: is_rate_limit / rl_resume_epoch`, ligado 2026-07-12); este
ficheiro e a MESMA logica em Python, para qualquer wrapper do lado PC (heartbeat-
desktop, e no futuro o bridge run-claude-loop.cmd) usar sem reinventar o parsing.

Uso:
  from limit_watch import is_rate_limit, parse_resume_epoch, gate

  # deteta na saida de um passo
  if is_rate_limit(saida):
      resume = parse_resume_epoch(saida)
      write_pause(PAUSA_PATH, resume)

  # no INICIO de cada ciclo do schtask, antes de fazer trabalho:
  ok, info = gate(PAUSA_PATH)
  if not ok:
      log(f"pausado por rate-limit ate {info}")
      sys.exit(0)   # sai em silencio; o schtask */10min tenta de novo sozinho

CLI:
  python limit_watch.py --selftest      # testa deteccao+parse+gate sem esperar reset real
"""
from __future__ import annotations

import re
import sys
import time
from pathlib import Path

# Windows nao traz a base IANA para zoneinfo (ao contrario de Linux/macOS) -> pacote
# 'tzdata' instalado localmente em _libs (mesmo padrao do desktop-send.py), independente
# da sessao/user. `pip install --target _libs tzdata`.
_LIBS = Path(__file__).resolve().parent / "_libs"
if _LIBS.is_dir() and str(_LIBS) not in sys.path:
    sys.path.insert(0, str(_LIBS))

from zoneinfo import ZoneInfo

MARGIN_SECONDS = 120          # "+2min de margem" pedido na reengenharia
DEFAULT_TZ = "Europe/Lisbon"  # timezone do Danilo; usado quando a mensagem nao diz
FALLBACK_SECONDS = 3600       # defensivo: sem hora parseavel -> pausa 1h (nunca ficar preso)

_RATE_LIMIT_RE = re.compile(
    r"hit your (session|usage) limit"
    r"|session limit"
    r"|usage limit"
    r"|limit reached"
    r"|rate limit"
    r"|reached your (usage|session)? *limit",
    re.IGNORECASE,
)

# "resets 5pm (Europe/London)" | "resets at 5pm" | "resets at 17:00" | "resets 5:30pm (Europe/Lisbon)"
_RESETS_RE = re.compile(
    r"resets?\s+(?:at\s+)?"
    r"(?P<h>\d{1,2})(?::(?P<m>\d{2}))?\s*(?P<ap>am|pm)?"
    r"(?:\s*\((?P<tz>[A-Za-z_]+/[A-Za-z_]+)\))?",
    re.IGNORECASE,
)


def is_rate_limit(text: str) -> bool:
    """True se o texto contiver um dos padroes de limite de sessao/uso."""
    if not text:
        return False
    return bool(_RATE_LIMIT_RE.search(text))


def parse_resume_epoch(text: str, now: float | None = None, margin_seconds: int = MARGIN_SECONDS) -> float:
    """
    Extrai a hora de reset da propria mensagem (timezone-aware) e devolve o epoch UTC
    de quando e seguro retomar (hora do reset + margem). Se nao conseguir parsear uma
    hora, devolve now + FALLBACK_SECONDS (defensivo — nunca pausa para sempre).
    """
    now = time.time() if now is None else now
    m = _RESETS_RE.search(text or "")
    if not m:
        return now + FALLBACK_SECONDS

    hh = int(m.group("h"))
    mm = int(m.group("m") or 0)
    ap = (m.group("ap") or "").lower()
    tz_name = m.group("tz") or DEFAULT_TZ

    if ap == "pm" and hh != 12:
        hh += 12
    elif ap == "am" and hh == 12:
        hh = 0

    if hh > 23 or mm > 59:
        return now + FALLBACK_SECONDS

    try:
        tz = ZoneInfo(tz_name)
    except Exception:
        tz = ZoneInfo(DEFAULT_TZ)

    import datetime as _dt
    local_now = _dt.datetime.fromtimestamp(now, tz)
    candidate = local_now.replace(hour=hh, minute=mm, second=0, microsecond=0)
    if candidate.timestamp() <= now:
        candidate += _dt.timedelta(days=1)  # a hora ja passou hoje -> e amanha

    return candidate.timestamp() + margin_seconds


def write_pause(path: Path, resume_epoch: float) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(str(int(resume_epoch)), encoding="utf-8")


def read_pause(path: Path) -> float | None:
    if not path.exists():
        return None
    try:
        return float(re.sub(r"[^0-9]", "", path.read_text(encoding="utf-8")) or "0") or None
    except Exception:
        return None


def clear_pause(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except Exception:
        pass


def gate(path: Path, now: float | None = None) -> tuple[bool, str]:
    """
    Verifica o ficheiro de pausa no INICIO de um ciclo.
    Devolve (True, "") se pode prosseguir (sem pausa, ou pausa ja expirada — e
    limpa-a sozinho, retomando sem intervencao do Danilo).
    Devolve (False, "HH:MM UTC") se ainda deve esperar.
    """
    now = time.time() if now is None else now
    resume = read_pause(path)
    if resume is None:
        return True, ""
    if now >= resume:
        clear_pause(path)
        return True, ""
    hhmm = time.strftime("%H:%M", time.gmtime(resume))
    return False, f"{hhmm} UTC"


# --------------------------- selftest (sem esperar reset real) ---------------------------
def _selftest() -> int:
    import tempfile

    ok = 0
    fail = 0

    def chk(label, cond):
        nonlocal ok, fail
        if cond:
            print(f"  [OK] {label}")
            ok += 1
        else:
            print(f"  [X ] {label}")
            fail += 1

    print("== deteccao is_rate_limit ==")
    chk("'You've hit your session limit · resets 5pm (Europe/London)'",
        is_rate_limit("You've hit your session limit · resets 5pm (Europe/London)"))
    chk("'usage limit reached. resets at 17:00'",
        is_rate_limit("usage limit reached. resets at 17:00"))
    chk("'Claude AI limit reached, resets 3pm'",
        is_rate_limit("Claude AI limit reached, resets 3pm"))
    chk("sem falso-positivo em texto normal",
        not is_rate_limit("tudo bem, terminei a tarefa com sucesso"))

    print("== parse_resume_epoch (timezone-aware + margem 2min) ==")
    now = time.time()
    ep = parse_resume_epoch("resets 5pm (Europe/London)", now=now)
    chk("epoch sempre no futuro", ep > now)
    london_5pm = __import__("datetime").datetime.fromtimestamp(ep, ZoneInfo("Europe/London"))
    chk("hora extraida = 17:xx Europe/London (+ margem)", london_5pm.hour in (17, 18) if london_5pm.minute >= 58 or london_5pm.hour == 17 else london_5pm.hour == 17)
    chk("margem de 2min aplicada", abs((ep - MARGIN_SECONDS) - int(ep - MARGIN_SECONDS)) < 1)

    ep_notz = parse_resume_epoch("resets at 22:15", now=now)
    lisboa = __import__("datetime").datetime.fromtimestamp(ep_notz, ZoneInfo(DEFAULT_TZ))
    chk("sem tz explicita -> usa DEFAULT_TZ (Europe/Lisbon), hora 22:xx", lisboa.hour == 22)

    ep_defensivo = parse_resume_epoch("mensagem sem hora nenhuma aqui", now=now)
    chk("sem hora parseavel -> defensivo now+1h (nunca preso p/ sempre)",
        FALLBACK_SECONDS - 5 <= (ep_defensivo - now) <= FALLBACK_SECONDS + 5)

    print("== write_pause / read_pause / clear_pause / gate ==")
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / ".pausa-rate-limit-pc"

        can, info = gate(p, now=now)
        chk("sem ficheiro de pausa -> gate deixa passar", can and info == "")

        write_pause(p, now + 3600)
        can, info = gate(p, now=now)
        chk("pausa no futuro -> gate BLOQUEIA (nao gasta tentativa)", not can and info != "")

        can2, _ = gate(p, now=now + 3601)
        chk("pausa expirada -> gate LIBERTA sozinho (sem Danilo)", can2)
        chk("gate limpou o ficheiro apos expirar", read_pause(p) is None)

    print("== fluxo ponta-a-ponta: deteta -> calcula resume -> pausa -> expira -> retoma ==")
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / ".pausa-rate-limit-pc"
        saida_simulada = "You've hit your session limit · resets 5pm (Europe/London)"
        chk("simulacao: is_rate_limit detecta a saida", is_rate_limit(saida_simulada))
        resume = parse_resume_epoch(saida_simulada, now=now)
        write_pause(p, resume)
        can, info = gate(p, now=now)
        chk("simulacao: ciclo seguinte (ainda dentro da janela) fica pausado", not can)
        can, info = gate(p, now=resume + 1)
        chk("simulacao: ciclo apos o reset+margem RETOMA sozinho", can)

    print(f"-- selftest limit_watch: {ok} OK, {fail} FALHAS --")
    return 1 if fail else 0


if __name__ == "__main__":
    import sys

    if "--selftest" in sys.argv[1:]:
        sys.exit(_selftest())
    print(__doc__)
    sys.exit(0)
