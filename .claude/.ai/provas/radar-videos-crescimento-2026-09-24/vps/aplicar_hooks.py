#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Liga os robos da VPS ao playbook das redes (missao radar-videos-crescimento-2026-09-24).

Uso: python3 aplicar_hooks.py fiscal <fiscal_video.py>
     python3 aplicar_hooks.py reel   <social-reel.sh>
     python3 aplicar_hooks.py emdia  <emdia_redes.py>
Cada um faz backup .bak-playbook-2026-09-24 e so mexe se o texto-ancora existir uma unica vez.
Idempotente: se ja tiver a marca, nao repete.
"""
import io
import shutil
import sys

MARCA = "playbook das redes (radar de videos, 2026-09-24)"


def ler(p):
    raw = io.open(p, "rb").read()
    return raw.decode("utf-8"), (b"\r\n" in raw)


def gravar(p, s, crlf):
    shutil.copyfile(p, p + ".bak-playbook-2026-09-24")
    io.open(p, "wb").write(s.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8") if crlf else s.encode("utf-8"))


def troca(s, a, b):
    if s.count(a) != 1:
        raise SystemExit("ancora nao unica (%d): %r" % (s.count(a), a[:60]))
    return s.replace(a, b)


def fiscal(p):
    s, crlf = ler(p)
    if MARCA in s:
        print("fiscal: ja tinha o hook"); return
    s = troca(s, "import time\n", "import time\n"
              "\n"
              "# --- " + MARCA + " ---------------------------------\n"
              "# Regras destiladas dos videos do YouTube (>= 3 videos cada), escritas pelo PC do\n"
              "# Danilo em /opt/data/social/playbook-redes.json. O olho pontua ate 4 delas e a\n"
              "# nota sai numa linha 'PLAYBOOK ...' e no .txt da prova. INFORMATIVO: nao entra na\n"
              "# nota /100 nem no aprovado/reprovado, para nao mudar o que ja esta agendado.\n"
              "PLAYBOOK_JSON = os.path.join(os.path.dirname(os.path.abspath(__file__)), \"playbook-redes.json\")\n"
              "PLAYBOOK_CATEGORIAS = (\"gancho\", \"duracao\", \"texto\", \"legendas\", \"cta\", \"formato\")\n"
              "\n"
              "\n"
              "def carregar_playbook(caminho=PLAYBOOK_JSON, maximo=4):\n"
              "    try:\n"
              "        with open(caminho, encoding=\"utf-8\") as f:\n"
              "            d = json.load(f)\n"
              "    except Exception:                                         # noqa: BLE001\n"
              "        return 0, []\n"
              "    rs = [r for r in d.get(\"regras\", []) if isinstance(r, dict) and r.get(\"regra\")\n"
              "          and r.get(\"categoria\") in PLAYBOOK_CATEGORIAS]\n"
              "    rs.sort(key=lambda r: -int(r.get(\"n_videos\", 0) or 0))\n"
              "    return int(d.get(\"versao\", 0) or 0), [(\"pb%d\" % i, str(r[\"regra\"])[:160]) for i, r in enumerate(rs[:maximo], 1)]\n"
              "\n"
              "\n"
              "PLAYBOOK_VERSAO, PLAYBOOK = carregar_playbook()\n"
              "\n"
              "\n"
              "def texto_playbook():\n"
              "    if not PLAYBOOK:\n"
              "        return \"\"\n"
              "    return (\"\\n\\nAlem disso, na MESMA resposta JSON acrescenta a chave \\\"playbook\\\": {%s}, um NUMERO de \"\n"
              "            \"0.0 a 1.0 por regra, a dizer quanto a faixa 3 cumpre cada regra do playbook das redes (v%d). \"\n"
              "            \"Isto NAO altera os criterios nem os chumbos acima.\\n%s\"\n"
              "            % (\", \".join('\"%s\": 0.0' % k for k, _ in PLAYBOOK), PLAYBOOK_VERSAO,\n"
              "               \"\\n\".join(\"- %s: %s\" % (k, r) for k, r in PLAYBOOK)))\n"
              "\n"
              "\n"
              "def pontuar_playbook(j):\n"
              "    \"\"\"Linha 'playbook vN: k/n (...)' a partir da resposta da IA. Nunca mexe na nota.\"\"\"\n"
              "    if not PLAYBOOK or not isinstance(j, dict):\n"
              "        return \"\"\n"
              "    pb = j.get(\"playbook\")\n"
              "    if not isinstance(pb, dict):\n"
              "        return \"v%d: a IA nao respondeu as %d regras\" % (PLAYBOOK_VERSAO, len(PLAYBOOK))\n"
              "    partes, soma, n = [], 0.0, 0\n"
              "    for k, _r in PLAYBOOK:\n"
              "        v = pb.get(k)\n"
              "        if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v):\n"
              "            continue\n"
              "        v = min(1.0, max(0.0, float(v))); soma += v; n += 1\n"
              "        partes.append(\"%s=%.1f\" % (k, v))\n"
              "    if not n:\n"
              "        return \"v%d: sem valores validos\" % PLAYBOOK_VERSAO\n"
              "    return \"v%d: %.1f/%d (%s)\" % (PLAYBOOK_VERSAO, soma, n, \", \".join(partes))\n"
              "# -----------------------------------------------------------------------------\n")
    s = troca(s, "{\"text\": PERGUNTA % (crit, chum)}", "{\"text\": PERGUNTA % (crit, chum) + texto_playbook()}")
    s = troca(s, "    n_olho, l_olho, fracos, chumbou, anulados, resumo = 0, [], [], [], [], \"\"\n",
              "    n_olho, l_olho, fracos, chumbou, anulados, resumo = 0, [], [], [], [], \"\"\n"
              "    linha_playbook = pontuar_playbook(j) if j is not None else \"\"\n")
    s = troca(s, "        f.write(\"resumo: %s\\n\" % resumo)\n",
              "        f.write(\"resumo: %s\\n\" % resumo)\n"
              "        f.write(\"playbook: %s\\n\" % (linha_playbook or (\"sem ficheiro %s\" % PLAYBOOK_JSON if not PLAYBOOK else \"sem olho\")))\n")
    s = troca(s, "    print(\"OLHO    %d/55 (%s, tentativa %d/%d): %s\" % (n_olho, modelo, tentativas, TENTATIVAS_IA, \" | \".join(l_olho)))\n",
              "    print(\"OLHO    %d/55 (%s, tentativa %d/%d): %s\" % (n_olho, modelo, tentativas, TENTATIVAS_IA, \" | \".join(l_olho)))\n"
              "    if linha_playbook:\n"
              "        print(\"PLAYBOOK \" + linha_playbook + \"  (informativo, nao entra na nota)\")\n")
    gravar(p, s, crlf); print("fiscal: hook aplicado")


def reel(p):
    s, crlf = ler(p)
    if MARCA in s:
        print("reel: ja tinha o hook"); return
    a = "log() { printf -- '- [%s] reel: %s\\n' \"$STAMP\" \"$*\" >> \"$LOG\"; }\n"
    s = troca(s, a, a +
              "# --- " + MARCA + " ---------------------------------\n"
              "# Regras destiladas dos videos do YouTube (>= 3 videos cada), escritas pelo PC em\n"
              "# /opt/data/social/playbook-redes.json. Fica no log a versao e as regras de gancho/\n"
              "# legenda que valem hoje; o fiscal_video pontua as mesmas regras na peca. Sem\n"
              "# ficheiro nao e erro: segue com as regras fixas deste script.\n"
              "PB_RESUMO=$( { /opt/data/social/venv/bin/python /opt/data/social/playbook_regras.py --resumo 2>/dev/null \\\n"
              "  || python3 /opt/data/social/playbook_regras.py --resumo 2>/dev/null; } | head -c 400 || true)\n"
              "log \"playbook das redes: ${PB_RESUMO:-sem ficheiro (segue com as regras fixas)}\"\n"
              "# -----------------------------------------------------------------------------\n")
    gravar(p, s, crlf); print("reel: hook aplicado")


def emdia(p):
    s, crlf = ler(p)
    if MARCA in s:
        print("emdia: ja tinha o hook"); return
    a = "    m = sys.argv[1]\n    if m == \"hora\":\n"
    s = troca(s, a,
              "    m = sys.argv[1]\n"
              "    if m in (\"hoje\", \"stock\"):\n"
              "        # " + MARCA + ": o robo le o playbook do Bora\n"
              "        # (/opt/data/social/playbook-redes.json) e deixa no log a versao que vale hoje; quem\n"
              "        # gera as pecas no PC segue as mesmas regras e o fiscal pontua-as. Sem ficheiro segue igual.\n"
              "        try:\n"
              "            sys.path.insert(0, \"/opt/data/social\")\n"
              "            import playbook_regras  # noqa: E402\n"
              "            log(\"playbook das redes: \" + playbook_regras.resumo())\n"
              "        except Exception as ex:                                    # noqa: BLE001\n"
              "            log(\"playbook das redes: indisponivel (%s)\" % str(ex)[:80])\n"
              "    if m == \"hora\":\n")
    gravar(p, s, crlf); print("emdia: hook aplicado")


if __name__ == "__main__":
    {"fiscal": fiscal, "reel": reel, "emdia": emdia}[sys.argv[1]](sys.argv[2])
