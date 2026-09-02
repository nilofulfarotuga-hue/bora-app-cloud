# -*- coding: utf-8 -*-
"""espelhar_para_repo.py — copia o codigo vivo do WhatsApp da loja para o repo do bora_app.

O codigo VIVO fica em C:\\BoraLocal\\Desktop-PC-antigo\\ferramentas\\whatsapp-loja (e a tarefa
agendada CerebroWhatsAppBora aponta para la). O repo leva uma copia SEM lixo -- nunca .env, audios,
imagens, logs, caches, node_modules, backups -- para o push da missao levar so o que e desta missao.
"""
import os
import shutil

ORIGEM = r"C:\BoraLocal\Desktop-PC-antigo\ferramentas\whatsapp-loja"
DESTINO = r"C:\BoraLocal\projetosflutter\bora_app\ferramentas\whatsapp-loja"
FORA_DIRS = {"node_modules", "audios", "imagens", "__pycache__", "_fichas", "enviados", "rascunhos", ".git"}
FORA_EXT = {".log", ".jsonl", ".bak", ".json"}          # .json: _tarefas/_atrasos locais; o registo fica no Supabase
FORA_NOMES = {".env", "ENVIO_DESLIGADO", "PEDIR_CENSO", "package-lock.json"}


def fora(nome):
    if nome in FORA_NOMES:
        return True
    if any(nome.endswith(e) or ".bak-" in nome for e in FORA_EXT):
        return True
    return False


def main():
    n = 0
    for raiz, dirs, ficheiros in os.walk(ORIGEM):
        dirs[:] = [d for d in dirs if d not in FORA_DIRS]
        rel = os.path.relpath(raiz, ORIGEM)
        alvo = os.path.join(DESTINO, rel) if rel != "." else DESTINO
        os.makedirs(alvo, exist_ok=True)
        for f in ficheiros:
            if fora(f):
                continue
            shutil.copy2(os.path.join(raiz, f), os.path.join(alvo, f))
            n += 1
    print("espelhados %d ficheiros para %s" % (n, DESTINO))


if __name__ == "__main__":
    main()
