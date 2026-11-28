⚠️ MODO PROTECÇÃO TOTAL ⚠️

# Missão limpeza-planos-fecho-2026-11-28 — juntar a app dos planos e escrever o Bloco B

MOTOR: Opus 5.5 · PORTA: uma só — esta sessão na nuvem (claude.ai/code, repo
nilofulfarotuga-hue/bora-app-cloud). Entra pelo CEO-AI (`.claude/skills/ceo-ai/`),
segue `protocolo-missao-bora` e `modo-automatico`. Lê `AGENTS.md`, `CLAUDE.md`,
`PADRAO_BORA.md`.

## Porquê

Ordem do Danilo 28/11 09:25 ("faz tudo, testa, publica e pronto, não quero
aprovar nada"), 10:28 ("Sim, aplica tu") e 11:43 ("eu tô autorizando e tem que
fazer tudo"): planos de limpeza (casas e Bora Empresas) só com cartão, cobrança
automática, cancelamento fácil "como os grandes". A sessão do PC fez a app
(Blocos C, D, F, G) mas o trabalho ficou preso no PC (credencial só de leitura).
Ela mandou pelo livro SÓ a parte fora das zonas protegidas e uma especificação
do Bloco B. O Bloco B (dinheiro) escreve-se aqui como PROPOSTA; quem o aplica no
servidor é a Claude.ai, por MCP, com o autorizo acima.

## Onde está tudo (livro = tabela claude_ai_memoria, espelhada no Córtex)

NESTA SESSÃO NÃO USES O SUPABASE (cada SQL pede "Permitir" e ninguém está a ver).
Lê o livro pelo Córtex (`cortex_ler` / `cortex_buscar`, pasta
`permanente/memoria-claude-ai/`). Se o espelho ainda não tiver as páginas, espera
10 min e tenta outra vez (o espelho corre de hora a hora).

- `patch-limpeza-planos-app-2026-11-28-p1` … `-p4` — o patch da app, em 4 partes.
- `patch-limpeza-planos-app-2026-11-28-md5` — as somas md5 de cada parte e do todo.
- `limpeza-planos-b-especificacao-2026-11-28` — o que a app espera do servidor.

## Blocos

A · App. Junta p1..p4 por ordem, confere cada md5 e o md5 total (ATENÇÃO: o
copiar pode tirar espaços no fim das linhas; linhas de contexto vazias dentro de
um bloco `@@` têm de ser " " e a assinatura "-- "). Ramo novo
`ai/2026-11-28-limpeza-planos` a partir da linha principal de HOJE; `git am`.
Se houver conflito com o que entrou depois, resolve a favor do que está hoje na
linha principal. `flutter analyze` 0 erros e `flutter test` verde.

B · Servidor (proposta). Escreve, seguindo a especificação À LETRA (nomes de
tabelas, colunas, funções, parâmetros, campos devolvidos e palavras dos erros —
a app já depende deles):
1. `docs/propostas/limpeza-planos-b-2026-11-28/migracao.sql` — tabelas
   cleaning_plans, cleaning_plan_charges, cleaning_plan_charge_items,
   cleaning_plan_refunds; colunas plan_id e plan_visit_date em
   cleaning_bookings; RLS (cliente lê só o seu, admin lê tudo, ninguém escreve
   direto); as funções do cliente, da profissional e do painel (com
   _admin_op_guard); o gerador de visitas; a exceção da oferta antes de cobrar;
   as devoluções (Carteira Bora pelo mesmo caminho do "Parar a série" de 02/11,
   cartão pela Edge); as definições com valor por defeito; os 2 agendamentos.
   Funções novas nascem fechadas a anon. Tudo idempotente (create … if not
   exists / create or replace), sem DROP de nada que exista.
2. `docs/propostas/limpeza-planos-b-2026-11-28/provas.sql` — provas dentro de
   uma transação desfeita (begin … rollback): criar plano, ativar, gerar visitas,
   preço por vaga, saltar, cancelar, cobrança com e sem profissional, nova
   tentativa, devolução, chamada repetida com a mesma chave.
3. As Edge Functions `supabase/functions/cleaning-plan/` e
   `supabase/functions/cleaning-plan-charge/`, e as mudanças em
   `stripe-webhook-empresa` (eventos dos planos) e `cleaning-checkout` (reverse
   recusa visitas com plan_id). Segue o estilo das Edge que já lá estão (chaves
   só do servidor, erros genéricos ao cliente, idempotência por tentativa).
   Testes Deno onde as outras Edge têm.
Antes de escrever, lê as migrações e Edge da limpeza que já existem no repo
(create_cleaning_booking, _cleaning_next_offer, cleaning-checkout, a série e o
"Parar a série") para reaproveitar o que já existe em vez de inventar.

C · Provas. Juiz anti-trapaça limpo; analyze e test verdes; `deno check` nas
Edge. Se puderes, corre a migração e as provas num Postgres local (pglite ou
postgres do apt) com o esquema do repo; se não, diz que não correu.

D · Entrega. Commit da app (A) e da proposta (B) no ramo; pedido de revisão para
o autonomous-night-2026-04-29 com título começado por "⚠️ DINHEIRO — Limpeza
planos". NÃO juntes nem publiques: a Claude.ai revê, aplica o SQL e as Edge por
MCP e publica. No fim, relatório curto (fiz isto, falta isto) e e2e_log pelo
relatório (sem Supabase: deixa as linhas para a Claude.ai gravar).

## Regras
- Só dinheiro trava: aqui só se PROPÕE; nada se aplica em produção desta sessão.
- Erro encontrado pelo caminho fora deste âmbito: reportar, não corrigir calado.
- `git add` por caminho; nunca mexer no versionCode nem na versão do pubspec.
- Classificador ou tranca negou: registar em `docs/TRANCAS.md`, saltar, continuar.
- Commits terminam com: Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

No fim: /ctx doctor e /ctx stats (se existirem nesta sessão).
