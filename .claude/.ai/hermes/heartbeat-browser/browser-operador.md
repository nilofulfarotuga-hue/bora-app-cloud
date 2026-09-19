# browser-operador — a ponte que fecha o loop SEM API paga

**Dono do loop `heartbeat-browser` (🟢 Core).** O browser-operador é o agente que
**já clica** — Claude in Chrome, extensão instalada (`claude --chrome`), pareado
com a **sessão Pro do Danilo** no `claude.ai`. É ele que devolve o resultado ao
Claude.ai sem custo de API: em vez de chamar a API paga, **abre um chat e escreve**.

## Como funciona (2 peças)

1. **Gatilho + anti-spam** — `.claude/scripts/heartbeat-browser.py` (cron/schtask
   `*/10`). Deteta mudança REAL de estado (ordem em estado final, teste novo) e só
   nesse caso escreve `pending.trigger`. Sem mudança → silêncio (nunca chats vazios).
2. **Ação (esta spec)** — o browser-operador vê `pending.trigger` e executa os passos
   abaixo. Sem `pending.trigger` → não faz nada.

## Passos do browser-operador (quando existe `pending.trigger`)

1. **Conta certa (regra dos 2 browsers).** O PC tem 2 browsers/perfis abertos. Usar
   **aquele que tem a sessão do Danilo logada no `claude.ai`** (Pro ativa) — NÃO o
   perfil de scraping/testes. Confirmar antes de escrever: a barra lateral do
   `claude.ai` mostra a conta do Danilo. Se nenhum tiver sessão → **não inventar
   login**; abortar e deixar o `pending.trigger` para a próxima ronda (a regra do
   HERMES_CHROME.md: nunca fazer login em contas sem aprovação).
2. **Chat NOVO** (não reusar o chat longo do Danilo — pode travar e é menos seguro):
   abrir `https://claude.ai/new`.
3. **Colar a FRASE FIXA** (vem em `pending.trigger` no campo `frase`, verbatim):

   > Bora Loop automatico: puxa o contexto do Bora pela tua memoria e Cortex,
   > verifica o estado das ordens (cortex_ler) e dos testes (SELECT em orders e
   > e2e_log no Supabase), e age no que for preciso - dispara a proxima ordem se
   > algo travou ou ficou incompleto, ou responde que esta tudo ok se nao ha nada
   > pendente. So avisa o Danilo se for importante ou decisao de dinheiro.

4. **Enviar** (Enter) e **fechar**. Não é preciso ler a resposta — o Claude.ai age
   sozinho a partir daí (tem os seus próprios guardrails: Trava, Juiz, kill switch).
5. **Marcar consumido:** mover `pending.trigger` para `consumidos/consumido-<ISO>.trigger`
   (assim o próximo `*/10` não reabre outro chat pela mesma mudança — anti-spam de 2ª camada).

## Anti-spam (2 camadas)

- **Camada 1 (script):** só escreve `pending.trigger` quando o watermark avança.
- **Camada 2 (operador):** consome o trigger (move para `consumidos/`) após enviar.
  Enquanto houver `pending.trigger` por consumir, não abrir 2º chat.

## Segurança

- Frase benigna, read-only do lado do gatilho. O que o Claude.ai fizer depois passa
  pelas 5 paredes do envelope (Trava/Juiz/tetos/humano-acima-do-L1/kill switch).
- **Nunca** criar conta, nunca fazer login sem sessão já ativa, nunca colar segredos.
- Reversível: apagar o schtask/cron desliga o gatilho; apagar esta pasta apaga o estado.
