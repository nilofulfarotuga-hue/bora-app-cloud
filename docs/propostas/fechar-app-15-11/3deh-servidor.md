# Bloco 3 (d)(e)(h) — o que fica PROPOSTO, à espera de ordem

> fechar-app-15-11 · escrito a 14/11/2026 pelo ajudante do Bloco 3.
> Nada aqui foi aplicado. O que já está pronto para aplicar são as duas
> migrações `20261115020000_push_token_papel_handyman.sql` e
> `20261115020100_cron_desencontrar_minutos_redondos.sql`.

## 1. (h) Segunda metade do desencontro das tarefas agendadas — PRECISA DE ORDEM

**Porquê fica só proposto:** são 12 tarefas cuja função toca em dinheiro
(pagamentos, reembolsos, gorjetas, acertos, créditos) ou em vigias de pedidos.
A proposta NÃO muda o que elas fazem nem quantas vezes correm: muda só o minuto.
Mesmo assim é mexer em tarefas de dinheiro, por isso espera pela ordem do Danilo.

**Porquê é precisa:** a migração `20261115020100` (10 tarefas de avisos) baixa o
pior minuto de 39 para 29 arranques no mesmo segundo. Cabem 29 (57 ligações menos
28 já ocupadas) — e ainda há 5 varreduras de segundos por cima. Só com esta
segunda metade o pior minuto de uma hora normal fica em 17 e o pior do mês
(dia 1 às 08:00) em 23. Conta feita em `supabase/tests/fechar_app_3h_prova.mjs`,
secções 5 e 6.

| Tarefa | Hoje | Proposto | Corre aos minutos |
|---|---|---|---|
| check-orphan-orders | `*/5 * * * *` | `4-59/5 * * * *` | 4, 9, 14, … |
| vigia_pago_sem_pedido | `*/5 * * * *` | `4-59/5 * * * *` | 4, 9, 14, … |
| tvde_expire_roundtrip_credits | `*/10 * * * *` | `2-59/10 * * * *` | 2, 12, 22, … |
| tvde-sweep-abandoned-payments | `*/10 * * * *` | `2-59/10 * * * *` | 2, 12, 22, … |
| appt-expire-pending-payment | `*/10 * * * *` | `2-59/10 * * * *` | 2, 12, 22, … |
| preencher-custos-corridas | `*/10 * * * *` | `6-59/10 * * * *` | 6, 16, 26, … |
| payments-reconciler-cobrancas | `*/10 * * * *` | `6-59/10 * * * *` | 6, 16, 26, … |
| restaurante-do-dia | `*/10 * * * *` | `6-59/10 * * * *` | 6, 16, 26, … |
| appt-auto-noshow | `*/15 * * * *` | `13-59/15 * * * *` | 13, 28, 43, 58 |
| auto-approve-safe-suggestions | `*/15 * * * *` | `13-59/15 * * * *` | 13, 28, 43, 58 |
| settlement-receipts-retry | `*/15 * * * *` | `13-59/15 * * * *` | 13, 28, 43, 58 |
| gorjetas-devolver-cancelados | `*/15 * * * *` | `13-59/15 * * * *` | 13, 28, 43, 58 |

Verificado em produção (só leitura, 14/11): nenhuma das 12 funções olha para o
minuto nem para a hora em que corre (procura por `extract(minute/hour …)` e
`date_trunc('hour'/'minute' …)` no corpo de cada uma: zero). Não se leram as
funções que elas chamam por dentro.

Ficam nos minutos redondos, de propósito, as tarefas de ofertas e despacho
(carwash-offer-timeout, carwash-retry-unoffered, tvde-dest-change-sweep,
cleaning-offer-timeout, cleaning-expire-no-cleaner, cleaning-auto-confirm), as
nove de minuto a minuto e as cinco de segundos.

SQL pronto (mesmo molde da migração `20261115020100`; só mexe na tarefa que
ainda tiver o horário antigo; repetível):

```sql
DO $desencontrar$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT j.jobid, j.jobname, m.novo
      FROM (VALUES
        ('check-orphan-orders',           '*/5 * * * *',  '4-59/5 * * * *'),
        ('vigia_pago_sem_pedido',         '*/5 * * * *',  '4-59/5 * * * *'),
        ('tvde_expire_roundtrip_credits', '*/10 * * * *', '2-59/10 * * * *'),
        ('tvde-sweep-abandoned-payments', '*/10 * * * *', '2-59/10 * * * *'),
        ('appt-expire-pending-payment',   '*/10 * * * *', '2-59/10 * * * *'),
        ('preencher-custos-corridas',     '*/10 * * * *', '6-59/10 * * * *'),
        ('payments-reconciler-cobrancas', '*/10 * * * *', '6-59/10 * * * *'),
        ('restaurante-do-dia',            '*/10 * * * *', '6-59/10 * * * *'),
        ('appt-auto-noshow',              '*/15 * * * *', '13-59/15 * * * *'),
        ('auto-approve-safe-suggestions', '*/15 * * * *', '13-59/15 * * * *'),
        ('settlement-receipts-retry',     '*/15 * * * *', '13-59/15 * * * *'),
        ('gorjetas-devolver-cancelados',  '*/15 * * * *', '13-59/15 * * * *')
      ) AS m(jobname, antigo, novo)
      JOIN cron.job j ON j.jobname = m.jobname AND j.schedule = m.antigo
  LOOP
    PERFORM cron.alter_job(r.jobid, schedule := r.novo);
    RAISE NOTICE 'cron %: passa a "%"', r.jobname, r.novo;
  END LOOP;
END
$desencontrar$;
```

Voltar atrás: o mesmo bloco com as colunas "antigo" e "novo" trocadas.

Como medir se resolveu (24 h depois de aplicar as duas metades):

```sql
-- corridas perdidas pelo pg_cron (em 47 h até 14/11 foram 273)
select status, left(return_message, 30) as motivo, count(*)
  from cron.job_run_details
 where start_time > now() - interval '24 hours' and status = 'failed'
 group by 1, 2;
```

e, nos registos do Postgres, contar as linhas "remaining connection slots"
(em 24 h até 14/11 foram 75, todas aos minutos :00, :10, :20, :30, :40).

## 2. (h) Alternativa de infraestrutura — decisão do Danilo

Não é SQL e não a preparei: subir `max_connections` (hoje 60, o valor do
plano mais pequeno) na configuração do Postgres do projeto. Dá folga às
ligações mas não tira o engarrafamento de 36 a 39 funções a arrancar no mesmo
segundo (às 18:30 de 14/11 as tarefas demoraram ~18 s em vez de 0,05 s). O
desencontro resolve as duas coisas; a subida do limite só a primeira.

## 3. Escrita negada pela tranca (falso positivo) — proposta de correção da regra

A primeira versão de `supabase/tests/fechar_app_3d_prova.mjs` foi recusada
pela bora-tranca ("segredo no conteúdo novo"). Não havia segredo nenhum: era
uma constante de teste com o nome que se dá ao identificador do aparelho,
seguida de um texto inventado. Não repeti a escrita nem usei outra ferramenta:
a prova foi escrita sem essa constante (o aparelho de teste chama-se
"aparelho" no ficheiro), como já estava anotado na memória para esta regra.

Proposta para `hooks/regras.ts` (quem aplica é o Danilo ou uma sessão por
ordem dele): a regra do segredo literal não devia disparar em ficheiros de
`supabase/tests/` e `test/` quando o valor não tem forma de chave (texto
curto, com hífenes, sem o prefixo de nenhum fornecedor). Com um teste novo em
`tranca.test.ts` para esse caso.
