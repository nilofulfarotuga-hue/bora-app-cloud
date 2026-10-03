# BORA APP — CONTEXTO DE NEGÓCIO E ESTADO (Junho 2026)
# Documento de referência. NÃO é código. Serve para o Claude Code/Hermes conhecerem as regras reais do projeto.
# Fonte: Danilo (fundador). Em caso de conflito com o código, este documento descreve a INTENÇÃO de negócio — investigar antes de mudar código.

## 1. PERFIL DO DANILO
- Fundador solo do Bora App. Brasileiro a viver na Guarda, Portugal.
- Também trabalha como estafeta TVDE (Uber/Bolt) na região da Guarda (Hyundai Ioniq 5) — tem visão dos dois lados.
- Comunica em português do Brasil informal, frequentemente por voz (interpretar intenção).
- Não é programador de formação — quer decisões claras e ações, não jargão.
- Emails admin: nilofulfarotuga@gmail.com, nilofulfaro@gmail.com.

## 2. REGRA CRÍTICA: PARCEIRO vs NÃO-PARCEIRO (confundir = erro grave)
Esta distinção SÓ se aplica a RESTAURANTES. Todos os mercados são SEMPRE não-parceiros.

### PARCEIRO (só restaurantes com contrato):
- Comissão: 10% visível + 5% markup oculto nos produtos + 5% taxa de serviço ao cliente.
- Estafeta: €3.80 + €0.20/km.

### NÃO-PARCEIRO (todos os mercados + restaurantes sem contrato):
- Preço: base + 15% fixo (incluído no preço mostrado).
- Fee fixo: €2.50.
- Estafeta: €3.80 + €0.20/km + €0.80 + 30% do lucro líquido da Bora.
- TODOS os mercados são não-parceiros: Continente, Lidl, Auchan, Pingo Doce, Mercadona, Intermarché.

## 3. VALORES GERAIS
- Entrega: €2.50 até 4km, +€0.50/km acima de 4km.
- Cash: máximo €40 por pedido.
- Sacos: restaurante €0.30 fixo; mercado €0.10 por saco.
- Tokens cliente: ROUND(preço × 3), mínimo 1.
- Tokens estafeta: +40 normal, +50 parceiro.

## 4. WALLET — SPLIT DE REEMBOLSO
Quando cliente cancela com reembolso para a wallet → split:
- 80% saldo livre (sem restrições)
- 20% tokens (expiram em 60 dias)
- Percentagens configuráveis em platform_settings.
- NÃO confundir com tokens de fidelidade do estafeta.

## 5. RESERVAS — PRÉ-PAGAMENTO
- €3 fixo cobrado ao cliente (prepayment_cents=300).
- Cliente CHEGA: parceiro desconta €2 do cliente (partner_payout_cents=200), Bora retém €1 (bora_service_cents=100).
- NO-SHOW (falta): Bora retém 100%.
- Cancela >2h antes: reembolso total.
- Cancela <2h antes: Bora retém 100%.
- cancel_window_hours=2.

## 6. IDIOMAS E DESIGN
- Apps (cliente, estafeta, parceiro): PT-PT (português europeu).
- Painel admin: PT-BR (só o Danilo usa). Termos técnicos com explicação entre parênteses.
- Design: verde #16A34A, laranja #F97316, fundo #F0F2EF, fonte Inter. Máx 1 laranja por ecrã.
- NUNCA alterar fotos reais de produtos de mercados/restaurantes — só cores, botões, cards, espaçamentos, cabeçalhos.

## 7. ESTADO ATUAL (Junho 2026)
Trabalho fechado desde Maio:
- TVDE vertical: bug crítico de identidade resolvido — drivers.id (PK aleatório) ≠ user_id (auth UID). Dispatch, FKs, notify-tvde-driver, location, e app Flutter corrigidos (commit 3c961ee).
- Favores (Errands) feature completa em produção (commit 53edfb4) — aguarda 1º teste E2E em device.
- Segurança hardening: RLS em tabelas backup, 9 funções SECURITY DEFINER revogadas de anon, bucket avatars privado. Role bora_admin aprovado, por criar.
- Build ~289, em Testes Fechados na Play Store (package pt.boraapp.bora). Falta 12 testadores + 14 dias para produção.
- 9855 preços do Continente corrigidos. ~42k produtos em 6 mercados.

## 8. ZONAS PROTEGIDAS / LISTA VERMELHA (nunca tocar sem autorização do Danilo)
- Dinheiro/Stripe: preços, fees, payouts, reembolsos, bora_tokens, platform_settings, webhooks Stripe.
- Escrita destrutiva em produção: DROP/DELETE/TRUNCATE, migrations destrutivas, dados em orders/wallets/ledger.
- Segurança: RLS, GRANT/REVOKE, auth, roles.
- Disparos em massa: push a todos os users, build de produção na Play Store, force-push na main.
- Ficheiros sensíveis: dispatch_engine, pricing_service.dart, pricing_calculate (SQL), triggers financeiros, notify-driver, bora_tokens, Stripe webhook v17+.

## 9. WORKFLOW
- versionCode: CI auto-incrementa (build_android.yml). NUNCA incrementar manualmente no pubspec.
- Branch de trabalho: autonomous-night-2026-04-29. Toda sessão termina com git push.
- Ordem de consulta na dúvida: 1º Obsidian/business_rules.md, 2º código do app, 3º padrão Glovo/Uber Eats/iFood. Nunca adivinhar.
- Toda feature nova → verificar se precisa de correspondência no painel admin (Danilo quer autoridade total: ver, editar, criar, banir, configurar, exportar, auditar).
- Pagamentos em teste: sempre dinheiro (cash).
