# Triagem — ronda de 04/10/2026

## Números reais (lidos na produção)
- `robot_suggestions`: 284 linhas no TOTAL, **0 abertas**. Estados válidos: nova, aprovada, aprovada-emerson, em_execucao (abertos) · aplicada, rejeitada, expirada (fechados). Hoje: 129 expirada, 113 rejeitada, 42 aplicada. O "~284 abertas" da missão era o total da tabela — nada a fechar.
- `skill_suggestions`: 34 linhas, **9 pendentes** (estados: pending, approved, rejected, implemented, rolled_back, auto_archived). As 9 fechadas hoje como `rejected` com motivo.
- `cortex_red_proposals` (espelho do Córtex que o ecrã da Central mostra): 2 abertas (1 nova de 29/08, 1 vista de 22/07) — a gravação foi RECUSADA pela barreira (ver "Precisa de confirmação").
- Cópias antes de mexer: `bkp_robot_suggestions_20261004` (284), `bkp_skill_suggestions_20261004` (34), `bkp_cortex_red_proposals_20261004` (95), todas com RLS ligada. Registo em `admin_audit_log` id `2c24550e-9c46-42ac-a3c1-b7e5d3ab6dea`.

## skill_suggestions fechadas (9) — por motivo
- Já feitas (2): `2aa02045` e `b3d2476e` (botão de terminar sessão) — existe "Terminar sessão" em `lib/screens/profile_screen.dart:1046` + FAQ no RAG.
- Duplicadas (5): `8a6d5ac6`, `fb2890d0`, `ef12cada` (cancelar — cobertas pelas skills CANCEL_PRE_PURCHASE/CANCEL_DURING_PURCHASE; as respostas de cancelamento erradas estão a ser corrigidas hoje pelo agente cliente-app), `d92cab30` (tokens — TOKENS_INFO + 52 trechos no RAG), `c63d8667` (preço de produto do parceiro — PARTNER_FAQ + 12 trechos).
- Obsoletas (2): `6234c5db` ("não aparece o botão", mensagem única e vaga), `de822d7d` (queixa pontual do pedido #bba0f5 de 12/09).

## robot_suggestions — revisão das expiradas recentes (já fechadas, verifiquei se ainda valiam)
- `aab23909` produtos sem categoria → feito 27/09 (B12: 5695/5700 com secção).
- `27f2845a` no-show/lembretes → feito (lembretes push antes da marcação aplicados 05/08).
- `80c6b3cb` cron mover-pedidos-demo (erro is_purchase_finalized) → o erro já não aparece em 30 dias.
- `de535934` McMenu a cobrar bebida/batata à parte → corrigido: no catálogo a bebida e o acompanhamento são escolhas a 0 € dentro do menu.
- As restantes (jun–ago: timeouts de cron, pedidos presos, no-show, fotos) são ruído antigo do robô, já substituídas/expiradas pelo "cap"; nada a reabrir.

## VÁLIDAS ainda não cobertas (por prioridade)
Nenhuma sugestão aberta válida ficou por cobrir. Dois pontos de vigia que vi pelo caminho (não são sugestões, não mexi):
1. pg_cron "job startup timeout": 487 falhas a 02/10 e 585 a 03/10 (todos os crons), 0 hoje — vigiar amanhã; se voltar, é saturação de trabalhadores do pg_cron (esforço: médio, ver crons a cada 1 min).
2. Cron 80 `repor-demo-apagar`: 2 falhas em 7 dias por tempo esgotado a apagar em `auth.identities` — baixo (só dados de demonstração).

## Córtex
- `prop-5892b538` ARQUIVADA: código integrado pela Claude.ai e SQL aplicado hoje (provas B2/B3/B6 verdes).
- APROVADAS (páginas legítimas, não superadas — não existiam no Córtex): `prop-805dfc79` (mods-claude-code-bora; os digests de 02/10 só a resumem), `prop-01932840` (playbook-redes do Bora 24/09; a playbook-redes-emdia é outra app), `prop-ccec2438` (digest 22/09 ronda geral, registo histórico). Nota: a aprovação criou ordens na fila do loop (`*-aprovado-chat`, estado "aberta") — a página só aparece quando o carteiro as correr.
- Pendentes no Córtex agora: 0.

## PRECISA DE CONFIRMAÇÃO (a barreira recusou este UPDATE)
```sql
update public.cortex_red_proposals set status='decidida_fora', revisada_em=now(), revisada_por_email='triagem-ronda-04-10',
 nota_revisao = case pid when 'prop-19f56ee2' then 'Obsoleta (triagem 04/10): ordem de 29/08 já tratada no Córtex; superada pelas missões seguintes.'
  else 'Já feita (triagem 04/10): AdminRobotSuggestionsScreen usa TabBarView + ListView em todas as abas.' end
where pid in ('prop-19f56ee2','prop-ddd67f48') and status in ('nova','vista');
```
(São só as 2 linhas antigas do espelho que a Central mostra como "Novas"; no Córtex de origem já não estão pendentes.)

## Não mexi em código nem em funções.
