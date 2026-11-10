---
id: memoria-claude-ai-digest-2026-11-10-fecho-contabilista
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-10
zona: verde
confianca: alta
estado: atual
---

# Digest 10/11/2026 — fecho ao contabilista com as regras do Hugo (Claude Code)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-10-fecho-contabilista`, origem `claude-code`, atualizada em 2026-11-10T16:09:26.387439+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 10 fecho contabilista · memoria claude.ai · claude_ai_memoria

A missão fecho-contabilista-2026-11-10 (ordem do Danilo de 10/11: "O que vai pro estafeta, o que vai pro parceiro, o que vai pro contabilista... sem erro") foi feita e testada pelo Claude Code no ramo de ensaio ai/2026-11-10-fecho-contabilista (commit f571247b, pedido de revisão #9 em nilofulfarotuga-hue/bora-app-cloud). Nada foi publicado: a bora-tranca desta sessão nega migration/DDL, deploy de Edge e envio fora de ai/ ("publica o Claude.ai"), e o Write da migração em supabase/migrations foi recusado por ler bora_tokens e ledger_entries; ficou registado em docs/TRANCAS.md e no e2e_log. O SQL está como proposta em docs/propostas/fecho-contabilista-2026-11-10 (01 fecho, 02 segurança, 03 NIF) com a ordem de publicação em LEIA-ME_PUBLICAR.md, provado no PGlite com as definições e os dados reais de outubro e novembro (42 verificações certas: outubro 159,17 com UMA linha consumidor final, tokens descontados 3,29 em rubrica própria, ajustes 0, entidade de novembro = sociedade 519686233).

ACHADO URGENTE: stripe_extrato_resumo, stripe_extrato_cruzar_base e fecho_mensal_prestadores têm a guarda "current_user in (postgres, service_role)", que dentro de SECURITY DEFINER é sempre verdadeira; provado na produção (só leitura) que um utilizador comum com uid inventado lê o resumo da Stripe e os estafetas com NIF, email e ganhos. Correção = proposta 02 (remendo por âncora) + a 01; aplicar primeiro. Regra: em SECURITY DEFINER usar session_user = 'postgres', nunca current_user.

Feito no ramo: Edge fecho-mensal-contabilista v2 (sem "a Bora fatura à loja", sem "recibo verde ao adquirente", sem TVDE, frase do IVA/retenção confirmados pelo contabilista, secções novas de tokens, códigos, check-in, cancelados/reembolsos, Stripe só parte Bora, prejuízo, NIF do cliente, dados em falta DAC7 e nota do Danilo, texto igual ao do painel guardado também em fecho_mensal_contabilista_log.resumo.texto, modo dry_run); monthly-partner-statement v4 (a v3 JÁ estava publicada; sem IVA/retenção fixos; lojas "parte da Bora faturada aos clientes"; outubro não reenviado); painel /admin/fecho-mensal "Para o contabilista" e ecrã novo "Dados fiscais (DAC7)"; app: cartão do NIF do estafeta só com NIF do cliente e aviso "Faltam dados para as Finanças" na limpeza, Casa, lavagem e lojas. BEMVINDO não é desconto em pedido: credita 1000 tokens (5 EUR) na conta do cliente, por isso o uso fica sem order_id; ligação nova em promo_code_uses.tokens_origem. Conferência D1: outubro sem diferenças (2 pedidos em dinheiro sem cash_total_due); novembro só o Favor de 03/11 com 10,77 pagos à parte (a diferença do Burger King de 2,00 é gorjeta cobrada junto). Teste D3 em supabase/tests passou na produção (set a nov). Guia da Stripe só leitura para o Hugo em docs/; ninguém convidado (falta o email dele e o autorizo). Testes: analyze sem erros novos, bateria completa 3261 verdes, Juiz CLEAN. Falta: a Claude.ai aplicar 02, 01 e 03, publicar as duas Edge, juntar o ramo e publicar nas 3, e ajustar o passo 5 da tarefa trig_011ZYanoJf6WgveKKV2KTHtp para enviar resumo->>'texto'. Repo bora-app-cloud continua PÚBLICO: nada de NIFs nem nomes com dados fiscais em ficheiros versionados nem neste livro.
