# C5 — Stripe Connect fase 2 · 03 · "Roll secret" do webhook do Connect

Missão `final-app-2026-10-29`, Bloco 7 C5. Agente `pagamentos-wallet` (PROPOSE-ONLY).
**Isto é uma ação no painel da Stripe e não foi feita por mim**: não há sessão da Stripe em nenhum perfil do
navegador e a regra é não entrar em contas nem guardar senhas. Fica para o **Danilo** (parte da Stripe) e para a
**Claude.ai** (parte do Supabase e a prova). Tempo: 5 a 10 minutos. **Não pára nenhum evento** se for feito pela ordem abaixo.

## 0. Em seis passos (para o Danilo)

1. Abrir o painel da Stripe, **em modo real** (o interruptor "Modo de teste" desligado), conta "bora app".
2. Ir a **Desenvolvedores → Webhooks** (ou **Workbench → Webhooks**) e abrir o destino cujo endereço termina em `/functions/v1/stripe-connect-webhook` (id `we_1U1ROvGlT3R2jCYpG8qnQ1zW`, escopo "contas conectadas").
3. Na secção do **segredo de assinatura**, escolher **"Roll secret"**, e na pergunta de quando expira o segredo antigo escolher **"daqui a 1 hora"** (ou 24 horas), **nunca "agora"**.
4. Copiar o segredo novo (começa por `whsec`). **Não o colar no chat.**
5. Colá-lo no Supabase, projeto `ojykpzwqrtusfeakzrna`, em **Edge Functions → Secrets**, no secret com o nome exato **`STRIPE_CONNECT_WEBHOOK_SECRET`** (substituir o valor).
6. Avisar a Claude.ai: ela faz a prova (secção 5) e regista.

## 1. Porquê

- A 06/08 o segredo de assinatura do webhook do Connect passou pelo chat (registado no relatório da fase 1 e na página `livro-areas-stripe-connect` do livro). Quem o conhecesse podia **assinar eventos falsos** e a função `stripe-connect-webhook` aceitá-los.
- Efeito hoje: um `account.updated` falso poderia mudar o estado espelhado de uma conta (`apply_stripe_account_update`) — por exemplo marcá-la como "pronta" ou "desativada". Não move dinheiro.
- Efeito com a fase 2: o estado "pronta" passa a contar para a elegibilidade de um pagamento. A função de transferência proposta confirma sempre a conta na própria Stripe antes de enviar (`accounts.retrieve`, capacidade `transfers` ativa) e o destino vem do banco, nunca do evento; mesmo assim convém **fechar o assunto antes de ligar dinheiro**.
- O `supabase secrets list` mostra só uma impressão digital (hash) do segredo, não o valor: a fuga foi pelo chat, não por esse comando.

## 2. O que é e o que não é

| Item | Valor |
|---|---|
| Endpoint a rodar | Webhook do **Connect**, modo real, id `we_1U1ROvGlT3R2jCYpG8qnQ1zW`, API `2026-02-25.clover`, escopo "contas conectadas" |
| URL | `https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/stripe-connect-webhook` |
| Eventos | `account.updated`, `account.application.deauthorized`, `payout.paid`, `payout.failed` |
| Função que o recebe | `stripe-connect-webhook` (id `dd450803-0daa-4041-8616-ab81c64c12c1`, versão 3, `verify_jwt=false`) |
| **Secret do Supabase a atualizar (só o nome)** | **`STRIPE_CONNECT_WEBHOOK_SECRET`** (lido em `supabase/functions/stripe-connect-webhook/index.ts:36`) |
| **NÃO mexer** | O webhook dos pagamentos (`/functions/v1/stripe-webhook`, secret `STRIPE_WEBHOOK_SECRET`, zona protegida) e qualquer webhook em **Modo de teste** (têm segredos próprios) |

Cuidado de leitura: nos ids da Stripe da Bora o "Gl" é **G + L minúsculo** (não "GI"). Em caso de dúvida, escolher o destino pelo **endereço**, não pelo id.

## 3. Passo a passo no painel da Stripe (Danilo)

Os nomes dos botões podem variar ligeiramente (não consegui abrir o painel; descrevo pelo que a Stripe documenta e pelo guia de 06/08).

1. https://dashboard.stripe.com — se pedir entrada, é o Danilo a entrar (a conta está no nome dele). Confirmar no canto superior que o **Modo de teste está desligado** e que a conta é a "bora app".
2. Menu **Desenvolvedores → Webhooks** (se o painel tiver o "Workbench": **Workbench → separador Webhooks**). Aparecem dois destinos reais: o dos pagamentos e o do Connect. **Abrir o que termina em `stripe-connect-webhook`.**
3. Na página do destino, secção **Segredo de assinatura** (ao lado do botão "Revelar"): abrir o menu "⋯" ou o botão **Roll secret** (em português pode aparecer como "Girar/Regenerar segredo").
4. Na janela que abre, **"Expirar o segredo antigo"**: escolher **1 hora** (ou 24 h). Durante esse prazo a Stripe assina cada evento com **os dois** segredos (cabeçalho com duas assinaturas `v1`); a função aceita o evento se **uma** bater com o segredo que o Supabase tiver. Por isso, durante a troca, nada falha.
5. Confirmar. Carregar em **Revelar** e copiar o segredo novo (`whsec...`). Não o enviar por chat, email, nem escrever em ficheiros do repo.

## 4. Passo no Supabase (Danilo ou Claude.ai)

Escolher **uma** das duas opções (a segunda evita o segredo aparecer no ecrã e no histórico):

