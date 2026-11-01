# B2: resumo do motor de cada perfil do Hermes (corre DENTRO do contentor). Nunca imprime chaves.
import glob
import os
import sys

try:
    import yaml
except ImportError:
    yaml = None

base = sys.argv[1] if len(sys.argv) > 1 else "/opt/data"
ficheiros = sorted(glob.glob(os.path.join(base, "profiles", "*", "config.yaml"))) + [os.path.join(base, "config.yaml")]
for f in ficheiros:
    if not os.path.exists(f):
        continue
    nome = os.path.basename(os.path.dirname(f)) if "profiles" in f else "(principal)"
    try:
        d = yaml.safe_load(open(f, encoding="utf-8")) if yaml else {}
    except Exception as e:  # noqa: BLE001
        print(nome, "ERRO", e)
        continue
    m = d.get("model") or {}
    fb = d.get("fallback_providers") or d.get("fallback_model") or d.get("fallbacks") or (m.get("fallbacks") if isinstance(m, dict) else None)
    fbt = []
    if isinstance(fb, list):
        for x in fb:
            if isinstance(x, dict):
                fbt.append("%s:%s@%s" % (x.get("provider"), x.get("model"), (x.get("base_url") or "")[:28]))
            else:
                fbt.append(str(x))
    elif isinstance(fb, dict):
        fbt.append("%s:%s@%s" % (fb.get("provider"), fb.get("model"), (fb.get("base_url") or "")[:28]))
    aux = d.get("auxiliary") or {}
    auxt = sorted({"%s:%s" % ((v or {}).get("provider"), (v or {}).get("model")) for v in aux.values() if isinstance(v, dict)}) if isinstance(aux, dict) else []
    print("%-20s default=%-24s base=%-32s fallback=%s aux=%s" % (nome, m.get("default") if isinstance(m, dict) else m,
          (m.get("base_url") if isinstance(m, dict) else "")[:32], fbt[:4], auxt[:4]))
