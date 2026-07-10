# -*- coding: utf-8 -*-
"""
Cinegrafista — grava o ecrã dos telemóveis durante os testes E2E (scrcpy).

Um processo scrcpy por telemóvel, segmentado POR FLUXO:
  gravacoes/<data>/<serial>/<fluxo>-<ts>.mp4

Uso como módulo (pelo runner.py):
    cine = Cinegrafista()
    mp4 = cine.start("N75LTG5X5DSKDMV4", "login-cliente")
    ... corre o fluxo Maestro ...
    cine.stop("N75LTG5X5DSKDMV4")          # ou cine.stop_all()

Uso manual (CLI):
    python cinegrafista.py start  --serial N75LTG5X5DSKDMV4 --fluxo login-cliente
    python cinegrafista.py stop   --serial N75LTG5X5DSKDMV4
    python cinegrafista.py status

Sincronização: quem regista timestamps é o runner (log com time.time() por passo);
o vídeo começa em start() — o campo 'inicio_epoch' no sidecar .json permite converter
timestamp do log → segundo do vídeo: seg = ts_passo - inicio_epoch.
"""
import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).resolve().parent
GRAVACOES = BASE / "gravacoes"
STATE_FILE = BASE / ".cinegrafista-state.json"

SCRCPY_ARGS = ["--no-playback", "--max-size", "1024", "--max-fps", "20"]
# --no-playback substituiu --no-display no scrcpy >= 2.0; detectado em _scrcpy_flags()


def _scrcpy_bin() -> str:
    exe = shutil.which("scrcpy")
    if exe:
        return exe
    # instalação winget: Links (alias) ou pasta de Packages
    local = Path(os.environ.get("LOCALAPPDATA", ""))
    cand = local / "Microsoft/WinGet/Links/scrcpy.exe"
    if cand.exists():
        return str(cand)
    hits = sorted((local / "Microsoft/WinGet/Packages").glob("Genymobile.scrcpy_*/**/scrcpy.exe"))
    if hits:
        return str(hits[-1])
    raise RuntimeError("scrcpy não encontrado no PATH — instala com: winget install Genymobile.scrcpy")


def _scrcpy_flags() -> list:
    """--no-playback (>=2.0) ou --no-display (1.x)."""
    try:
        out = subprocess.run([_scrcpy_bin(), "--version"], capture_output=True, text=True, timeout=15).stdout
        major = int(out.split()[1].split(".")[0])
    except Exception:
        major = 2
    flag = "--no-playback" if major >= 2 else "--no-display"
    return [flag] + SCRCPY_ARGS[1:] if SCRCPY_ARGS[0].startswith("--no-") else [flag] + SCRCPY_ARGS


def _load_state() -> dict:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def _save_state(st: dict):
    STATE_FILE.write_text(json.dumps(st, indent=2, ensure_ascii=False), encoding="utf-8")


class Cinegrafista:
    def __init__(self):
        self._procs = {}  # serial -> subprocess.Popen

    def start(self, serial: str, fluxo: str) -> str:
        """Arranca gravação para um serial. Devolve o path do mp4."""
        self.stop(serial)  # nunca dois processos para o mesmo device
        dia = datetime.now().strftime("%Y-%m-%d")
        ts = datetime.now().strftime("%H%M%S")
        destino = GRAVACOES / dia / serial
        destino.mkdir(parents=True, exist_ok=True)
        mp4 = destino / f"{fluxo}-{ts}.mp4"
        cmd = [_scrcpy_bin(), f"--serial={serial}", f"--record={mp4}"] + _scrcpy_flags()
        log = open(destino / f"{fluxo}-{ts}.scrcpy.log", "w", encoding="utf-8", errors="replace")
        proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT,
                                creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0))
        self._procs[serial] = proc
        sidecar = {"serial": serial, "fluxo": fluxo, "mp4": str(mp4),
                   "inicio_epoch": time.time(), "pid": proc.pid}
        mp4.with_suffix(".json").write_text(json.dumps(sidecar, indent=2, ensure_ascii=False), encoding="utf-8")
        st = _load_state(); st[serial] = sidecar; _save_state(st)
        time.sleep(1.5)  # frames extra antes da ação (pedido: playback suave)
        if proc.poll() is not None:
            raise RuntimeError(f"scrcpy morreu ao arrancar para {serial} — vê {mp4.with_suffix('.scrcpy.log')}")
        return str(mp4)

    def stop(self, serial: str):
        """Para a gravação de um serial (graciosamente, para o mp4 fechar bem)."""
        proc = self._procs.pop(serial, None)
        st = _load_state()
        info = st.pop(serial, None)
        _save_state(st)
        pid = proc.pid if proc else (info or {}).get("pid")
        if pid is None:
            return
        time.sleep(1.5)  # frames extra depois da ação
        try:
            if proc is not None and proc.poll() is None:
                # CTRL_BREAK fecha o scrcpy limpo no Windows; fallback terminate
                try:
                    proc.send_signal(signal.CTRL_BREAK_EVENT)
                    proc.wait(timeout=8)
                except Exception:
                    proc.terminate()
                    proc.wait(timeout=8)
            elif proc is None:
                subprocess.run(["taskkill", "/PID", str(pid), "/T"], capture_output=True)
        except Exception:
            pass

    def stop_all(self):
        for serial in list(self._procs.keys()) + list(_load_state().keys()):
            self.stop(serial)


def main():
    ap = argparse.ArgumentParser(description="Cinegrafista — gravação scrcpy por fluxo")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_start = sub.add_parser("start"); p_start.add_argument("--serial", required=True); p_start.add_argument("--fluxo", required=True)
    p_stop = sub.add_parser("stop"); p_stop.add_argument("--serial", required=True)
    sub.add_parser("stop-all")
    sub.add_parser("status")
    args = ap.parse_args()
    cine = Cinegrafista()
    if args.cmd == "start":
        print(cine.start(args.serial, args.fluxo))
    elif args.cmd == "stop":
        cine.stop(args.serial); print("parado")
    elif args.cmd == "stop-all":
        cine.stop_all(); print("tudo parado")
    elif args.cmd == "status":
        print(json.dumps(_load_state(), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
