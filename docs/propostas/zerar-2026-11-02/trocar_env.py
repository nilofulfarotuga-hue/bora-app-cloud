# Le a chave nova do stdin e troca o valor de SUPABASE_SERVICE_ROLE_KEY em cada ficheiro dado.
# Guarda copia <ficheiro>.bak-legada-20261102 (mesmas permissoes) e escreve no mesmo inode.
# Imprime so o nome do ficheiro e o prefixo antes/depois.
import shutil
import sys

nova = sys.stdin.readline().strip()
if not nova.startswith("sb_secret_"):
    print("chave invalida no stdin")
    sys.exit(2)
nome = "SUPABASE_SERVICE_ROLE_KEY"
for caminho in sys.argv[1:]:
    with open(caminho, encoding="utf-8") as f:
        linhas = f.read().split("\n")
    mudou = 0
    antes = ""
    for i, l in enumerate(linhas):
        if l.startswith(nome + "="):
            antes = l.split("=", 1)[1][:10]
            linhas[i] = nome + "=" + nova
            mudou += 1
    if mudou == 0:
        print(caminho, "sem a variavel")
        continue
    shutil.copy2(caminho, caminho + ".bak-legada-20261102")
    with open(caminho, "r+", encoding="utf-8") as f:
        f.seek(0)
        f.write("\n".join(linhas))
        f.truncate()
    print(caminho, "linhas=%d" % mudou, "antes=%s..." % antes, "depois=%s..." % nova[:10])
