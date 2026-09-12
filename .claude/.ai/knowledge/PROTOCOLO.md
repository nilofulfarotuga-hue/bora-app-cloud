---
tema: protocolo-cerebro · escopo: projeto · estado: atual · atualizado: 2026-07-01
---

# 📓 PROTOCOLO — Como os agentes usam o Cérebro

> Escrita de memória é **operação de primeira classe**, com gatilho explícito (fim de tarefa).
> Não é "o modelo decide sozinho o que lembrar".

## ANTES de trabalhar (ciclo de leitura)
1. Ler `INDEX.md` (este é o único ficheiro que se lê "sempre").
2. Identificar o(s) tema(s) da tarefa e carregar **só** esses ficheiros.
   - Ex.: mexer no Supabase → `semantica/backend-map.md` + `semantica/zonas-protegidas.md`.
   - Ex.: corrigir um bug → `episodica/bugs-resolvidos.md` (não re-corrigir o já corrigido).
3. Verificar **frescura**: aplicar só factos `estado: atual`. Se um facto `superado` parecer
   relevante, seguir o que o substituiu.
4. **Nunca** carregar o Cérebro inteiro (rebenta o context window — foi o problema do MEMORY.md 45KB).

## DEPOIS de terminar (ciclo de escrita)
1. O agente **NÃO escreve** direto no Cérebro. Reúne o que aprendeu num bloco de handoff:
   ```
   HANDOFF → bibliotecario-cerebro
   tipo: licao | bug | decisao | facto
   escopo: projeto | agente:<nome>
   tema-alvo: <ficheiro sugerido>
   conteudo: <o facto, apoiado no que aconteceu — com commit/data/entidade>
   ```
2. Entrega o handoff ao agente **`bibliotecario-cerebro`** (o único que escreve).
3. O Bibliotecário **verifica** (8-checagens), faz dedup, marca `superado` se contradizer,
   grava no sítio certo e atualiza o `INDEX.md` se criar/partir ficheiro.

## Memória de trabalho (efémera)
- `sessao/` guarda checkpoints da tarefa em curso (dogfooding). É **gitignored** e apagável.
- Progresso de tarefas longas escreve-se aqui para sobreviver a um relançamento.

## Regras duras
- Índice e cada ficheiro **< ~24 KB** (limite de leitura). Passou → partir por sub-tema.
- **Zero perda**: nada sai do Cérebro sem ir para `_arquivo/` + entrada no mapa de migração.
- **História não se apaga**: um facto errado marca-se `superado (por X, data)`, não se remove.
