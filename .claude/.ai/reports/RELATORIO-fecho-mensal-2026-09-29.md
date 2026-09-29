# Relatório — fecho mensal (missão `fecho-mensal-2026-09`, 29/09/2026)

Motor: Opus 5.5 · Porta: Claude Code · Ramo `autonomous-night-2026-04-29` · Supabase `ojykpzwqrtusfeakzrna`
RAM medida no arranque: **697 MB disponíveis** (acima do portão leve de 400 MB). Antes do `flutter analyze`: **1087 MB** (acima dos 800 MB do portão pesado).

## Números de setembro (confirmados por SQL antes de escrever código — B0)

| O quê | Valor | Bate com o prompt? |
|---|---|---|
| Pedidos entregues reais (sem TVDE) | 17 | sim |
| Pago pelos clientes | 371,40 € | sim |
| Custo da mercadoria | 275,19 € | — |
| Receita própria da Bora | 96,21 € | sim |
| Pago a estafetas | 87,93 € | sim |
| Lucro | 8,28 € | sim |
| Barbearia (1 corte) | 12,00 € pagos, Bora reteve 0, taxa Stripe 0,43 € | sim |
| TVDE de outros motoristas (parte Bora, sem o Danilo e sem o "Rui Teste E2E") | 10,00 € (25 corridas) | sim (acrescento das 22:20) |

**Uma regra que o prompt não dizia e que é precisa para bater os 96,21 €:** o pedido do Burger King
`29c1043a` não tem talão. O custo dele entra como **subtotal ÷ 1,15** (13,63 → 11,85 €). Sem esta
regra a receita dava 108,06 €. A função marca estes pedidos como "custo estimado".

**Comissão das lojas parceiras = subtotal − parte da loja.** É isto que dá as faturas que o Danilo
passou à mão: Goola 8,76 € e Sabores de Casa 5,05 €. Consumidor final = 96,21 − 8,76 − 5,05 = 82,40 €.
As quatro faturas-recibo de setembro saem iguais às declaradas.

## O que ficou feito, bloco a bloco

| Bloco | Feito | Prova |
|---|---|---|
| B0 | Números confirmados | SELECTs acima; tabela bate |
| B1 `admin_monthly_closeout(ano, mes)` | Aplicada. Só leitura, só admin (ou service_role). Totais, por método, parceiros (com acertos pagos e pendente), serviços, estafetas (ganho, dinheiro em mão, talões), pedidos no prejuízo com motivo, TVDE de outros motoristas, bloco "para as Finanças" com as faturas-recibo e texto corrido, e o bloco "modelo a partir de 01/10" (receita Bora vs cobrado por conta de terceiros) | JSON completo no fim |
| B2 `partner_monthly_statement(id, ano, mes)` | Aplicada. Só a própria loja (ou admin/service_role) | Goola vê o seu: 4 pedidos, vendas 61,26, comissão 8,76, parte 52,50, pago 52,50, saldo 0,00. Goola a pedir o da Sabores → `sem_permissao` |
| B3 Edge Function `monthly-partner-statement` | Publicada (v1). Tabela `monthly_statement_log` (idempotente). Cron novo **88** `0 8,9 1 * *` (só avança às 09h de Lisboa). Função `admin_resend_monthly_statement` para o botão "Reenviar" (force) | Envio único de prova a 2026-09 para a Goola: HTTP 200, `estado: sent`, linha em `monthly_statement_log` com `sent_at 2026-09-29 21:30:46 UTC`. Resumo ao admin enviado (id Resend `01a0ef13-cc85-7e2d-abbb-1f6371438113`) |
| B4 Painel `/admin/fecho-mensal` (PT-BR) | Ecrã novo, escolher mês, B1 inteiro, CSV e PDF, parceiros com "extrato enviado / reenviar", prejuízo com link para o pedido, recibos dos estafetas, faturas da Bora por dia, botão "Exportar DAC7". Rota registada em `main.dart` e entrada "Fecho do mês" em Dinheiro e acertos. **A rota do fecho semanal (`/admin/acertos-semana`) já estava registada** — confirmado | `flutter analyze` sem erros; 33 testes do painel verdes |
| B5 App do parceiro (PT-PT) | Cartão "Este mês" no ecrã de Ganhos, por baixo do fecho semanal: resumo, acertos, pedidos, mês anterior/seguinte e "Descarregar extrato (PDF)" | `flutter analyze` sem erros |
| B6A Modelo novo do estafeta | Termos de 01/10/2026 (cliente e estafeta) com aceitação obrigatória no arranque (`TermsGate`); NIF + "tenho atividade aberta" (`driver_fiscal_status`), aviso 14 dias (prazo 15/10/2026), depois não fica online; `driver_monthly_invoice_summary` + "Já passei o recibo"; aviso ao admin no dia 10 (cron novo **89**) | Valdemir vê só o dele (5 entregas, 24,90 €, texto do recibo pronto); `bloqueado=false`, `dias_restantes=16` |
| B6B Fatura da Bora por pedido | Tabela `bora_invoices_pending`, gatilho `zzzz_bora_fatura_on_delivered` (a partir de 01/10; qualquer erro vira aviso e nunca parte a entrega), lista do mês com total por dia e "marcar como lançadas" | Função responde; setembro fica de fora por desenho |
| B6C DAC7 | `admin_dac7_report(ano)`: reaproveita o `admin_dac7_export` de 23/09 e junta o que faltava (prestadores de serviços) e o NIF confirmado pelo estafeta; lista quem não tem morada e quem não tem NIF. Só prepara, não envia | 2026: 8 linhas, 2 sem morada, 4 sem NIF |
| Publicação | Commit `136fff32` (só os 12 ficheiros da missão, caminhos explícitos), push `c4bf71be..136fff32`. CI arrancou: Android, Web e olho-golden | ver secção CI |

