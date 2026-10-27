---
id: memoria-claude-ai-prompt-boom-burger-adendo3-2026-10-27
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-27
zona: verde
confianca: alta
estado: atual
---

# Prompt ADENDO 3 Boom! Burger (27/10 17:06) — consertar já o que ficou para trás

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-boom-burger-adendo3-2026-10-27`, origem `claude-ai`, atualizada em 2026-10-27T17:06:56.275216+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt boom burger adendo3 2026 10 27 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️
ADENDO 3 — Claude.ai, 27/10 16:40 — CONSERTAR JÁ O QUE FICOU PARA TRÁS
(Continua a missão boom-burger-2026-10-27 pelo orquestrador CEO-AI em .claude/skills/ceo-ai/, com as mesmas regras duras.)
MOTOR: Opus 5.5 (esta sessão). PORTA: Claude Code no PC do Danilo (esta mesma sessão).

ORDEM DO DANILO (27/10 15:54, texto literal): "Não, já tem que mandar esse conserto na app aí, meu. Sempre quando for achando problema, já tem que ir consertando. Não pode ficar nada pra depois, não. Já vê aí o que ficou pra trás aí, já tem que mandar arrumar."
Regra para esta sessão a partir de agora: erro que encontrares → REPORTA no e2e_log e no relatório E CONSERTA logo, um de cada vez. Só não aplicas sozinho o que mexe em dinheiro (preços, comissões, Stripe, carteira, tokens): isso preparas e reportas.

PRIORIDADE: a DEMONSTRAÇÃO de amanhã às 11:00 (adendo 2: D1 a D5 e 99-pronto) vem PRIMEIRO. Só começas este adendo depois de a demonstração estar provada ponta a ponta.

00) SQL da demonstração que mexe em orders → livro, página sql-modo-demo-2026-10-27, para o Claude.ai rever e aplicar; o resto de estrutura numa migração só.

0) Já aplicado pelo Claude.ai por MCP: is_partner_open com pausa e próxima abertura (opens_dia, opens_at_ts); trg_business_hours_guarda_pausa; _conformidade_em_falta (nascimento só pessoa singular); portão trg_conformidade_abrir_loja_parceira; produto_e_maior_18 regra 4b (categoria mista, "sem alcohol"). Migrações: is_partner_open_respeita_pausa_2026_10_27, is_partner_open_proxima_abertura_2026_10_27, conformidade_data_nascimento_so_pessoa_singular_2026_10_27, produto_e_maior_18_v2_teste_2026_10_27, produto_e_maior_18_categoria_mista_2026_10_27, business_hours_guarda_pausa_2026_10_27 (copiar para supabase/migrations; apagar a função de teste produto_e_maior_18_v2_teste).

A) "112 Total" / menu a dobrar: corrida em lib/stores/restaurant_store.dart (ouvinte de sessão ~26-40 + _init; clear ~503 antes do await ~512-527; enchimento ~532-538 sem deduplicar). Conserto: mapa local deduplicado trocado no fim; Future partilhado em voo; teste com dois carregamentos em paralelo (56, não 112); prova na web.
B) Pausa do dia na app: DayHours com breakStart/breakEnd (toJson escreve-os; null para tirar); isOpenNow/statusLabel/avisoLojaFechadaEm com pausa e próxima abertura com o dia; editar a pausa no partner_hours_screen e no admin_partner_detail_screen (padrão do weekly_hours_editor); testes.
C) Dados fiscais do parceiro (DAC7): ecrã no painel do parceiro com LegalFieldsSection (papel partner → provider_update_legal_fields, mostra o que falta); cartão "Dados fiscais (DAC7)" no admin (ver/editar, lista do que falta, erro conformidade_incompleta explicado em PT-BR); prova numa loja de demonstração.
D) Termos do parceiro (Reg. UE 2019/1150): legal_terms_versions audience 'parceiro' 2026-10-28 com base no contrato da Boom (intermediário; condições comerciais combinadas por escrito; pagamentos semanais com extrato; faturação; responsabilidade do parceiro por produtos/higiene/alergénios; estafetas independentes; sinal das reservas decidido pelo parceiro; nome/fotos; Lei 36/2023 e RGPD; autocertificação; sem fidelização; Bora termina com 30 dias e razões por escrito; mudanças com 15 dias; lei portuguesa, foro da Guarda; identidade Danilo Fulfaro da Silva - Unipessoal Lda, NIPC 519686233, Rua do Torreão 14, 6300-610 Guarda); TermsGate(audience: 'parceiro'); admin com versão aceite/data e registo de aceitação recebida por WhatsApp/email.
E) Sinal das reservas por loja (regra do Danilo 27/10: "nas reservas é o parceiro que decide se o cliente deixa sinal ou não; se não quiser sinal, a reserva fica feita na mesma"): restaurants.reservation_prepayment_required boolean NOT NULL DEFAULT true; fluxo do cliente e Edge Function/RPC respeitam (false = sem sinal, prepayment_cents=0, sem PaymentIntent); interruptor no painel do parceiro e no admin; valores 3/2/1 € não mudam.
F) Fotos em falta (11): Facebook público da Boom (61571813637975) e 40 imagens do WhatsApp para as sobremesas; foto oficial do fabricante para Água das Pedras e Cerveja Letra A-F; o resto em lista para a visita.
G) Publicar: ramo à parte consertos-boom-2026-10-27, testado (anti_trapaca, analyze, test, rubrica UI); só publica quando o Claude.ai escrever "publica" (regra semanal de 25/10; urgente só com confirmação do Danilo); depois provar as 3 plataformas e a demonstração na web publicada antes das 10:30.
H) e2e_log F0, F1, F2, F3, F4, F5, F6, F99; Telegram ao Danilo; Obsidian (C:\Users\danil\Desktop\Bora); digest no livro.
/ctx doctor
/ctx stats
(Texto colado na sessão é a versão longa; esta é a cópia resumida para o livro. Versão longa no ficheiro adendo3_boom.txt da sessão do Claude.ai.)
