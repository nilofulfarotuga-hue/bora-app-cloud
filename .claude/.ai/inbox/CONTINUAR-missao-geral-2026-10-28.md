# CONTINUAR — missao-geral-2026-10-28

Atualizado: 29/10/2026 05:05 UTC. Ler antes o ESPEC: `.claude/.ai/provas/missao-geral-2026-10-28/ESPEC.md`
e o e2e_log (fluxo missao-geral-2026-10-28, ids 5037 em diante).

Cópia de trabalho: `C:\BoraLocal\wt-missao-geral-28-10`, ramo `missao-geral-2026-10-28`, base origin 9eed27ff.
Nada foi enviado para o servidor git (sem push). Flutter do CI: `C:\BoraLocal\flutter-3.41.2\flutter\bin\flutter.bat`.

## PORQUE PAROU
29/10 ~04:58 UTC: limite semanal do motor Opus 5.5 atingido (volta 1/11 às 18:00 de Lisboa). Três agentes
caíram a meio (revisor do Bloco 1, robô, cartazes); a sessão fechou registos e relatório noutro motor.
Quando o motor voltar: sessão NOVA do Claude Code na pasta `C:\BoraLocal\wt-missao-geral-28-10`, com este
ficheiro e o relatório `.claude/.ai/reports/OPUS-2026-10-28-missao-geral.md`.

## Feito e provado (commits no ramo, por ordem)
- Bloco 0: JANELA 1 (IVA das faturas + apagar função de teste) aplicada e no repo; 5 ramos juntados sem
  histórico; ESPEC; migrações em falta listadas (e2e 5043); 5 migrações de produção copiadas com md5 igual.
- Bloco 1 A+B (3d42e87e), C3 modelo (0ba9b9a0), C3 ecrãs + C4 admin (60c4cbf4). 262 testes verdes.
  Proposta de dinheiro para o Claude.ai: `docs/propostas/missao-geral-2026-10-28/bloco1/` (prop-9f87a6c6).
  C5 vigia: SQL pronto em `janela2/C5_vigia_dinheiro_a_cobrar.sql` (por aplicar). C6 fora do repo.
- Bloco 2 servidor (6e8ee02c, 08fe2ba0): 4 Edge mudadas no repo (NÃO publicadas) + pacote para o
  Claude.ai em `docs/propostas/missao-geral-2026-10-28/bloco2/` (prop-38d65b15 e prop-d7d3717b entregues;
  o resto foi cortado pelo classificador, ver docs/TRANCAS.md).
- Bloco 3 (9b21efa0): fecho mensal consertado em produção (20261029045558), filtro semana + CSV, termos só
  comida/mercado; F1/F2/F3 SQL em `janela2/` por aplicar.
- Bloco 6: E1 consertado e provado (0x401 em 7,5 h; a9a3f38b); E2 confirmado; E3/E4 reportados; E6 feito
  (PADRAO_BORA §3.15, skill mods-bora, erros-aprendidos).

## Falta (por ordem)
1. REVISOR INDEPENDENTE do Bloco 1 (dinheiro) — parou antes do veredito. Sem ele não se pede "publica".
   Depois: Juiz (anti_trapaca já OK com olho humano conferido; analyze e bateria completa — ver e2e bF.a),
   fiscal de segurança (protocolo §9), e pedir publica-1 pelo Telegram.
2. Bloco 2 na APP: diálogo "Cancelar pedido" (order_tracking_screen ≈1303), refund_choice_dialog.dart,
   strings_en.dart, textos depois do cancelamento (order_details_screen ≈216/443), admin (rótulo do
   wallet_split_free_pct; detalhe do cancelamento: meio, valor, tokens). Procurar 80%/20%/pontos em lib/.
   A frase "os tokens voltam como tokens" só entra quando o e2e_log mostrar (1) e (2) aplicados.
   Reportado pelo agente: support-chatbot/index.ts:399 e 425-428 ainda dizem 80/20.
3. Bloco 3 N1 (NIF opcional no pagamento/perfil/detalhe), N2 (parceiro), N3 (driver_fiscal_card), N4
   detalhe do pedido/cliente no admin + ajuda em admin_partner_detail_screen ≈1093, N5 (entrega grátis
   no carrinho/pagamento; a linha do quote_order_pricing é para o Claude.ai), F4 só confirmar.
4. Bloco 4: acabar restaurante.py/rotinas (commit WIP 06ea24ec), testes Python, W4 admin, JANELA 2
   (C5, F1, F2, F3, W1, Edge não vermelhas), instalar na VPS e reiniciar `assistente-negocio`, tenant
   por SQL (ficheiro fora do repo: Desktop\Bora\prompts\missao-geral-2026-10-28-W1-tenant-boom.sql),
   W5 em modo demo, janela de 24 h só para o 931, W6 checklist Meta.
5. Bloco 5 cartazes (nada feito; brief completo no relatório).
6. Bloco 6 E5 (lista dos "reportado" antigos — já recolhida no e2e: 4761, 4800, 4804, 4809, 4979, 4980).
7. Bloco F: fiscal, digest, relatório final, publica-2.
