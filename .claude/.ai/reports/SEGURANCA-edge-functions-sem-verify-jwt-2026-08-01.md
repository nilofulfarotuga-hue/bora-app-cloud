# 🔒 SEGURANÇA — 24 Edge Functions sem `verify_jwt` declarado
Aberto: 2026-08-01 · Estado: **POR AUDITAR** · Zona: 🟡 sensível (autenticação)

> Entrada **separada** por ordem do Danilo: isto é segurança, não é resto da missão
> `nunca-mais-travar`. Não pode ficar enterrado no relatório de ontem.

## O que se sabe (facto, não suposição)

Contado a 2026-08-01 em `supabase/functions/`:

- **53** Edge Functions locais (pastas com `index.ts`)
- **24** dessas **não declaram `verify_jwt` em nenhum ficheiro da sua pasta**
- 29 declaram

Como apareceu: por acaso, na prova de paridade da missão `nunca-mais-travar` — a tarefa de teste
era uma auditoria de Edge Functions. Não foi uma auditoria de segurança intencional, por isso o
número é fiável mas **a interpretação ainda não foi feita**.

## O que NÃO se sabe (e é o trabalho)

`verify_jwt` não declarado **não significa automaticamente "pública"** — o default da plataforma
e a configuração de deploy podem impor JWT à mesma. Antes de agir é preciso responder a:

1. Qual é o comportamento real quando `verify_jwt` não é declarado — default `true` ou `false`?
   Confirmar na config de deploy (`supabase/config.toml`), não por memória.
2. Das 24, quais **deviam** ser públicas por desenho? Há casos legítimos:
   `create-payment-intent` e `create-mbway-payment-intent` são `verify_jwt=false` **de propósito**
   (documentado no `CLAUDE.md`), porque o cliente chama-as antes de haver sessão.
3. Das restantes, alguma expõe leitura/escrita de dados sem autenticação?
4. Alguma toca 🔴 dinheiro (Stripe, wallet, tokens, refund, payouts)?

## Regras que se aplicam a este trabalho

- **Zona 🔴:** qualquer função que toque pagamentos entra em PROPOSE-ONLY. Preparar tudo,
  **não aplicar**, esperar o "vai" do Danilo.
- Não alterar `verify_jwt` de nenhuma função "por precaução": mudar de `false` para `true` numa
  função que o cliente chama sem sessão **parte o fluxo em produção**. Cada mudança precisa de
  saber quem chama.
- O agente dono é o `seguranca` (🟡), com `backend-supabase`. Gate do Juiz obrigatório.

## Primeiro passo sugerido (read-only, sem risco)

Listar as 24 por nome com: quem as invoca no app (`git grep functions.invoke`), se são chamadas
antes ou depois do login, e se tocam tabelas financeiras. Só isso já separa "legítimo" de
"a corrigir" sem tocar em nada.

## Proveniência

Descoberto durante a missão `nunca-mais-travar-2026-07-31` (prova de paridade da Parte 2).
Relatório dessa missão: `.claude/.ai/reports/FECHO-nunca-mais-travar-2026-08-01.md`.
Contagem também registada no `CLAUDE.md` (secção Edge Functions), que estava stale em 44.
