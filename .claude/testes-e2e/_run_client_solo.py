# Corre SÓ o lado cliente (reset -> delivery-mercado-cash) num device fixo, com
# visibilidade total do stdout do Maestro. Objetivo: criar 1 pedido REAL e ver
# exatamente onde a compra falha. Reutiliza o env/creds do runner (sem expor chaves).
import sys
import runner

SERIAL = sys.argv[1] if len(sys.argv) > 1 else "RZGYB1XQD2P"
FLUXO = "delivery-mercado-cash"

runner.garante_serial_autorizado(SERIAL)
runner.garante_permissoes(SERIAL)

log = []
for yaml_rel in ("comum/reset-role-screen.yaml", "cliente/delivery-mercado-cash.yaml"):
    print(f"\n===== MAESTRO {yaml_rel} @ {SERIAL} =====", flush=True)
    r = runner.corre_maestro(SERIAL, yaml_rel, {}, log, fluxo=FLUXO)
    print(f"---- rc={r['rc']} dur={r['dur_s']}s ok={r['ok']} ----", flush=True)
    print(r["tail"], flush=True)
    if not r["ok"]:
        print(f"\n!!! PAROU em {yaml_rel} (rc={r['rc']}) — ver tail acima.", flush=True)
        sys.exit(1)
print("\n=== CLIENTE OK: pedido deve estar criado (poll orders para confirmar) ===", flush=True)
