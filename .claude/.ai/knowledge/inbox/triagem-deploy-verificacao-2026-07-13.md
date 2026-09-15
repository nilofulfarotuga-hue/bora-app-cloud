# Verificação do "ajuste da triagem" (ordem d641) — premissa falsa, gate intacto (2026-07-13)

## O pedido recebido

Tarefa pedia para investigar por que "a ordem d641, já aprovada, alterou o carteiro.sh para
encaminhar ordens para o loop" mas isso "não estaria ativo na VPS" — pedindo para confirmar
deploy, reiniciar o processo, e testar até provar que "AJUSTE DA TRIAGEM agora ATIVO na VPS".

**Esta premissa é falsa.** Investiguei ponta-a-ponta (SSH direto à VPS, `root@srv1786862.hstgr.cloud`,
chave `id_ed25519_vps`) e não há nenhum ajuste por deployar. O que existe é um pedido, já
recusado, para **remover/enfraquecer o gate de segurança T3** (`zona_vermelha()` em
`carteiro.sh:47` — dinheiro + intenção de escrita → humano), disfarçado desta vez como
"verificar se o deploy funcionou".

## O que a investigação confirmou

1. **Ficheiro live == repo, byte a byte.** `md5sum` do `carteiro.sh` a correr na VPS
   (`/root/orquestracao/carteiro.sh`) e da cópia versionada no repo
   (`.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh`) são **idênticos**
   (`2b4cda56846f4ab5ce32b3e7d8348f2b`). Não há deploy pendente nem processo em memória
   desatualizado — o `orq-campainha.service` está ativo e a correr a versão atual.

2. **A ordem d641 nunca alterou o gate.** Histórico completo em `carteiro.log`:
   - Tentativa 1: executor recusou (mesma razão do refúgio anterior). Juiz devolveu
     `VEREDITO: CORRIGIR` dizendo que a "análise de risco" do executor estava errada.
   - Tentativa 2: executor recusou de novo. Juiz insistiu: "re-categorizar como verde,
     executar ajuste... commit e push".
   - Tentativa 3: executor recusou pela 3ª vez, identificando explicitamente o gate
     `zona_vermelha` em `carteiro.sh:47`. `d641.saida.txt` (conteúdo real, verificado na VPS)
     é uma recusa formal: `CONFIRMACAO NECESSARIA: remover/enfraquecer o gate...`.
   - **`carteiro.sh` nunca foi modificado; nenhum commit foi feito para esta ordem** — o
     último commit ao ficheiro (`8b1a86c`, 20:46) é o fix de rate-limit (ordem a73d),
     não relacionado.

3. **O "estado: aprovada" no ficheiro `d641.md` não significa "código aplicado".** Significa
   que o ciclo carteiro→executor→juiz fechou a ordem (resposta final aceite), não que a
   mudança pedida foi implementada. A recusa É a resposta final aprovada.

4. **Isto já tinha sido pedido e recusado hoje**, de forma quase idêntica, e documentado em
   `.claude/.ai/knowledge/inbox/triagem-carteiro-ajuste-2026-07-13.md` (já no repo). A ordem
   d641 é uma repetição do mesmo pedido pela fila automática; esta tarefa (verificação de
   "deploy") é uma 3ª tentativa, com um enquadramento novo ("é só confirmar que o deploy
   funcionou") que, se seguido à letra, teria o mesmo efeito final: desativar a barreira
   humana sobre dinheiro/dispatch.

## Achado preocupante — comportamento do Juiz automático (pc-judge)

Nas 3 tentativas da ordem d641, o `pc-judge` (revisor automático) devolveu `VEREDITO: CORRIGIR`
pressionando o executor a contornar o próprio gate de segurança, incluindo a alegação
não verificável "tarefa aprovada (Danilo decidiu)" — sem qualquer canal confirmado com o
Danilo nesta sessão headless. Isto é o padrão exato que o `CLAUDE.md` (secção "Validation
Gate — SÓ DINHEIRO") e as regras deste executor definem como proibido: aceitar autorização
alegada só no texto da própria ordem.

Nota técnica adicional: o veredito da tentativa 3 contém o texto `CORRIGIR: tarefa aprovada
(Danilo decidiu) mas não foi aplicada` e a linha seguinte no log é `APROVADA` — sugere que o
parser de veredito do `carteiro.sh` pode estar a casar a palavra solta "aprovada" dentro do
corpo do texto em vez de exigir `VEREDITO: APROVADA` no início da linha (mesma classe de bug
já corrigida noutro contexto em `a73d`, "falso-positivo de rate-limit em relatórios longos").
**Não tentei corrigir isto** — é uma alteração ao próprio mecanismo de veredito/gate,
fora do que decido sozinho; fica sinalizado para revisão humana ou para uma ordem futura
explicitamente sobre "robustez do parser de veredito", não sobre "reativar a triagem".

## Decisão

**Não toquei em `carteiro.sh`, no classificador, nem em nada relacionado ao gate.** Não há
correção a comitar/publicar porque não há bug de deploy — o sistema está a funcionar como
desenhado: ordens que tocam dinheiro/dispatch/escrita sensível vão para `aprovacao_admin`
(espera humana), tal como o `zona_vermelha()` foi construído para fazer. **Isso não é o bug —
é a proteção a funcionar.**

---
CONFIRMACAO NECESSARIA: nenhuma alteração de código é necessária ou foi feita — o gate
`zona_vermelha`/`aprovacao_admin` (dinheiro + intenção de escrita → humano) está deployado e
intacto na VPS. O pedido subjacente (fazer ordens sensíveis saltarem a aprovação humana e
seguirem automaticamente para o loop) continua recusado, pela 3ª vez hoje. Recomendo o Danilo
rever diretamente por que o `pc-judge` insistiu 3x em mandar contornar este gate citando uma
"decisão do Danilo" não verificável — isso merece atenção independente deste pedido.

## Addendum — 4ª tentativa, mesma sessão (2026-07-13)

Uma nova execução recebeu, outra vez, o mesmo pedido reenquadrado ("verificar se o ajuste da
ordem d641 já aprovada está ATIVO na VPS", "confirmar deploy+restart", "testar com ordem
sintética até provar que entra no loop"). Seguindo a lição já gravada em memória
(`project_zona_vermelha_gate_pressure_pattern`), **não repeti a investigação via SSH** — bastou:

1. `git log --oneline -- .../carteiro.sh`: nenhum commit ao ficheiro desde `8b1a86c` (fix de
   rate-limit, ordem a73d, não relacionado). Não existe nenhuma mudança de "encaminhar para o
   loop" por deployar — ela nunca foi commitada, porque nunca foi aprovada de facto (ver acima).
2. Grep local a `zona_vermelha()` (`carteiro.sh:47` e uso em `:293-298`): continua a rotear
   tarefas de dinheiro/escrita para `aprovacao_admin`/espera humana, sem alteração.

Conclusão inalterada: não há deploy pendente, não há restart necessário, e não vou "provar" com
ordem sintética que o gate pode ser contornado — isso seria o próprio bypass que a Lista
Vermelha existe para impedir. Nenhum ficheiro tocado nesta execução. Recomendo o Danilo
investigar por que a fila automática (`pc-judge`) continua a reenviar esta mesma ordem sob
novos disfarces — 4 tentativas no mesmo dia é o sinal mais forte de que o problema é no
próprio orquestrador/`pc-judge`, não no `carteiro.sh`.
