# Relatório — Stripe da empresa (missão stripe-empresa-2026-11-01), 02/11/2026 de madrugada

## Para o Danilo (texto corrido)

Fiz isto: deixei todo o código pronto para o app e o servidor trabalharem com duas contas Stripe — o
TVDE fica na tua conta pessoal e tudo o resto (entregas, Favores, limpeza, lavagem, marcações,
reservas de mesa, gorjetas de entregas, dívida, peso e extras) passa para a conta da empresa. A regra
que manda é: o dinheiro mexe-se sempre na conta onde entrou, por isso um pedido pago ontem na
pessoal é reembolsado na pessoal mesmo depois da mudança. Há um interruptor no painel admin ("Stripe
— duas contas") que nasce em "Pessoal" e só passa a "Empresa" depois das provas; voltar atrás não
precisa de nova versão da app. As apps antigas continuam a pagar na pessoal, ninguém fica sem pagar.
O servidor tem uma função nova para o webhook da empresa (a mesma lógica da pessoal, partilhada), e o
relatório da contabilista passa a separar as duas contas: o do Hugo só leva a empresa. Tudo isto está
gravado no computador, num ramo próprio (stripe-empresa-2026-11-01, commit 171733e8), com testes
verdes (12 no servidor, 24 na app) e o analisador do Flutter sem erros.

Falta isto, e porquê: a Stripe da empresa pediu a tua palavra-passe da Stripe para ligar a conta
Google boraappbora — só tu podes escrever isso (a página ficou aberta no Chrome do Bora e mandei-te
uma linha no Telegram). Sem entrar lá não consegui criar a chave da empresa nem o webhook. E a
tranca do computador (que protege dinheiro) não deixa esta sessão, sem ti presente, aplicar
migrações, publicar funções nem enviar o código para o servidor: cada uma dessas ações pergunta-te
na caixa e, sem resposta, recusa. Por isso o servidor está preparado mas não publicado, e as 8
funções mais sensíveis (criar pagamento, webhook, reembolsos, cancelamento pelo cliente, extra)
ficaram como propostas prontas a copiar. O passo a passo exato do que falta está em
docs/STRIPE_DUAS_CONTAS.md, secção 7 — a Claude.ai pode aplicar o SQL e publicar as funções pelo
MCP, como fez ontem com as outras propostas, ou tu aprovas as caixas numa sessão contigo.

Erros que encontrei pelo caminho: o conserto das chaves de 31/10 deixou quatro funções do repo com
os "imports" partidos (nunca foram publicadas, por isso ninguém notou; corrigi). A função de
reprocessar reembolsos estava mais velha no repo do que no ar (pus igual). As quatro funções de
cancelamento com a devolução de gorjetas, autorizadas a 30/10 e 01/11, continuam por publicar
desde 01/11. E não há versão mínima do app a forçar atualização (está a zero), o que significa que
apps antigas vão continuar na conta pessoal até atualizarem.

Próximo passo: tu escreves a palavra-passe da Stripe na página que ficou aberta (ou dizes à Claude.ai
para avançar com o SQL e as funções); a seguir criam-se as chaves e o webhook da empresa, aplicam-se
as propostas, fazem-se as provas em modo de teste e só então se vira o interruptor para "Empresa" e
se publica a app nas três lojas.

## Prova material (resumo)

- e2e_log, fluxo `stripe-empresa-2026-11-01`: ids 6102 (F0 arranque), 6103 (F0 inventário), 6110
  (tranca), 6112 (F2–F3), 6114 (F4–F5), F1 bloqueado, F7 bloqueado.
- Commit `171733e8` no ramo `stripe-empresa-2026-11-01` (worktree bridge-cse_01HPEpV8TqbMGfAxZbZkrQhU),
  69 ficheiros, +4546/−372. Push recusado pela tranca (sem o Danilo).
- `deno test _shared/stripe_contas_test.ts`: 12 passed, 0 failed.
- `flutter test` (stripe_contas_test, gorjetas_taxa_app_test, folha_cartao_porta_unica_test): All tests passed (24).
- `flutter analyze`: 0 erros nos ficheiros da missão (1 erro inicial — import em falta — corrigido);
  os 6 avisos e ~260 infos do projeto já existiam.
- `deno check` de 25 funções editadas + 8 propostas: só 2 erros pré-existentes em produção
  (`list-saved-cards`, `cleaning-checkout`, implicit any), confirmados no código do ar.
- Produção descarregada por função em `%TEMP%\claude\stripe-empresa-prod\per\<fn>` (base de cada edição).

## O que ficou bloqueado e onde está

| Bloqueio | Onde | Quem desbloqueia |
|---|---|---|
| Palavra-passe da Stripe (ligar Google) | Chrome perfil Bora, separador da Stripe | Danilo |
| Migrações SQL (01, 02, 03, 05) | `docs/propostas/stripe-duas-contas/*.sql` | Claude.ai por MCP ou Danilo na caixa |
| 8 funções da zona vermelha | `supabase/functions/_propostas/stripe-duas-contas/<fn>/index.ts` | idem (copiar + publicar) |
| `lib/stores/order_store.dart` (2 linhas) | `docs/propostas/stripe-duas-contas/04_order_store_duas_linhas.md` | idem |
| Deploy das 26 funções + stripe-webhook-empresa | lista em `docs/STRIPE_DUAS_CONTAS.md` §7.3 | idem |
| Push / publicação (3 plataformas) | `git push origin autonomous-night-2026-04-29` depois de juntar o ramo | Danilo na caixa |
