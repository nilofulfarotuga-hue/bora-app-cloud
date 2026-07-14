---
name: desbloqueio-zona-vermelha
category: hermes-agent
description: Quando o Danilo responde "vai <id>" no Telegram a um aviso de ordem em ZONA VERMELHA da fila de orquestração do Bora (dinheiro/pagamento, à espera de confirmação humana), esta skill move essa ordem de volta para a fila de execução normal. NÃO decide se a ordem é segura — só reage à confirmação explícita que o próprio Danilo já deu.
---

# Desbloqueio da fila de espera (zona vermelha) via "vai <id>"

> Este skill NÃO muda a regra de negócio: ordens que tocam dinheiro (Stripe/pricing/tokens/
> dispatch/wallet/ledger) continuam a exigir confirmação humana antes de correr — isso é
> intencional e fica como está. Este skill só torna essa confirmação de "um toque" em vez de
> exigir que o Danilo edite a página manualmente.

## Gatilho
Uma mensagem do Danilo no Telegram que corresponde ao padrão **`vai <id>`** (ex.: `vai
ordem-20260714153211-a1b2`), normalmente em resposta direta a um aviso anterior do formato:

```
🔴 Bora/orquestração: ordem <id> EM ESPERA (zona vermelha — toca dinheiro/pagamento).
Resumo: <resumo curto da tarefa>
Para libertar para a fila normal, responde aqui: vai <id>
```

Só reage a este padrão específico (`vai` + algo que parece um id de ordem, tipicamente começando
por `ordem-`). Um "vai" isolado, sem id, ou a falar de outra coisa (ex.: "o autocarro vai
chegar") **não** é este gatilho — ignora.

## Onde vive a fila
`/opt/data/cortex-brain/orquestracao/<id>.md` (= `/brain/orquestracao/<id>.md`). Cada ficheiro
tem campos `id:`, `estado:`, `tarefa:`, `nota:`, etc., um por linha (formato `campo: valor`).

## Fluxo de trabalho
1. **Extrai o id** da mensagem (tudo depois de `vai `, sem espaços). Se o id completo não bater
   certo com nenhum `<id>.md`, tenta encontrar UM ficheiro cujo campo `id:` **termine** nesse
   texto (aceita o Danilo colar só o sufixo, é mais rápido de escrever no Telemóvel). Se não
   encontrar exatamente um candidato, responde a dizer que não encontrou essa ordem (não
   adivinhes, não apliques a mais que uma ordem de cada vez).
2. **Lê o ficheiro** `orquestracao/<id>.md` e confere o campo `estado:`.
   - Se `estado: zona_vermelha` → é o caso normal, segue para o passo 3.
   - Se já for `estado: aberta|executando|respondida|aprovada` → já não está à espera; responde
     ao Danilo a dizer o estado atual, **não editas nada** (evita reabrir/duplicar trabalho).
   - Se for `estado: travada` → também não é para reabrir sozinho com um simples "vai" (uma
     ordem travada passou pelo teto de 5 tentativas ou timeout — precisa de mais contexto que
     "vai"); responde a explicar que está travada, não zona vermelha, e sugere reformular a
     ordem se for para tentar de novo.
3. **Edita o ficheiro**: muda a linha `estado: zona_vermelha` para `estado: aberta`, e limpa a
   linha `nota:` (fica `nota:` vazia — o registo de que passou por zona vermelha já ficou no
   `carteiro.log` do host, não precisa de repetir na ordem). Não mexas em mais nenhum campo
   (`tentativa`, `tarefa`, `missao`, `passo` ficam exatamente como estavam).
4. A escrita neste ficheiro já é suficiente — a campainha (inotify) do host acorda o carteiro
   sozinha assim que o ficheiro muda; não precisas (nem tens acesso) de tocar em nada no host.
5. **Confirma ao Danilo** em 1 linha curta, ex.: `✅ Ordem <id> libertada — volta à fila normal
   de execução.` Se dentro da mesma mensagem o Danilo mandou "vai" para mais do que um id,
   processa cada um pela sua vez e confirma todos numa lista curta.

## O que este skill NUNCA faz
- Nunca decide sozinho que uma ordem em zona vermelha pode avançar sem o "vai" explícito do
  Danilo — zero heurística, zero "isto parece seguro". A palavra "vai" É a decisão humana.
- Nunca edita a `tarefa:` da ordem (o texto que vai ser executado é exatamente o que já lá
  estava quando entrou em zona vermelha — não acrescentes nem resumas).
- Nunca cria ordens novas nem mexe no `_controlo.md` (kill switch) ou em ordens de outros ids.
- Se o ficheiro não existir, ou a fila estiver com `.pausa-total`/`orquestracao_enabled: false`,
  responde a informar em vez de forçar (a pausa/kill switch são decisões do Danilo, não anulas).

## Exemplo
Mensagem recebida: `vai ordem-20260714153211-a1b2`
1. Encontra `/opt/data/cortex-brain/orquestracao/ordem-20260714153211-a1b2.md`.
2. `estado: zona_vermelha` → confirma que é o caso.
3. Edita: `estado: zona_vermelha` → `estado: aberta`; `nota: 🔴 ZONA VERMELHA — ...` → `nota:`.
4. Responde: `✅ Ordem ordem-20260714153211-a1b2 libertada — volta à fila normal de execução.`

## Nota de origem
Criado 2026-07-14 (pedido: "melhorar o aviso das ordens que ficam em espera manual"). Fonte
canónica no git: `bora_app/.claude/.ai/hermes/orquestrador-carteiro/skill-desbloqueio-vai/`.
Deploy: copiar para `/opt/data/skills/hermes-agent/desbloqueio-zona-vermelha/` no VPS (mesmo
padrão de `hermes-operacao-confiavel`). Ver `../deploy/DEPLOY.md`.
