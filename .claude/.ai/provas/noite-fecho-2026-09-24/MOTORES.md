# MOTORES — quem decide, e como se liga um motor novo

> Escrito 2026-09-25, missão `noite-fecho-2026-09-24`. Acompanha o `MOTORES.json`, que é a
> cascata que o `delegar.ps1` lê. Este ficheiro explica em palavras o que lá está em JSON, e
> em particular **como se liga o Jev quando a chave chegar**.

## O decisor do Bora, em duas linhas

Há uma Edge Function chamada **`decidir`** no Supabase do Bora. Recebe uma pergunta fechada
(sim/não, escolha, ou nota numa escala) mais o estado, e devolve resposta, confiança e
probabilidades. Grava cada decisão na tabela **`decisoes`**, com o motor que respondeu, o
modelo, a latência e se houve erro.

Serve para responder depressa a perguntas pequenas e repetidas — vale a pena abrir esta
sugestão? esta conversa devia passar a um humano? — sem gastar um modelo grande.

## Os motores, pela ordem em que são tentados

| Ordem | Motor | Quando responde |
|---|---|---|
| 1 | **Jev** (TypeSafe) | só quando houver chave. Hoje **não há** |
| 2 | **Gemini** | `gemini-3.6-flash` → `gemini-3.5-flash-lite` → `gemini-3.1-flash-lite` |
| 3 | **regra determinística** | quando nenhum modelo responde: devolve o que o sistema já fazia antes de existir decisor, e grava com `motor='fallback'` |

**8 segundos por modelo, uma tentativa cada.** Se o Google responder 429 (cheio), 503
(indisponível) ou 404 (modelo que já não existe), passa-se imediatamente ao seguinte. Isto
mudou a 25/09: antes esperava 20 segundos e repetia o mesmo modelo, e por isso 19 de 20
provas de 23/09 ficaram sem motor nenhum.

## Como ligar o Jev quando a chave chegar

É **uma linha**. A chave vai para o cofre do Supabase, e mais nada muda — a Edge já a procura
lá sozinha:

```sql
select vault.create_secret('<a chave do TypeSafe>', 'typesafe_api_key',
  'Chave do Jev (TypeSafe) para a Edge decidir');
```

Se já existir e for para substituir:

```sql
select vault.update_secret(
  (select id from vault.secrets where name = 'typesafe_api_key'),
  '<a chave nova>');
```

Para confirmar que pegou, sem olhar para a chave:

```sql
select public.decidir_sombra('<chave do hermes>', 'hermes-prova',
  'Is this a test?', '{"texto":"ligar o jev"}'::jsonb);
-- e depois:
select motor, modelo, erro from public.decisoes
 where usado_por = 'hermes-prova' order by quando desc limit 1;
```

Enquanto não houver chave, cada decisão traz `erro = 'jev_sem_chave'` e o Gemini responde —
o sistema **não pára** por falta do Jev. A 24/09 o registo no TypeSafe estava fechado
(`signups_disabled`), por isso não há chave para criar sozinho: tem de vir deles.

## O Hermes a perguntar em sombra (VPS)

A VPS **não** tem a chave de serviço do Supabase, e não devia ter: essa chave lê e escreve
tudo. Em vez disso há uma porta estreita:

- **`public.decidir_sombra(chave, usado_por, pergunta, estado, criterios, contexto_id)`** —
  valida uma chave só do Hermes (`hermes_decisor_key` no cofre) e faz a chamada por dentro,
  com a chave de serviço a nunca sair da base. Só aceita `usado_por` começado por `hermes-`.
- Na VPS: **`/opt/data/ferramentas/decidir.py`**, com `HERMES_DECISOR_KEY` no `/opt/data/.env`.
- Ligada em **sombra** em dois sítios, que só gravam e não mudam comportamento:
  - `rotinas/emerson.py` — o Porteiro do Telegram (isto devia interromper o Danilo agora?);
  - `rotinas/despachante.py` — a escolha do agente (o agente escolhido é o certo?).

Ver as sombras:

```sql
select quando, usado_por, motor, resposta, confianca, latencia_ms
  from public.decisoes where usado_por like 'hermes-%' order by quando desc limit 20;
```

## Aviso honesto sobre a qualidade, a 25/09/2026

O decisor **responde sempre e depressa** (20 de 20 provas, ~800 ms), mas **acerta mal**: 5 em
10 nas sugestões do Robot B e 2 em 6 no suporte, porque responde "não" a quase tudo. A
confiança separa bem (0,61 quando acerta, 0,28 quando falha), o que aponta para o corte e não
para a leitura. **Por isso está em sombra.** Não se liga nada disto a decidir de verdade sem
alguém olhar para o corte primeiro.
