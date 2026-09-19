@echo off
cd /d "C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\testes-e2e"
"C:\Users\danil\Desktop\produtividade-ia\agent-reach-venv\Scripts\python.exe" loop-noturno.py > loop-noturno-task-%DATE:/=-%.log 2>&1

