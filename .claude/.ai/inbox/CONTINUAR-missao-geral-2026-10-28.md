# CONTINUAR — missao-geral-2026-10-28

Atualizado: 28/10/2026 21:20 UTC. Ler antes o ESPEC: `.claude/.ai/provas/missao-geral-2026-10-28/ESPEC.md`
e o e2e_log (fluxo missao-geral-2026-10-28, ids 5037 em diante).

Cópia de trabalho: `C:\BoraLocal\wt-missao-geral-28-10`, ramo `missao-geral-2026-10-28`, base origin 9eed27ff.
Nada foi enviado para o servidor git (sem push). Flutter do CI: `C:\BoraLocal\flutter-3.41.2\flutter\bin\flutter.bat`.

## Feito e provado
- Bloco 0: JANELA 1 aplicada (20261028203348 IVA normal; 20261028203353 apagar função de teste) e no repo;
  5 ramos juntados sem histórico (7 commits); ESPEC; lista das migrações em falta (e2e 5043).
- C1: 5 migrações de produção postas no repo com md5 igual; as que a guarda recusa estão em
  `docs/propostas/missao-geral-2026-10-28/MIGRACOES-POR-POR-NO-REPO.md`.
- C2, C6, E3, E4: reportados (e2e 5045, 5046, 5049, 5048).
- A+B (talão e nome da loja): commit 3d42e87e. C3 modelo: commit 0ba9b9a0.
- E1 (401 da VPS): consertado e provado (0 respostas 401 desde 20:56); E2 confirmado.
- C5 vigia: SQL pronto em `docs/propostas/missao-geral-2026-10-28/janela2/C5_vigia_dinheiro_a_cobrar.sql` (por aplicar).
- Pedido ao Claude.ai: conta de teste com saldo e tokens (cortex prop-76046159).

## Em curso quando isto foi escrito (agentes)
- C3 ecrãs + C4 admin (driver_map, driver_home, favor_passos, ecrãs do cliente, admin_order_detail).
- Bloco 2 servidor (propostas em docs/propostas/missao-geral-2026-10-28/bloco2/; mudanças em
  supabase/functions/{cancel-order-with-choice,execute-cancellation,admin-cancel-order,auto-refund-order}).
- Bloco 3 parte fiscal (H2, N4 fecho mensal, N6, F1-F3; SQL em docs/propostas/.../janela2/).
- Bloco 4 robô (preparação; SQL W1 em janela2; tenant fora do repo em Desktop\Bora\prompts).

## Falta (por ordem)
1. Rever e fazer commit do C3/C4; revisor independente do Bloco 1; Juiz; pedir "publica" 1 (Telegram).
2. Bloco 2 app (diálogo de cancelamento, refund_choice_dialog, strings_en, textos depois do cancelamento,
   admin) — depois do C3, porque mexe nos mesmos ecrãs do cliente. Entregar ao Claude.ai o _shared e os tokens.
3. Bloco 3 N1, N2, N3, N4 (detalhe do pedido), N5 (pagamento, carrinho, parceiro, estafeta, admin).
4. JANELA 2 (C5, F1, F2, F3, W1 colunas + order_origem, Edge Functions não vermelhas) — Telegram antes.
5. W5 testes do robô em modo demo; janela de 24 h só para o 931.
6. Bloco 5 cartazes. 7. Bloco 6 E5/E6. 8. Bloco F.
