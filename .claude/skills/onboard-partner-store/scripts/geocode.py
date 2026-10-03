"""geocode — reutiliza onboard-partner-restaurant/scripts/geocode.py (lógica única).

Executado via subprocess pelo insert_supabase.py com --dir. Encaminha argv para o
módulo original.
"""
import runpy
import sys
from pathlib import Path

_REST = Path(__file__).resolve().parents[2] / "onboard-partner-restaurant" / "scripts"
if str(_REST) not in sys.path:
    sys.path.insert(0, str(_REST))

runpy.run_path(str(_REST / "geocode.py"), run_name="__main__")
