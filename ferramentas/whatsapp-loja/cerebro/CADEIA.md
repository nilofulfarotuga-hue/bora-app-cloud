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

## Ordem FINAL (09:45, 02/09) — por qualidade, com o custo zero em todos
`gemini-3.6-flash → gemini-3-flash-preview → zen:nemotron-3-ultra-free → ollama (qwen2.5:7b)`.
O 7b local responde depressa quando quente mas escreve pior: prometeu "vou verificar" com os dados
já na mão e colou um título do manual na resposta. Ficou de reserva, atrás de tudo o que é bom e
grátis; e as guardas em código (factos fixos, pedidos em resumo determinístico, títulos limpos,
número sem ferramenta = invenção) apanham o que ele escrever mal. Quando o Gemini está em 429 fica
marcado 10 min e a cadeia desce sozinha.

## Revisão 10:20–11:20 (02/09) — o Danilo mediu no banco: 57 s e 90 s por resposta
O Gemini 3.6 esgotou a quota do dia e a cadeia caiu no nemotron do Zen, que responde com ferramentas
mas leva 40–90 s por volta; com 2–3 voltas de ferramentas eram minutos. Ordem: **groq:llama-3.3-70b-versatile
(activa-se sozinho quando houver `GROQ_API_KEY` no `cerebro/.env`; sem chave salta em 0 ms) →
gemini-3.1-flash-lite (0,9 s medido, quota separada) → gemini-3-flash-preview → ollama (7b quente) →
zen:nemotron-3-ultra-free**. Tempos: 12 s Gemini/Groq, 25 s Ollama, 60 s Zen — quem não responde dá a vez.
E o agente passou a UMA chamada sem ferramentas (`agente._rapido`): o que precisa de dados verifica-se
antes, em código. Medido: 10 de 10 respostas em menos de 10 s (máx. 7,6 s). `CEREBRO_RAPIDO=0` volta ao
ciclo com ferramentas. Na VPS a cadeia vive em `Environment=CEREBRO_CADEIA` no serviço, não no ficheiro.
