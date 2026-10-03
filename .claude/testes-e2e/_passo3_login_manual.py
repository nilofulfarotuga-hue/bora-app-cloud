"""PASSO 3 do diagnóstico E2E — corre UM flow (login cliente) à mão, sem expor segredos.
Reutiliza as funções do runner.py. Imprime só rc + últimas 15 linhas do output do Maestro."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import runner  # noqa

SERIAL = sys.argv[1] if len(sys.argv) > 1 else "N75LTG5X5DSKDMV4"
YAML = "cliente/login.yaml"

creds = runner._creds_maestro()
if not creds.get("CLIENT_PW_A"):
    print("ERRO: sem E2E_CLIENT_PASSWORD no .env — não dá para injetar credenciais")
    sys.exit(3)

log = []
r = runner.corre_maestro(SERIAL, YAML, {}, log)
print(f"=== maestro rc={r['rc']} ok={r['ok']} dur={r['dur_s']}s ===")
print("--- últimas 15 linhas ---")
tail = (r.get("tail") or "").splitlines()
print("\n".join(tail[-15:]))
