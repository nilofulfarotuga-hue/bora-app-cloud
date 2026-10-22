"""Põe a chave publicável da Supabase no .dart_defines do build (15/10/2026).

A chave antiga (JWT "anon") vinha no segredo DART_DEFINES_FILE_B64. A nova
(sb_publishable_...) é pública por desenho — vai dentro de qualquer app ou
página — por isso vive aqui, no código, e não num segredo. A antiga continua
válida até o Danilo mandar desligar as chaves legadas (docs/SEGURANCA-CHAVES.md).

Aceita os dois formatos que o .dart_defines já teve: JSON e KEY=VALUE.
Para voltar atrás: reverter o commit que chama este script.
"""
import json
import pathlib
import sys

CHAVE = "sb_publishable_ylfhSuS2D_JoKmtFY-x6-A_DlOgHhVP"

p = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".dart_defines")
texto = p.read_text(encoding="utf-8")

if texto.lstrip().startswith("{"):
    dados = json.loads(texto)
    dados["SUPABASE_ANON_KEY"] = CHAVE
    p.write_text(json.dumps(dados, indent=2) + "\n", encoding="utf-8")
else:
    linhas = [l for l in texto.splitlines() if not l.startswith("SUPABASE_ANON_KEY=")]
    linhas.append("SUPABASE_ANON_KEY=" + CHAVE)
    p.write_text("\n".join(linhas) + "\n", encoding="utf-8")

print("OK: SUPABASE_ANON_KEY = chave publicavel (sb_publishable_...)")
