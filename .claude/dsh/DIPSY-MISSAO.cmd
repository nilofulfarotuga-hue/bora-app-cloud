@echo off
rem DIPSY-MISSAO (08/11/2026, missao m3): da ao Dipsy a missao escrita em Desktop\Bora\prompt-dsh.md.
rem Uso: duplo clique (pasta escolhida no Telegram com /pasta) ou DIPSY-MISSAO.cmd em_dia  (ou bora_app, BoraStudio...)
rem Trabalha num worktree proprio, regista no e2e_log e manda o fecho ao Danilo pelo porteiro (texto e voz).
chcp 65001 >nul
title DIPSY-MISSAO
"C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe" "C:\Users\danil\.dsh\telegram\missao.py" %*
echo.
echo Pronto. Podes fechar esta janela.
pause >nul
