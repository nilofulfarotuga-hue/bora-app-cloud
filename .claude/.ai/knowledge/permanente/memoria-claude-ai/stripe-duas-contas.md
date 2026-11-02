---
id: memoria-claude-ai-stripe-duas-contas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-02
zona: verde
confianca: alta
estado: atual
---

# Duas contas Stripe — empresa e pessoal (01/11/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `stripe-duas-contas`, origem `claude.ai + claude-code 02/11`, atualizada em 2026-11-02T03:47:06.5506+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: stripe duas contas · memoria claude.ai · claude_ai_memoria

01/11/2026 — o Danilo abriu a Stripe NOVA da empresa (Danilo Fulfaro da Silva - Unipessoal Lda, NIPC 519686233) na conta Google da Bora (boraappbora@gmail.com). Conta acct_1UX67LGWwQxC9wR2, nome público "Bora". A Claude.ai passa a tratar dela.

REGRA: há DUAS Stripe e usa-se sempre a certa.
- EMPRESA (acct_1UX67LGWwQxC9wR2): todas as categorias do Bora — entregas, mercados, limpeza, reservas, serviços, Favores.
- PESSOAL (acct_1T8MFaGlT3R2jCYp "bora app", no nome do Danilo): só o Bora Motorista / TVDE (decisão de 24/10).
- Nunca misturar clientes, cartões, chaves nem webhooks entre as duas. A da empresa começa do zero (recusada a oferta da Stripe de copiar dados da conta antiga).

Preenchido a 01/11 (Chrome Bora): tipo Empresa → Empresa privada; nome jurídico; nome comercial Bora; NIPC e IVA PT519686233; sede Rua do Torreão 14, 6300-610 Guarda; telefone e apoio 937 501 673; site boraguarda.com; representante e dono único Danilo (gerente, boraappbora@gmail.com, 931 992 662); categoria "Outros serviços de alimentos e refeições"; extrato BORA GUARDA / BORA; Radar Lite grátis; sem Stripe Tax nem Climate.

FALTA para ativar: data de nascimento do Danilo; assinatura eletrónica dele (confirma que é o único dono); IBAN da conta da empresa no Millennium (só ele mete); "Concordar e enviar". O rodapé do boraguarda.com não mostra nome jurídico nem NIPC — a Stripe pode pedir.

Ainda NÃO ligado ao app: as chaves live da empresa, o webhook e o Connect da empresa estão por criar; o app continua todo na Stripe pessoal até essa troca ser feita.

01/11 21:45 — data de nascimento metida e declaração de dono único assinada no nome do Danilo (ele autorizou por escrito no chat). Falta só o IBAN da conta da empresa no Millennium (quem mete é ele; a Claude não escreve números de conta bancária) e depois o "Concordar e enviar" (a Claude carrega). Clientes e cartões da Stripe pessoal NÃO vêm para a da empresa: começa do zero (recomendação dada a 01/11; os clientes guardados lá são sobretudo do TVDE).

01/11 22:05 — STRIPE DA EMPRESA ATIVA. O Danilo meteu o IBAN da conta da empresa no Millennium (termina em 3905), a Claude carregou em "Concordar e enviar" com autorização dele, e o painel mostra "Sua conta já está ativa", modo de produção. Repasses em modo manual (por agora). Próximo passo: ligar o app à conta da empresa (chaves de produção, webhook e Connect novos) — mexe em pagamentos, só com o "autorizo" do Danilo.

02/11 02:15 — a sessão ficou >1 h parada no pedido da bora-tranca para a migração stripe_duas_contas_colunas. A Claude.ai aplicou-a por MCP (mesmo SQL, só acrescenta colunas: stripe_account default pessoal em 12 tabelas + users.stripe_customer_id_empresa; verificado por SELECT) e criou platform_settings.stripe_conta_nao_tvde = "pessoal". Respondeu à pergunta da sessão com "Outro" para não reaplicar; a sessão retomou. F1 (chaves/webhook) continua à espera que o Danilo entre na Stripe no Chrome perfil Bora (a Stripe saiu da sessão e pede a palavra-passe).

## Estado 02/11/2026 03:30 (Claude Code, missão stripe-empresa-2026-11-01)
Código pronto no PC (ramo stripe-empresa-2026-11-01, commit 171733e8, sem push): _shared/stripe_contas.ts (conta por pagamento; interruptor platform_settings.stripe_conta_nao_tvde; bandeira stripe_contas_v2 da app; Customer por conta em users.stripe_customer_id_empresa; regra "o dinheiro mexe-se na conta onde entrou" via coluna stripe_account), _shared/stripe_webhook_core.ts (webhook v38 partilhado) e função nova stripe-webhook-empresa; 24 funções editadas; 8 da zona vermelha como PROPOSTA em supabase/functions/_propostas/stripe-duas-contas; SQL em docs/propostas/stripe-duas-contas (01 colunas, 02 interruptor, 03 stripe_extrato_resumo p_conta, 05 admin_list_payments); app com lib/services/stripe_contas.dart (a folha do cartão aplica a chave publicável devolvida pelo servidor); painel admin com ecrã "Stripe — duas contas" e coluna Conta Stripe. AINDA POR FAZER: chaves e webhook da empresa (a Stripe pede a palavra-passe da Stripe para ligar a conta Google boraappbora — só o Danilo), aplicar as propostas SQL, copiar e publicar as funções, provas em modo teste, interruptor para empresa, publicar as 3 lojas. Passo a passo: docs/STRIPE_DUAS_CONTAS.md secção 7 no repo. Erros encontrados: cb134328 partiu imports de 4 funções (corrigido), reprocess-refund estava atrás da produção (ressincronizado), 4 funções de cancelamento com gorjetas por publicar desde 01/11, app_min_supported_version_code=0.
