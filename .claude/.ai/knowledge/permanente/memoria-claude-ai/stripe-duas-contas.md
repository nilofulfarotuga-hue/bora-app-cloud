---
id: memoria-claude-ai-stripe-duas-contas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-01
zona: verde
confianca: alta
estado: atual
---

# Duas contas Stripe — empresa e pessoal (01/11/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `stripe-duas-contas`, origem `claude.ai`, atualizada em 2026-11-01T22:02:28.994495+00:00).
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