## O que ficou em `staged_` (zona protegida — não aplicado)

`platform_settings.staged_fecho_mensal_20260929`:
- **Bloqueio no servidor ao aceitar entrega** (`driver_accept_offer`, zona do dispatch): acrescentar a
  verificação `public._estafeta_fiscal_bloqueado(auth.uid())`. A função auxiliar já existe (só leitura).
- **Dispatch não oferecer a quem está bloqueado**.
Hoje o bloqueio é só na app (não deixa ficar online). Um estafeta com app antiga continua a poder aceitar.

⚠️ ISTO MEXE NO DISPATCH (zona protegida). Está tudo pronto — confirma que eu aplico.

## Funções, tabelas e ecrãs mexidos (e porquê)

- Funções novas: `_fecho_pedidos`, `_fecho_limites`, `_fecho_stripe_estimado`, `admin_monthly_closeout`,
  `partner_monthly_statement`, `monthly_statement_recipients`, `admin_resend_monthly_statement`,
  `legal_terms_pending`, `legal_terms_accept`, `_nif_valido`, `driver_fiscal_status_get`,
  `driver_confirm_fiscal_activity`, `driver_monthly_invoice_summary`, `driver_mark_invoice_issued`,
  `aviso_recibos_estafetas_em_falta`, `_bora_invoice_upsert`, `fn_bora_invoice_on_delivered`,
  `admin_bora_invoices_month`, `admin_mark_bora_invoice`, `admin_dac7_report`, `_estafeta_fiscal_bloqueado`.
- Tabelas novas (todas com RLS): `monthly_statement_log`, `legal_terms_versions`, `legal_terms_acceptances`,
  `driver_fiscal_status`, `driver_monthly_invoices`, `bora_invoices_pending`.
- Gatilho novo em `orders`: `zzzz_bora_fatura_on_delivered` (AFTER UPDATE OF status, só escreve em
  `bora_invoices_pending`; não mexe em valores do pedido).
- `platform_settings` (chaves novas, nenhuma de preço): `fecho_tvde_excluir_emails`,
  `estafeta_fiscal_em_vigor_desde`, `estafeta_fiscal_prazo`, `staged_fecho_mensal_20260929`.
