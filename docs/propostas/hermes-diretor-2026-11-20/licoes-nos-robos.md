# Lições dos robôs: o que falta ligar (missão hermes-diretor-2026-11-20, bloco B6)

Estado conferido a 22/11/2026 por leitura (`get_edge_function` + `git grep` nos commits fixos). Nada foi editado nem publicado.

## Quem lê `licoes_robos` hoje

| Robô | Onde corre | Lê as lições? | Prova |
|---|---|---|---|
| Suporte | Edge Function `support-chatbot` v41 | NÃO | O código no ar é só `import` do commit `bd38e3c3` (index.ts, 82 561 bytes). `git grep -i licoes_robo bd38e3c3 -- supabase/functions/support-chatbot supabase/functions/_shared` sem resultados. No ramo atual também nada. |
| Amigo Bora | Edge Function `client-assistant` v27 | NÃO | Código no ar = `import` do commit `a9b4980d` (index.ts, 134 311 bytes). `git grep -i licoes_robo a9b4980d -- supabase/functions/client-assistant` sem resultados. No ramo atual também nada. |
| WhatsApp | Não existe Edge Function: nenhum slug com whatsapp/cerebro/waha entre as 118 funções. Corre fora do Supabase (VPS, Hermes/WAHA) | NÃO PODE SER VERIFICADO aqui | Não tenho ssh nem acesso ao código da VPS. O Hermes tem de chamar `licoes_robo_texto('whatsapp')` (ver 3.) |

O repo e o ar estão em sincronia nestas duas funções: as shims do ar apontam a commits fixos, e o ramo atual não tem diferença de conteúdo nelas quanto a lições. Como o ar é uma shim, a mudança tem de ir para o repo, num commit novo, e a shim ser republicada a apontar a esse commit (quem publica é a Claude.ai).

Já existe leitura de conhecimento aprendido no Amigo e no Suporte (`assistant_learned`, `assistant_knowledge`, RAG), mas é outra tabela. `licoes_robos` fica sem leitor até isto entrar.

## Remendo mínimo (igual nos dois)

A RPC `public.licoes_robo_texto(p_robo, p_max)` só aceita `service_role`, por isso chama-se com o `adminClient` que as duas funções já têm. Cache de 5 minutos em memória (por instância; chega, o corte de custo vem de não ir à base de dados em cada mensagem). Se a RPC falhar, devolve o último valor bom ou vazio: o robô nunca pode parar por causa disto.

Colar uma vez em cada `index.ts`, perto das outras funções auxiliares:

```ts
// B6 (hermes-diretor-2026-11-20): lições dos robôs, com cache de 5 min em memória.
const LICOES_TTL_MS = 5 * 60 * 1000;
const licoesCache = new Map<string, { texto: string; em: number }>();
async function licoesDoRobo(adminClient: ReturnType<typeof createClient>, robo: string): Promise<string> {
  const c = licoesCache.get(robo);
  if (c && Date.now() - c.em < LICOES_TTL_MS) return c.texto;
  try {
    const { data, error } = await adminClient.rpc('licoes_robo_texto', { p_robo: robo, p_max: 2500 });
    if (error) throw error;
    const texto = typeof data === 'string' ? data : '';
    licoesCache.set(robo, { texto, em: Date.now() });
    return texto;
  } catch (_e) {
    return c?.texto ?? '';   // falhou: usa a última boa, ou nada
  }
}
const blocoLicoes = (t: string) =>
  t ? '\n\nLIÇÕES APRENDIDAS (correções reais; têm prioridade sobre o resto do conhecimento):\n' + t : '';
```

### support-chatbot (`index.ts` do commit `bd38e3c3`, linha ~1137)

Antes:
```ts
const systemPrompt = comTvde(buildSystemPrompt(userRole, emFoco, settings, skillsMd, ragContext));
```
Depois:
```ts
const licoesTxt = await licoesDoRobo(adminClient, 'suporte');
const systemPrompt = comTvde(buildSystemPrompt(userRole, emFoco, settings, skillsMd, ragContext)) + blocoLicoes(licoesTxt);
```
O `adminClient` já existe nesse ponto (criado na linha ~1009). Juntar depois do `comTvde` para o filtro do Bora Motorista continuar a atuar só sobre o texto original.

### client-assistant (`index.ts` do commit `a9b4980d`, linha ~1015)

Antes:
```ts
const systemPrompt = (s.pesquisaWeb ? buildSystemFixo(s.personality, false) : systemFixo) + '\n' + systemContexto;
```
Depois:
```ts
const licoesTxt = await licoesDoRobo(adminClient, 'amigo');
const systemPrompt = (s.pesquisaWeb ? buildSystemFixo(s.personality, false) : systemFixo) + '\n' + systemContexto + blocoLicoes(licoesTxt);
```
`adminClient` existe (linha ~803). O bloco entra no fim do contexto (parte variável), por isso não parte o prefixo fixo que o `systemFixo` mantém igual entre pedidos (cache do prompt).

### WhatsApp (Hermes, VPS)

Onde o Hermes monta o prompt do atendimento WhatsApp, fazer um `POST /rest/v1/rpc/licoes_robo_texto` com a chave de serviço e o corpo `{"p_robo":"whatsapp","p_max":2500}`, guardar o resultado 5 minutos e juntar `blocoLicoes(...)` ao fim do prompt de sistema. O texto vem pronto, uma regra por linha ("- regra"), sem dados pessoais.

## Portão "se piorar, não publica"

`public.robos_regressao_resumo(p_robo)` devolve `pode_publicar=false` se algum caso de teste ativo do robô falhou na última corrida. Cada publicação de uma das funções acima deve correr os casos (`robos_casos_teste`), gravar com `robo_caso_resultado` e só depois consultar este resumo.

## Os 471 trechos de "notas internas de programação"

Ver o relatório final: o conhecimento do Suporte tem hoje 637 trechos (471 `obsidian`, 97 `knowledge`, 37 `business_rules`, 32 `ajuda`). Os 471 de `obsidian` NÃO saíram da tabela. O que os impede de chegar ao robô é o filtro `public._conhecimento_para_clientes(...)` dentro de `match_knowledge`, que deixa passar 4 dos 471 (e 2 de `business_rules`, 0 de `knowledge`, 32 de `ajuda`).
