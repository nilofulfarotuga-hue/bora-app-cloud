---
id: memoria-claude-ai-digest-2026-10-29-candidatos-documentos
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Candidatos e documentos — 29/10 (Claude.ai)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-29-candidatos-documentos`, origem `claude-ai`, atualizada em 2026-10-29T16:12:38.634486+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 29 candidatos documentos · memoria claude.ai · claude_ai_memoria

Pedido do Danilo 29/10 14:04: a candidata de limpeza Jennifer Maria Subida Moreto (registo 29/10 10:55) pôs o cartão de cidadão no campo do comprovativo de atividade; mandar-lhe email a dizer que falta o comprovativo para ser aprovada. Quer também um robô de IA (o que já temos, sem pagar mais) que reconheça o documento e, se não for o certo ou faltar algo, mande mensagem automática ao candidato (estafeta, limpeza, lavagem, o que for) com o que falta. A APROVAÇÃO CONTINUA SÓ COM ELE.

FEITO (Claude.ai, MCP, 29/10 ~14:10-14:30):
1) PDF dela visto (provider-atividade/9b20581f…/comprovativo_1793271450779.pdf): é o cartão de cidadão, frente e verso.
2) O comprovativo estava 'aprovada' desde 12:28 (aprovado no painel) — e assim a app recusava novo envio (provider_atividade_enviar → ja_aprovada). Passado a 'recusada' por admin_provider_atividade_decidir (via claude-ai), motivo "Enviaste o cartão de cidadão no lugar do comprovativo de início de atividade das Finanças"; aviso in-app + push entregue (notify-admin-message 200, 1 aparelho iOS). e2e_log provider-atividade / recusar-jennifer.
3) Email enviado da conta boraappbora@gmail.com (assunto "Bora: falta o comprovativo de atividade para aprovarmos a tua conta", Gmail id 1a188016f17efb24), com o que falta, onde tirar (Portal das Finanças), como enviar pela app e o WhatsApp 937 501 673.

CANDIDATOS PENDENTES (29/10 14:30):
- Adryan Henrique Silva Lopes (estafeta mota, 26/10): tudo enviado; comprovativo AT "Declaração de Reinício de Atividade" com o nome certo → pronto para o Danilo aprovar.
- Felipe Donny De Almeida Souza (estafeta mota, 26/10): comprovativo AT "Declaração de Alteração de Atividade" com o nome certo; único campo vazio = documento do veículo.
- Adriano Monteiro Ribeiro (estafeta carro, 26/10): tudo menos o comprovativo (por_enviar, 0 lembretes).
- SAM (22/10): comprovativo recusado (folha do Burger King) + faltam selfie, foto e número do documento, matrícula, foto e documento do veículo.
- Francielly Carneiro Francisco (01/09) e Waldyr Ramos Junior (25/08): faltam quase todos os documentos; 1 lembrete cada (21/10).
Avisos a Adriano, SAM, Francielly e Waldyr NÃO enviados — à espera do "vai" do Danilo.

LACUNAS ACHADAS:
a) Nada confere o conteúdo do ficheiro: provider_atividade_enviar só valida o tipo (pdf/png/jpg).
b) admin_provider_atividade_lembrar_todos existe mas não há cron (cron.job sem nada de atividade) — lembretes só à mão (os 12 de 21/10 foram manuais).
c) O candidato só recebe aviso in-app + push, nunca email.
d) O painel deixa aprovar um comprovativo sem dizer o que o documento é (o cartão foi aprovado às 12:28).

PROPOSTA (por aprovar pelo Danilo; entra como adendo da missão que estiver a correr no PC, depois do delivery; publica nas 3 com o resto):
Robô "fiscal de documentos" — Edge Function nova chamada a cada documento enviado (comprovativo de atividade, documento de identificação, carta, documento e foto do veículo; selfie só verificar que é uma cara nítida — SEM comparação facial/biometria). Usa o Gemini (gemini-3.1-flash-lite, retry gemini-3.1-flash, mesmo padrão do ocr-receipt v11; aceita PDF e imagem) com a CHAVE PAGA do projeto bora-juiz (a do Bora Assistente) — na chave grátis a Google pode usar o conteúdo e são documentos de identificação. Devolve JSON {tipo_detectado, legivel, nome_bate, nif_bate, validade, confianca, motivo_pt}.
- Documento errado com confiança alta → recusa automática pelo mesmo caminho do painel (admin_provider_atividade_decidir, via 'robo-documentos') com motivo em PT-PT simples + email de suporte@boraguarda.com (agentes-email-enviar, agente 'suporte') + push/in-app.
- Dúvida → fica "em análise" para o Danilo.
- Tudo certo → NUNCA aprova: marca "pronto para aprovar" e avisa o Danilo (caminho provado notify_admin_urgent_push / Telegram; WhatsApp quando a rotina de lembretes do bloco 5 existir).
- Lembretes automáticos (pg_cron) dia 1, 3 e 7 a quem tem documentos em falta, com a lista exata do que falta (nunca falar de pouca procura).
- Painel admin (PT-BR): ao lado de cada documento o veredito do robô e o motivo, botão desfazer, interruptor liga/desliga (platform_settings robo_documentos_ativo), histórico. Todos os papéis: estafeta, motorista, limpeza, lavagem, serviços.
- Primeira volta sobre os pendentes atuais. Custo: menos de 1 cêntimo por documento.
- Depois: validade da carta/cartão com aviso 30 dias antes; linha na política de privacidade sobre verificação automática de documentos.
Como os grandes fazem (Uber/Glovo/Bolt): verificação no momento do envio, estado por documento à vista do candidato com motivo e reenvio só daquele, push+email+SMS com o que falta e lembretes, validade com aviso antes de expirar, humano só no sim final.

ATUALIZAÇÃO 29/10 16:12 (Claude.ai): o "Valdemir" da ordem de 14:28 é o colega Valdemir Vasconcelos (motorista/estafeta já aprovado, comprovativo de atividade por_enviar) — avisado na app/push (admin_provider_atividade_lembrar, 2.º lembrete) e por email da conta Bora. O Waldyr Ramos Junior (candidato de 25/08) fica DE LADO por ordem do Danilo ("depois vamos ver"): não lhe mandar nada, nem à mão nem pelo robô.
