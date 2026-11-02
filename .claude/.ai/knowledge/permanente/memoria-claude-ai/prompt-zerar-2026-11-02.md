---
id: memoria-claude-ai-prompt-zerar-2026-11-02
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-02
zona: verde
confianca: alta
estado: atual
---

# Prompt "zerar" (02/11 15:10): chaves antigas, série de limpeza devolve, peso cobra no cartão + arrumações

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-zerar-2026-11-02`, origem `claude-ai`, atualizada em 2026-11-02T14:52:08.588945+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt zerar 2026 11 02 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️

MOTOR: Opus 5.5 · PORTA: sessão nova no PC do Danilo (Remote Control, pasta bora_app), modo Automático. MISSÃO: zerar-2026-11-02. Fluxo e2e_log: 'zerar-2026-11-02'.

Invoca o orquestrador CEO-AI (.claude/skills/ceo-ai/), a skill protocolo-missao-bora e, para o B1, a skill trocar-chaves-servidor (obrigatória). Lê antes: AGENTS.md, PADRAO_BORA.md, CLAUDE.md e no livro (claude_ai_memoria) erros-aprendidos, regras-do-danilo, stripe-duas-contas, digest-2026-11-01-app-fechar, digest-2026-11-02-chaves-varredura e digest-2026-11-02-travadas-infra. git pull origin autonomous-night-2026-04-29 primeiro (origin em aeb984d ou mais à frente). RAM do PC: medir antes de analyze/test; com menos de 800 MB esperar.

AUTORIZAÇÃO DO DANILO (02/11/2026 14:46, literal, respostas à lista de pendências): "Dois tem que fazer, né? O três. É para fazer também. O 4 é para fazer também." Onde: 2 = desligar as chaves antigas do Supabase (a service_role/anon legadas, a que vazou no GitHub), obrigando os telemóveis com a app antiga a atualizar; 3 = "Parar a série" da limpeza devolve à carteira do cliente as limpezas já pagas; 4 = quando o peso ao quilo sobe e o cliente pagou com cartão, cobrar a diferença no cartão. Carta de autonomia: decides, saltas o que travar (docs/TRANCAS.md) e segues. Outro erro pelo caminho: REPORTA, não corrijas calado. Dinheiro além do que está escrito aqui: não mexes.

B1 CHAVES ANTIGAS (item 2) — seguir a skill trocar-chaves-servidor passo a passo. Inventário de 01/11 (e2e 6001): 38 funções do banco leem vault.service_role_key, 8 usam _service_role_key(), 9 _dispatch_jwt(), 8 crons, 2 da gorjeta; Bloco 3 por aplicar (20261016100000_chave_nova_banco_manda_apikey); .env da VPS e do PC; segredo SUPABASE_SERVICE_ROLE_KEY do GitHub; app_min_supported_version_code. Ordem: (a) tudo o que é servidor passa a usar a chave nova (sb_secret) e prova-se com a ronda do vigia _saude_chaves_lista (50 ok) e com cada caminho de dinheiro; (b) ver que chave a app usa: se as versões antigas trazem a anon legada, sobe app_min_supported_version_code (Android e iOS) para obrigar a atualizar — MAS só depois de a versão nova do iPhone estar À VENDA na App Store (hoje há builds à espera de revisão da Apple); se ainda não estiver, prepara tudo, deixa o passo pronto e regista no e2e_log "à espera da Apple"; (c) só no fim desligar as chaves legadas (Management API, com o token da CLI já autenticada; nunca login no Chrome) e provar outra vez a ronda e os pagamentos. Se algo partir, voltar a ligar as legadas na hora.

B2 SÉRIE DE LIMPEZA (item 3): cancel_cleaning_series (e o botão "Parar a série toda" da app) cancela as limpezas futuras já pagas por MB Way/cartão sem devolver. Passa a devolver cada uma à carteira do cliente usando EXATAMENTE a mesma lógica de reembolso que o cancelamento de uma limpeza só (cancel_cleaning_booking) já usa — mesmas regras, mesmas janelas, mesma divisão saldo/tokens da carteira (platform_settings), sem inventar valores. Prova em rollback com uma série de teste e SELECT; ecrã do cliente a dizer quanto volta.

B3 PESO AO QUILO NO CARTÃO (item 4): quando o estafeta ajusta o peso para cima (estafeta_ajustar_peso) e o pedido foi pago com cartão, cobrar a diferença no cartão guardado com a charge-extra (já está com as duas contas Stripe; usar a conta do pedido). Se a cobrança falhar ou for MB Way, fica como hoje (aviso + carteira). Texto ao cliente em PT-PT e linha no talão/recibo. Prova com cartão de teste no modo de teste, nunca cobrança real; testes de widget. Painel admin: mostrar as cobranças de diferença de peso.

B4 ARRUMAÇÕES (achados de 01-02/11, sem dinheiro):
- update-products: publicar a versão do repo (commit b030296: sem "market" dá 400 e a Mercadona curada só com forcar_mercadona) pela CLI, verify_jwt igual ao ar; prova 400 sem market e o cron do Continente a passar.
- Página "apagar a minha conta" para a Google Play: o robô da Play bate na função delete-account e leva 401 (e2e 6142). Criar www.boraguarda.com/apagar-conta (site bora-site, pasta C:\BoraLocal\projetosflutter\bora-site, publicar com deploy-cloudflare.sh) a explicar como apagar a conta na app e por email, e pôr esse endereço na Play Console (Segurança dos dados → eliminação de conta) pelo Chrome do perfil Bora d9e862e0. Se o classificador travar a Play Console, regista.
- robot_apply_suggestion consegue banir sem motivo de 10 letras: passa a exigir o motivo como admin_suspender_prestador.
- Painel: oferecer suspensão com data de fim também a estafetas (a proteção antiga já não é precisa: a manutenção levanta o is_banned desde 01/11).
- Continente: Melancia Riscada (cnt-5817102) e melões com preço de balança pela regra §59, como a melancia cont-5050572 (backup antes).
- Alarme do filme (fábrica do episódio 1) a gritar de 2 em 2 horas: o filme está PARADO por ordem do Danilo; silenciar esse alarme na VPS até ele mandar retomar (não apagar nada do filme).
- Assinatura da VPS srv1786862: o aviso diz que venceu a 09/10. Ver no hPanel (Chrome, só leitura) a data real e corrigir a data no robô do aviso; se estiver mesmo por pagar, só avisar no relatório (não pagar).

PUBLICAÇÃO: o que mudar na app vai para as 3 (Android, iPhone, web) e prova-se nas 3. Juiz (.claude/juiz/anti_trapaca.py), flutter analyze 0 erros, flutter test verde. git add por caminho.

FECHO: relatório curto em português simples ("fiz isto, falta isto"), digest no livro (digest-2026-11-02-zerar), fecha os separadores que abriste. Termina com /ctx doctor e /ctx stats.
