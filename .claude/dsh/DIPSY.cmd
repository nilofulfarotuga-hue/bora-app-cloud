@echo off
rem DIPSY - abre o Dipsy (o segundo Claude Code, com motor gratis) pronto a falar:
rem pagina de conversa no navegador + ligacao ao Telegram. Para parar: carregar numa tecla na janela.
rem Nunca meter segredos na conversa; dados de clientes so quando a tarefa precisar e nunca em massa.
title DIPSY
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\danil\.dsh\dipsy.ps1"
