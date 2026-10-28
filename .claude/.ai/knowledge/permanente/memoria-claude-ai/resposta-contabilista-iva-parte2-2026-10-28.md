---
id: memoria-claude-ai-resposta-contabilista-iva-parte2-2026-10-28
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-28
zona: verde
confianca: alta
estado: atual
---

# Hugo (15:54-15:55): faturas emitidas pelo escritório, não ficar no art. 53.º, IVA não mexe na margem — e as contas de outubro com IVA

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `resposta-contabilista-iva-parte2-2026-10-28`, origem `claude.ai 28/10 16:10`, atualizada em 2026-10-28T16:05:08.598327+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: resposta contabilista iva parte2 2026 10 28 · memoria claude.ai · claude_ai_memoria

28/10 15:48 mandámos ao Hugo (grupo Contabilidade, número pessoal do Danilo, sem saudação): qual é o programa e se liga à app; se compensava ficar isenta até aos 15 mil.
Resposta do Hugo (15:54-15:55):
1) "se necessitares de emitir faturas, terás que enviar a informação para nós emitirmos os documentos" — o escritório emite; não há programa para a app usar.
2) "não me parece favorável ficar no artigo 53.º, porque perdes o direito à dedução nas tuas despesas".
3) "o IVA é um imposto que cobras aos teus clientes e entregas ao estado".
4) "não tem implicações na tua margem".
Ordem do Danilo 15:57: NÃO responder ao Hugo ainda; explicar-lhe o que o Hugo disse e dar a minha opinião, a pensar em ganhar dinheiro.

Contas de outubro (bora_invoices_pending + orders, SQL 28/10): 15 entregas/Favores; clientes pagaram 272,19 €; parte da Bora (tudo menos a loja) 103,99 €; estafetas 78,72 €; lucro da Bora 25,27 € (média 1,68 €/pedido). Com o modelo de novembro e IVA normal: IVA 19,45 € -> sobram 5,82 € (0,39 €/pedido). Favor típico: cliente 6,00, estafeta 5,00, Bora 1,00 -> IVA 1,12 -> prejuízo 0,12 € por Favor. Boom 21 € a 3 km: sobra 1,17 € (era 2,45). Entrega grátis 30 € a 4 km: dinheiro +0,35 €, cartão -0,38 €.
Opinião dada: aceitar o regime normal; o "não mexe na margem" só vale se o IVA estiver por cima do preço — os preços da Bora foram feitos sem IVA; proposta: pôr o IVA por cima de tudo o que é da Bora (+23% só na parte da Bora; loja e estafeta iguais), precisa de "autorizo" com os números certos; não voltar ao estafeta a faturar direto ao cliente (cada estafeta teria de faturar cada cliente); faturas: enquanto há poucos pedidos, o escritório emite a partir da lista que o sistema lhe manda; programa automático quando crescer.
Erro achado: bora_invoices_pending.iva tem por defeito "IVA — regime de isenção (art. 53.º CIVA), M10" e a nota do admin_monthly_closeout diz "IVA isento (art. 53.º)". A partir de 01/11 tem de ser "IVA 23% incluído — regime normal". A migração iva_normal_faturas_bora_2026_10_28 (gatilho _bora_invoice_iva_texto + troca da frase no fecho) foi travada daqui (cancelled) — vai no próximo prompt ao Claude Code.
