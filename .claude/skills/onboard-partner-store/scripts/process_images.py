"""process_images — reutiliza onboard-partner-restaurant/scripts/process_images.py.

Lógica única (rembg + resize WebP 3 tamanhos). Encaminha argv para o módulo original.
"""
import runpy
import sys
from pathlib import Path

_REST = Path(__file__).resolve().parents[2] / "onboard-partner-restaurant" / "scripts"
if str(_REST) not in sys.path:
    sys.path.insert(0, str(_REST))

runpy.run_path(str(_REST / "process_images.py"), run_name="__main__")
