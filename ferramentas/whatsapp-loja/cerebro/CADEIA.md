# Ordem dos motores (cerebro/cadeia.txt) — decisão de 02/09/2026
Medido na 2.ª volta das provas: o qwen2.5:7b local demorou >150 s a avaliar o prompt do agente
(~3 mil tokens) a frio neste CPU, em todas as provas; o gemini-3.6-flash respondeu com ferramentas
reais em 4–20 s. Um cliente não espera dois minutos. Ordem: gemini-3.6-flash → ollama (45 s de
espera; útil quando o Gemini estiver esgotado) → gemini-3-flash-preview. Custo: quota grátis do
Gemini; quando cair (429), o cérebro marca-o esgotado 10 min e desce sozinho. Voltar a pôr o
Ollama primeiro = editar `cadeia.txt` (o servidor lê ao arrancar) — nada de código.

## Revisão 09:10 (02/09) — depois de os dois Gemini esgotarem a quota do dia (429)
Medido: qwen2.5:7b com o prompt compacto e reordenado (partes fixas primeiro) = 182 s a frio, 15 s
quente; qwen2.5:3b = 75 s a frio, 2,4 s quente, mas copia o exemplo do prompt e ignora a pergunta;
OpenCode Zen `nemotron-3-ultra-free` responde COM ferramentas (41 s) desde que o pedido se
identifique como browser (senão Cloudflare 403/1010); `hy3-free` já não existe ("not supported").
Ordem: **ollama (7b, mantido quente pelo aquecedor) → zen:nemotron-3-ultra-free → gemini-3.6-flash
→ gemini-3-flash-preview**. Custo zero em todos; o Gemini serve ~20 chamadas/dia por modelo.
