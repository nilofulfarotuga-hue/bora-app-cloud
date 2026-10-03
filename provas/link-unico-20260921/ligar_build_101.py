"""Paridade 3 plataformas (2026-09-21) — H4: liga o build do TestFlight à versão
1.0.1 (PREPARE_FOR_SUBMISSION) sem submeter nada.

Uso: python ligar_build_101.py <numero do build, ex. 130>

O que faz, por esta ordem, e tudo lido de volta:
  1. procura o build pelo número (filter[version]) e imprime processingState;
  2. só liga se processingState == VALID (senão diz para esperar);
  3. PATCH /v1/appStoreVersions/{id}/relationships/build;
  4. lê de volta /v1/appStoreVersions/{id}/build e confirma o número.
NUNCA chama /v1/appStoreVersionSubmissions — submeter é o clique do Danilo.
"""
import sys
import asc_api as a

APP = "6809954739"
VERSAO_101 = "02c335b3-25f0-44c6-9590-0c6a18ca268d"   # criada 21/09 como 1.0.1 (link-unico); renomeada 1.0.2 a 21/09 (comboio 1.0.1 fechado)


def main(numero: str) -> int:
    c, v = a.get(f"/v1/appStoreVersions/{VERSAO_101}",
                 **{"fields[appStoreVersions]": "versionString,appStoreState,appVersionState"})
    print("versão:", c, v.get("data", {}).get("attributes"))
    estado = v.get("data", {}).get("attributes", {}).get("appStoreState")
    if estado != "PREPARE_FOR_SUBMISSION":
        print("A 1.0.1 não está em PREPARE_FOR_SUBMISSION — não mexo.")
        return 2

    c, bs = a.get("/v1/builds", **{"filter[app]": APP, "filter[version]": numero,
                                   "fields[builds]": "version,processingState,uploadedDate,expired"})
    dados = bs.get("data", [])
    print("builds com esse número:", c, [(b["id"], b["attributes"]) for b in dados])
    if not dados:
        print("Ainda não há build", numero, "no App Store Connect — esperar o upload/processamento.")
        return 3
    b = dados[0]
    if b["attributes"].get("processingState") != "VALID":
        print("Build ainda em", b["attributes"].get("processingState"), "— esperar.")
        return 3

    c, r = a.patch(f"/v1/appStoreVersions/{VERSAO_101}/relationships/build",
                   {"type": "builds", "id": b["id"]})
    print("PATCH relationships/build ->", c, (r if c >= 300 else "ok"))
    if c >= 300:
        return 1

    c, lido = a.get(f"/v1/appStoreVersions/{VERSAO_101}/build",
                    **{"fields[builds]": "version,processingState"})
    atr = (lido.get("data") or {}).get("attributes")
    print("lido de volta: build ligada à 1.0.1 =", atr)
    return 0 if (atr or {}).get("version") == numero else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "132"))