- **Painel:** projeto `ojykpzwqrtusfeakzrna` → **Edge Functions → Secrets** → secret `STRIPE_CONNECT_WEBHOOK_SECRET` → editar → colar o valor novo → guardar.
- **Linha de comandos (PC do Danilo):** `C:\supabase\supabase.exe secrets set` com o nome `STRIPE_CONNECT_WEBHOOK_SECRET` e o valor tirado da **área de transferência** (ler com `Get-Clipboard` para uma variável e passar essa variável ao comando, sem escrever o valor), `--project-ref ojykpzwqrtusfeakzrna`. (O `npx supabase` não tem binário para Windows x64: usar o executável acima, como na fase 1.) Depois limpar a área de transferência.

Efeito esperado: a função passa a ler o valor novo logo (lê `Deno.env.get` dentro do pedido, `index.ts:36`). **Plano B** se, passados 2 minutos, ainda houver respostas 400 com o segredo novo: voltar a publicar a **mesma** versão da função (`supabase functions deploy stripe-connect-webhook` com `--no-verify-jwt`, ficheiro do repo; este slug não está na lista de funções protegidas). Em 06/08 a função só passou a 200 numa versão nova (v2) depois de o segredo ser gravado; não consegui provar se foi coincidência ou necessidade.

## 5. Como provar que funcionou (só leitura; Claude.ai)

A função verifica a assinatura **antes** de qualquer escrita (`index.ts:46`), e só depois grava o evento; um evento repetido devolve `200` com `duplicate:true` (`index.ts:68-70`). Isso dá uma prova sem alterar nada:

1. **Antes de tocar em nada**, anotar: `SELECT count(*), max(received_at) FROM stripe_connect_events;` (hoje: 30 eventos, o último a 28/09/2026 15:23 UTC).
2. Depois de gravar o segredo novo no Supabase, na Stripe: abrir o destino → **Eventos / Tentativas de entrega** → escolher um evento `account.updated` antigo → **Reenviar** (resend). Esperado na Stripe: resposta **200** com o corpo `{"received":true,"duplicate":true}`.
3. Nos registos da função (MCP, só leitura), consulta:

```sql
select m.function_id, response.status_code, function_edge_logs.timestamp, event_message
from function_edge_logs
cross join unnest(metadata) as m
cross join unnest(m.response) as response
where m.function_id = 'dd450803-0daa-4041-8616-ab81c64c12c1'
order by function_edge_logs.timestamp desc
limit 20
```

   Esperado: pedidos `POST` a **200** depois da hora da troca, linha de log `duplicate event ignored`, **nenhum 400** (um 400 é "Webhook signature error" = segredo errado).
4. `SELECT count(*), max(received_at) FROM stripe_connect_events;` → **igual ao passo 1** (o reenvio não cria linha nova; prova que o 200 foi do ramo "duplicado", ou seja, a assinatura passou).
5. **Controlo negativo (opcional, só se houver dúvida):** um pedido sem assinatura devolve 400 `Missing stripe-signature or connect webhook secret` (`index.ts:40`); já foi provado a 06/08.
6. Passado o prazo de expiração do segredo antigo (1 h ou 24 h), **repetir os passos 2–4 uma vez**: continua 200. Só aí o assunto fica fechado.
7. Um evento **real** fecha o ciclo: o próximo `account.updated` verdadeiro (por exemplo quando um parceiro novo acabar o cadastro) deve aparecer como linha nova em `stripe_connect_events` e mudar o estado da conta; qualquer `payout.paid`/`payout.failed` de parceiros só chegará depois da fase 2.

Registos: uma linha no `e2e_log` (fluxo `final-app-2026-10-29`, passo `7.C5-roll-secret`, estado `ok`, com a hora e a contagem de eventos antes/depois) e uma nota no Córtex a dizer "Roll secret do webhook Connect feito a <data>; segredo antigo expirou a <data>". Nunca o valor.

## 6. Se algo correr mal

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| 400 "Webhook signature error" depois de gravar o segredo | Valor colado com espaço/linha a mais, ou copiado o segredo do destino errado (o dos pagamentos, ou o de Modo de teste) | Voltar a copiar do destino certo (endereço `stripe-connect-webhook`, modo real) e regravar; **durante o prazo de expiração o segredo antigo ainda é válido**, por isso pode-se até repor o antigo no Supabase enquanto se corrige |
| 400 só depois de o segredo antigo expirar | O Supabase ainda tem o segredo antigo | Gravar o novo (passo 4) e reenviar os eventos falhados a partir da Stripe |
| Eventos perdidos | Nenhuns: a Stripe repete as entregas falhadas durante dias, e a função apaga o registo de idempotência quando o tratamento falha, para poder reentregar | Reenviar manualmente na Stripe os eventos que ficaram em erro |
| Rolou o destino errado | Rolar o segredo do webhook dos pagamentos quebraria a confirmação de pagamentos | **Parar**, repor o valor antigo enquanto o prazo de expiração corre (por isso nunca escolher "agora") e avisar a Claude.ai |

## 7. O que NÃO fazer

- Não rolar o segredo do destino dos pagamentos (`stripe-webhook`): é zona protegida.
- Não escolher "expirar agora": cortaria a entrega até o Supabase ser atualizado.
- Não usar o mesmo nome de secret para o webhook de Modo de teste: o guia antigo (`GUIA_DANILO_STRIPE_CONNECT.md:97-98`) sugere trocar o valor de `STRIPE_CONNECT_WEBHOOK_SECRET` durante os testes; isso cortaria o webhook real. Para a fase 2 os testes não precisam de webhook (a transferência é síncrona); se um dia forem precisos, criar um secret com outro nome.
- Não colar o segredo em chat, email, `.env` do repo nem relatórios.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO — à espera de autorizo. (Ação no painel da Stripe: só o Danilo; nada foi feito por mim.)