- Cron novos: 88 `monthly-partner-statement`, 89 `aviso-recibos-estafetas`. Jobs 26/63 intocados; 43/58/69 continuam desligados.
- Edge Function nova: `monthly-partner-statement`.
- Flutter: `main.dart` (rota + `TermsGate` no cliente e no estafeta de entregas), `admin_fecho_mensal_screen.dart`
  (novo), `admin_menu_registry.dart` (entrada), `partner_earnings_screen.dart` + `partner_monthly_statement_card.dart`
  (novo), `driver_home_screen.dart` + `driver_fiscal_card.dart` (novo), `terms_gate.dart` (novo).
- **Não mexi** em preços, comissões, ganhos do estafeta, Stripe, tokens, RLS de orders/wallets/ledger, nem no pubspec.

## Provas

- `flutter analyze` aos 8 ficheiros: **0 erros, 0 avisos**; 4 infos antigas (anonKey, activeColor, 2 const em linhas que não são minhas).
- `flutter test` painel + ficha legal + golden do painel: **33/33 verdes**.
- Chão anti-trapaça do Juiz (`--base HEAD`): **CLEAN, exit 0**.
- Provas SQL em transacção desfeita (DO + RAISE), com o admin simulado pelo uid `c9fccf85`, a Goola e o Valdemir.

## O que falhou ou ficou por fazer (com a causa real)

1. **Capturas no emulador Android: não feitas.** O emulador precisa de ~3 GB de RAM e o PC tinha ~1 GB livre;
   ia pendurar a sessão (lição já registada). A captura da app do parceiro exige entrar na conta da loja, e
   eu não entro com palavras-passe de contas reais. Ver secção CI para o que se conseguiu no navegador.
2. **Autoteste completo** (`flutter test` inteiro): corri só os testes que tocam nos ecrãs mexidos, não a suite toda (RAM).
3. **NIF do cliente no checkout (B6B)**: não existe campo e acrescentá-lo mexe no checkout (zona que cobra).
   As faturas saem todas a consumidor final até haver campo.
4. **Córtex**: o conector pede nova autorização (OAuth perdido) — não consegui ler nem gravar lá.

## Erros encontrados fora do âmbito (reportados, não corrigidos)

1. **MB Way com `stripe_charge_cents = 0`** nos 6 pedidos MB Way de setembro. Pelo nome da coluna, o valor cobrado
   pela Stripe devia estar lá. Por isso a "parcela Stripe estimada" dá 0 € nas entregas. Vale ver se o webhook grava a coluna.
2. **Talão do Burger King `bf7d404d` = 17,18 € para um subtotal de 9,80 €** (e 5,02 € de tokens). Parece talão mal
   escrito ou pedido com mais coisas: dá −8,97 € de resultado.
3. **4 pedidos no prejuízo em setembro** (lista no JSON): Auchan e Wells com talão acima do catálogo, Continente em que as taxas não cobrem o estafeta.
4. **Sabores de Casa sem NIF** em `restaurants.nif`: gravar quando chegar (a fatura de 5,05 € sai marcada "falta NIF").
5. **DAC7**: 2 vendedores sem morada e 4 sem NIF em 2026. O relatório lista quem são.
6. **DAC7 e TVDE**: o `admin_dac7_export` já existente soma o ganho TVDE dentro do total do estafeta. Está certo para o DAC7, mas é diferente do resto deste prompt (onde a TVDE fica de fora).

## PARA O DANILO

- ⚠️ Dispatch: aplicar o bloqueio no servidor (secção `staged_`)? Responde "vai".
- Os termos novos aparecem **já no próximo arranque** (cliente e estafeta de entregas), a dizer que valem a partir de 01/10. Os motoristas TVDE não os veem (a TVDE ficou fora desta ordem).
- O contabilista ainda não confirmou "intermediário vs revendedor". Tudo aqui segue o que decidiste a 29/09: regime simplificado, isento art. 53.º (M10).

## JSON de `admin_monthly_closeout(2026, 9)`

