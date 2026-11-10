# Para a Claude.ai publicar — missão fecho-contabilista-2026-11-10

> NÃO colar como missão. É a lista de publicação do ramo `ai/2026-11-10-fecho-contabilista`.
> Feito e testado pelo Claude Code a 10/11/2026. A bora-tranca desta sessão nega migration/DDL,
> deploy de Edge e envio fora de `ai/` ("publica o Claude.ai"), por isso nada disto foi aplicado.
> Ordem do Danilo (10/11/2026, literal): "Eu quero que você arrume um sistema aí. O que vai pro
> estafeta, o que vai pro parceiro, o que vai pro contabilista... O sistema tem que estar ótimo, sem
> erro." e "eu autorizo você arrumar o envio aí por WhatsApp também, o fecho mensal".
> Nada aqui muda preços, comissões, ganhos nem cobra nada a ninguém.

## Ordem (cada passo com a prova a fazer logo a seguir)

1. **URGENTE — segurança.** Aplicar `02_seguranca_guarda_current_user.sql` (remendo por âncora em
   `stripe_extrato_resumo` e `stripe_extrato_cruzar_base`). Hoje qualquer utilizador com sessão na app
   lê o resumo da Stripe (provado a 10/11 com `set local role authenticated` e uid inventado).
   Prova: o bloco comentado no fim do ficheiro tem de dar exceção da guarda.
2. **A migração do fecho.** Aplicar `01_fecho_contabilista_regras_hugo.sql` e gravar o mesmo texto em
   `supabase/migrations/20261110163000_fecho_contabilista_regras_hugo_2026_11_10.sql`. Substitui também
   `fecho_mensal_prestadores` (tinha o mesmo defeito de segurança — devolvia NIF, email e ganhos dos
   estafetas a qualquer pessoa com sessão). Provas (como `postgres`, ou com
   `set_config('request.jwt.claims','{"role":"service_role"}',true)`):
   - `select (public.admin_monthly_closeout(2026,10))->'para_as_financas'->'faturas_recibo'` → UMA linha
     "Consumidor final" de 159,17;
   - `select (public.admin_monthly_closeout(2026,10))->'para_as_financas'->'rubricas'` → tokens_descontados
     -3,29, margem_nao_parceiros 31,42, comissao_lojas_parceiras 3,59, ajustes 0;
   - `select (public.admin_monthly_closeout(2026,11))->'entidade'` → sociedade 519686233;
   - `select public.admin_fecho_contabilista(2026,10)->>'texto'` → o texto do contabilista (total 159,17 €);
   - `select public.admin_prestadores_dados_fiscais()->'com_falta'` (7 a 10/11);
   - `select count(*) from promo_code_uses where tokens_origem is not null` (38 a 10/11);
   - como utilizador comum (`set local role authenticated` + jwt com sub inventado):
     `fecho_mensal_prestadores(2026,10)`, `admin_prestadores_dados_fiscais()` e
     `admin_fecho_contabilista(2026,10)` → `admin_required`.
3. **NIF.** Aplicar `03_nif_sem_ramo_bora.sql` (tira o ramo morto "talão com o NIF da Bora" de
   `driver_order_invoice_nif`). Prova: num pedido sem NIF do cliente devolve `mostrar=false`.
4. **Edge Functions** (deste ramo, `verify_jwt` fica como está: true nas duas):
   - `fecho-mensal-contabilista` (v2). Prova SEM enviar nada: `net.http_post` com corpo
     `{"year":2026,"month":10,"dry_run":true}` (mesmos cabeçalhos do cron 125) e ler
     `net._http_response`: `ensaio=true`, `aviso=null`, `texto` igual ao de
     `admin_fecho_contabilista(2026,10)`.
   - `monthly-partner-statement` (v4). A v3 já estava no ar (código igual ao repo a 10/11). **Não reenviar
     outubro** (o Hugo já o recebeu e decide ele).
   - `ocr-receipt`: só mudou o comentário de `nif_talao.ts` — publicar quando for conveniente.
5. **App e painel** (ramo `ai/2026-11-10-fecho-contabilista`): juntar a `autonomous-night-2026-04-29`
   e enviar → o CI faz Android e web; iOS pelo caminho de sempre. Verificar nas 3:
   - estafeta: sem NIF do cliente o cartão "NIF PARA A FATURA" não aparece; com NIF do cliente aparece;
   - painel `/admin/fecho-mensal` → secção "Para o contabilista" (copiar, CSV, nota, reenviar);
   - painel Dinheiro → "Dados fiscais (DAC7)";
   - app da limpeza/Casa/lavagem/loja com dados em falta → barra "Faltam dados para as Finanças".
6. **WhatsApp do dia 1** (tarefa `trig_011ZYanoJf6WgveKKV2KTHtp`, criada pela Claude.ai): não mexi nela.
   Depois dos passos 2 e 4, trocar o passo 5 da tarefa para mandar `resumo->>'texto'` (a Edge v2 grava o
   texto completo em `fecho_mensal_contabilista_log.resumo.texto`) — é o mesmo texto do email e do painel,
   já com as regras do Hugo; acrescentar só os talões e as faturas do Gmail como hoje.
7. **Stripe da empresa para o Hugo** (`docs/stripe-acesso-contabilista-so-leitura.md`): só com o email
   dele e o "autorizo" do Danilo no momento.

## O que mudou (resumo)

- Fecho ao contabilista: uma só linha "Consumidor final"; "parte da Bora nos pedidos desta loja
  (faturada aos clientes)"; "Cada prestador fatura a sua parte; o regime de IVA e a retenção de cada um
  são confirmados pelo contabilista"; sem TVDE; secções novas (tokens oferecidos e descontados, códigos
  promocionais, prémios do check-in, cancelados e reembolsos, taxas da Stripe só da parte Bora, pedidos
  com prejuízo, pedidos com NIF do cliente, dados em falta DAC7, nota do Danilo).
- Entidade do fecho pelo mês: sociedade desde 11/2026 (antes `admin_monthly_closeout` lia só as settings,
  que ainda dizem "individual").
- BEMVINDO: não é desconto num pedido — credita 1000 tokens (5 €) na conta do cliente; a ligação fica em
  `promo_code_uses.tokens_origem` (coluna gerada, sem tocar na função dos tokens).
- Conferência (D1) `admin_fecho_conferencia(ano, mês)`: só reporta. Outubro: 0 diferenças; 2 pedidos em
  dinheiro sem valor de dinheiro registado (Favor 1a2c3afe 10,08 e pedido de loja parceira 74657b0d 24,81).
  Novembro: Favor b72c4f2c, Stripe 13,21 contra 23,98 (os 10,77 que o cliente pagou à parte a 03/11).
- Teste D3: `supabase/tests/fecho_mensal_consistencia_test.sql` (OK na produção a 10/11).
