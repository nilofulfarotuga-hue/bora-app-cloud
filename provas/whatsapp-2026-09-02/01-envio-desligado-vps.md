# Prova 0b — porta da VPS (Baileys) trancada sem reiniciar (02/09/2026)

`/root/whatsapp-bora/ligar.js` não tem código de envio: o handler `messages.upsert` era um no-op — a porta só emparelha (QR/401). A bandeira `ENVIO_DESLIGADO` ficou lá na mesma, à cabeça, para o dia em que a porta enviar. O serviço **não foi reiniciado de propósito**: cada arranque é mais uma tentativa de emparelhar e o WhatsApp está a recusar com 401 por tentativas a mais desde 31/08 10:18.

```
ligar.js: bandeira inserida
node --check: ok
--- servico (NAO reiniciado de proposito) ---
active
restarts=0
--- bandeira ---
-rw-r--r-- 1 root root 103 Sep  2 06:55 ENVIO_DESLIGADO
11:// o dia em que tiver: enquanto existir DIR/ENVIO_DESLIGADO, nada pode sair por aqui.
12:const ENVIO_DESLIGADO = () => fs.existsSync(DIR + '/ENVIO_DESLIGADO');
73:  sock.ev.on('messages.upsert', () => { if (ENVIO_DESLIGADO()) return; /* sem envio nesta versao */ });
--- 401 continua? ---
FECHADO 401
```

rc do ssh: 0