```json
{
  "totais": {
    "lucro": 8.28,
    "por_metodo": {
      "cash": {"pago": 254.59, "pedidos": 11, "stripe_estimado": 0, "cobrado_pela_stripe": 0.00},
      "mbway": {"pago": 116.81, "pedidos": 6, "stripe_estimado": 0, "cobrado_pela_stripe": 0.00}
    },
    "stripe_estimado": 0,
    "custo_mercadoria": 275.19,
    "pago_a_estafetas": 87.93,
    "pedidos_entregues": 17,
    "pago_pelos_clientes": 371.40,
    "receita_propria_bora": 96.21,
    "pedidos_com_custo_estimado": 1
  },
  "periodo": {"ano": 2026, "fim": "2026-09-30T23:00:00+00:00", "mes": 9, "fuso": "Europe/Lisbon", "nome": "setembro", "tvde": "excluído", "inicio": "2026-08-31T23:00:00+00:00"},
  "servicos": [
    {"nome": "Barbearia Ouro e Prata", "estado": "paid", "pago_em": "2026-09-19T20:21:41.223592+00:00", "marcacoes": 1, "bora_reteve": 0.00, "provider_id": "82e3162c-0560-443a-a44a-104dc71a95ef", "taxa_stripe": 0.43, "liquido_prestador": 11.57, "pago_pelos_clientes": 12.00}
  ],
  "estafetas": [
    {"nome": "Danilo", "ganho": 63.03, "user_id": "4f61dd31-5e9e-4a7c-a557-7d53d2ceded7", "entregas": 12, "taloes_adiantados": 152.80, "dinheiro_recebido_em_mao": 209.76},
    {"nome": "Valdemir Vasconcelos", "ganho": 24.90, "user_id": "e355fde0-b634-48ba-bce1-e2a4466c4cc2", "entregas": 5, "taloes_adiantados": 27.76, "dinheiro_recebido_em_mao": 44.83}
  ],
  "parceiros": [
    {"nome": "Goola Açaí", "email": "goolaguarda2443@gmail.com",
     "acertos": [
       {"estado": "paid", "pago_em": "2026-09-06T23:30:57.046172+00:00", "parte_loja": 19.80, "semana_fim": "2026-09-06", "semana_inicio": "2026-08-31"},
       {"estado": "paid", "pago_em": "2026-09-14T09:17:30.758944+00:00", "parte_loja": 21.80, "semana_fim": "2026-09-13", "semana_inicio": "2026-09-07"},
       {"estado": "paid", "pago_em": "2026-09-21T13:51:15.57203+00:00", "parte_loja": 10.90, "semana_fim": "2026-09-20", "semana_inicio": "2026-09-14"}],
     "extrato": {"erro": null, "estado": "sent", "enviado_em": "2026-09-29T21:30:46.869+00:00"},
     "pedidos": 4, "pendente": 0.00, "parte_loja": 52.50, "partner_id": "goola-acai-guarda", "pago_no_mes": 52.50, "vendas_brutas": 61.26, "comissao_total": 8.76},
    {"nome": "Sabores de Casa Açaí", "email": "kauanmtsaru@gmail.com",
     "acertos": [{"estado": "paid", "pago_em": "2026-09-28T11:34:51.230977+00:00", "parte_loja": 30.28, "semana_fim": "2026-09-27", "semana_inicio": "2026-09-21"}],
     "extrato": null, "pedidos": 1, "pendente": 0.00, "parte_loja": 30.28, "partner_id": "12aa2cbb-01bd-443b-a17e-633c169d4864", "pago_no_mes": 30.28, "vendas_brutas": 35.33, "comissao_total": 5.05}
  ],
  "regra_custo": "parceiro=ledger earning; não-parceiro=talão (order_receipts_v2); sem talão=subtotal/1,15",
  "servicos_totais": {"marcacoes": 1, "bora_reteve": 0.00, "taxa_stripe": 0.43, "pago_prestadores": 11.57, "pago_pelos_clientes": 12.00, "pendente_prestadores": 0},
  "para_as_financas": {
    "texto": "Receita própria da Bora em setembro de 2026: 96.21 € nas entregas, mais 10.00 € de parte da Bora nas corridas TVDE de outros motoristas (25 corridas; as do próprio Danilo e as de teste ficam fora). Entregas por rubrica: entrega 48.29 €, taxa de serviço 20.27 €, sacos 3.50 €, taxa de pedido pequeno 8.34 €, comissões de lojas parceiras 13.81 €, margem sobre compras em lojas não parceiras 4.78 €, ajustes e descontos -2.78 €. Não inclui o valor da mercadoria (275.19 €), que pertence às lojas. Serviços (marcações): a Bora reteve 0.00 €. Faturas-recibo a emitir: uma por loja parceira com a comissão (13.81 €) e o resto a consumidor final (82.40 € entregas + 10.00 € TVDE). Regime simplificado, IVA isento ao abrigo do art. 53.º do CIVA (M10).",
    "regime": "simplificado; IVA isento art. 53.º CIVA (M10)",
    "rubricas": {"sacos": 3.50, "entrega": 48.29, "taxa_servico": 20.27, "ajustes_descontos": -2.78, "taxa_pedido_pequeno": 8.34, "margem_nao_parceiros": 4.78, "comissao_lojas_parceiras": 13.81},
    "faturas_recibo": [
      {"nif": "519478428", "valor": 8.76, "descricao": "Comissão de intermediação — pedidos pela plataforma Bora", "falta_nif": false, "partner_id": "goola-acai-guarda", "destinatario": "Goola Açaí"},
      {"nif": null, "valor": 5.05, "descricao": "Comissão de intermediação — pedidos pela plataforma Bora", "falta_nif": true, "partner_id": "12aa2cbb-01bd-443b-a17e-633c169d4864", "destinatario": "Sabores de Casa Açaí"},
      {"nif": null, "valor": 82.40, "descricao": "Serviços de entrega e intermediação — plataforma Bora (setembro 2026)", "destinatario": "Consumidor final"},
      {"nif": null, "valor": 10.00, "descricao": "Parte da Bora nas corridas TVDE de outros motoristas (setembro 2026)", "destinatario": "Consumidor final"}
    ],
    "receita_propria": 96.21, "receita_servicos": 0.00, "total_a_declarar": 106.21, "parte_bora_tvde_outros": 10.00
  },
  "pedidos_no_prejuizo": [
    {"data": "2026-09-24", "loja": "Burger King", "pago": 13.59, "motivo": "talão provavelmente mal escrito", "estafeta": 5.38, "order_id": "bf7d404d-7007-4ceb-914a-fec63dba83bb", "resultado": -8.97, "mercadoria": 17.18},
    {"data": "2026-09-01", "loja": "Auchan", "pago": 39.86, "motivo": "talão acima do catálogo", "estafeta": 6.42, "order_id": "3768b27e-f086-44e4-b355-f096be0258e1", "resultado": -5.56, "mercadoria": 39.00},
    {"data": "2026-09-14", "loja": "Wells", "pago": 18.32, "motivo": "talão acima do catálogo", "estafeta": 5.41, "order_id": "197a6d93-e112-4c0d-87cd-861a2b99cb62", "resultado": -1.82, "mercadoria": 14.73},
    {"data": "2026-09-09", "loja": "Continente", "pago": 16.27, "motivo": "taxas do pedido não cobrem o estafeta", "estafeta": 5.47, "order_id": "6194a8fa-6171-4bb7-bc1d-9a9c8775d1ab", "resultado": -1.70, "mercadoria": 12.50}
  ],
  "tvde_outros_motoristas": {"nota": "Soma de tvde_rides.bora_cut_cents (finalizada). Fora: corridas do próprio Danilo e contas de teste.", "corridas": 25, "parte_bora": 10.00},
  "modelo_a_partir_de_2026_10": {
    "nota": "Em vigor a partir de 01/10/2026. Até 30/09 a receita declarada é a receita_propria_bora.",
    "receita_bora": 8.28,
    "receita_bora_rubricas": {"sacos": 3.50, "taxa_servico": 20.27, "taxa_pedido_pequeno": 8.34, "margem_nao_parceiros": 4.78, "comissao_lojas_parceiras": 13.81, "entrega_menos_ganho_estafeta": -39.64, "ajustes_descontos": -2.78},
    "cobrado_por_conta_de_terceiros": {"estafetas": 87.93, "lojas_parceiras": 82.78, "mercadoria_nao_parceiros": 192.41}
  }
}
```
(`ajustes_descontos` no bloco do modelo novo foi acrescentado depois da primeira chamada, para as rubricas somarem os 8,28 € — confirmado por SQL: soma 8,28 = receita_bora 8,28.)
