---
id: memoria-claude-ai-digest-2026-10-27-boom-burger-5
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-27
zona: verde
confianca: alta
estado: atual
---

# Boom! Burger 27/10 tarde — consertos no servidor + adendo 3

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-27-boom-burger-5`, origem `claude-ai`, atualizada em 2026-10-27T17:06:23.377275+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 27 boom burger 5 · memoria claude.ai · claude_ai_memoria

Danilo (15:54) mandou consertar JÁ tudo o que ficou para trás: "não pode ficar nada pra depois" (regra gravada em erros-aprendidos).
Aplicado pelo Claude.ai por MCP (migrações): is_partner_open_respeita_pausa_2026_10_27 e is_partner_open_proxima_abertura_2026_10_27 (pausa break_start/break_end respeitada; opens_at = próxima abertura real com opens_dia e opens_at_ts; provado Boom ter 16:00 fechada abre hoje 19:00, sáb 23:00 abre segunda 19:00); business_hours_guarda_pausa_2026_10_27 (trigger que impede a app antiga de apagar a pausa ao guardar o horário; provado); conformidade_data_nascimento_so_pessoa_singular_2026_10_27 (_conformidade_em_falta só pede nascimento a NIF de pessoa singular; portão novo trg_conformidade_abrir_loja_parceira: loja parceira aprovada só abre ao público com nome legal, NIF, morada, IBAN PT, nascimento se singular e autocertificação — à Boom faltam nif, iban, nascimento se for em nome individual, autocertificação); produto_e_maior_18_categoria_mista_2026_10_27 (água/refrigerante/sumo em categoria mista deixam de ser +18; "sem alcohol" = sem álcool; comparado em 58 303 produtos: só 4 da Mercadona mudam, nenhum álcool deixou de ser +18). Função de teste produto_e_maior_18_v2_teste ficou (DROP travado) — a sessão apaga-a.
Achado no código: "112 Total" = corrida em lib/stores/restaurant_store.dart (ouvinte de sessão + _init carregam produtos ao mesmo tempo; clear antes do await e sem deduplicar) — também pode dobrar o menu do cliente.
NÃO preenchido de propósito: plataforma_nif/denominacao/sede (aparecem nos recibos e na conformidade do TVDE; mostrariam a empresa como plataforma TVDE sem licença do IMT).
ADENDO 3 colado às 17:06 na sessão Boom Burger (session_01HPEpV8WXaQCL8BCB8FbFfe), depois da demonstração: A) corrida 112; B) pausa na app e painéis; C) ecrã Dados fiscais do parceiro + cartão DAC7 no admin; D) termos do parceiro (legal_terms_versions audience parceiro + TermsGate + admin); E) restaurants.reservation_prepayment_required (default true); F) fotos em falta; G) publicar só quando o Claude.ai escrever "publica" (regra semanal de 25/10); H) e2e_log F0..F99. A sessão manda para o livro (sql-modo-demo-2026-10-27) o SQL da demonstração que mexe em orders, para o Claude.ai rever e aplicar.
Demonstração: Danilo aprovou as 2 bora-trancas (filtro do despacho só para a loja/janela demo; fecho sem custo do pedido demo). O cliente de demonstração pede por uma página escondida do site da Boom (a app não deixa pedir em loja Em breve); o pedido vai até "a caminho" e fecha sem dinheiro.
Para a visita de amanhã 11:00: pedir ao Emanuel NIF, IBAN, data de nascimento se for em nome individual, alergénios, preço do King Elvis, aceitação do contrato, email para o login.
