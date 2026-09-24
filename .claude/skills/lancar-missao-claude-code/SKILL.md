---
name: lancar-missao-claude-code
description: Procedimento certo para lançar uma missão grande no Claude Code do navegador para o Danilo.
---

# Lançar missão no Claude Code (caminho certo)

1. Escrever o prompt completo (regras do Danilo: MODO PROTECÇÃO TOTAL, CEO-AI, motor no topo, /ctx doctor e /ctx stats no fim).
2. Pôr o prompt como ficheiro PROMPT_<nome>_<data>.md na raiz do repo:
   - bora-app-cloud, ramo autonomous-night-2026-04-29 (push pela VPS ou GitHub web);
   - em-dia-app, ramo main: SÓ pelo GitHub web no Chrome (a chave da VPS só lê).
3. Abrir claude.ai/code no Chrome, escolher repo + ramo; nuvem (Default) salvo se precisar do PC (aí Controle Remoto, claude rc).
4. Escrever na caixa com type uma frase curta: "Lê PROMPT_<nome>.md na raiz e executa bloco a bloco". Colar texto grande por JS é bloqueado.
5. O Enter é bloqueado: pôr o separador à frente e dizer ao Danilo só "carrega Enter".
6. Vigiar pelo e2e_log (run_id da missão) e aplicar por MCP o que vier bloqueado.
7. NUNCA mandar missão grande pelo cortex_nova_ordem (loop).
