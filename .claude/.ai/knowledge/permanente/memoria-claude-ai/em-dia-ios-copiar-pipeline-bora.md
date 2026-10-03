---
id: memoria-claude-ai-em-dia-ios-copiar-pipeline-bora
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-22
zona: verde
confianca: alta
estado: atual
---

# Em Dia / iOS: nao escrever o CI do zero, copiar o da Bora que ja funciona

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `em-dia-ios-copiar-pipeline-bora`, origem `claude-ai`, atualizada em 2026-09-22T11:50:12.352771+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: em dia ios copiar pipeline bora · memoria claude.ai · claude_ai_memoria

Achado a 22/09/2026 ao ler o e2e_log da Bora.

A Bora JA TEM um pipeline de iOS que funciona ponta a ponta: build_ios.yml em runners macOS, IPA assinado (~53 MB), altool com UPLOAD SUCCEEDED, build a aparecer no TestFlight e testador com INSTALLED. A build 132 da Bora subiu assim a 22/09 as 01:45.

Por isso o workflow de iOS da Em Dia deve ser COPIADO do da Bora e adaptado, nao escrito de novo. So mudam: bundle id (com.boraguarda.emdia), apple_id do upload (6814807320), o nome do esquema/app e os segredos de assinatura.

ARMADILHAS JA PAGAS PELA BORA, para nao as pagar outra vez na Em Dia:
1. TECTO DE TEMPO. Com o Firebase iOS 12 cada compilacao demora o dobro. A corrida 129 foi cancelada pelo tecto de 75 min; tiveram de o subir para 120. Por o tecto do job de build em 120 minutos desde o inicio.
2. COMBOIO DE VERSAO FECHADO. A corrida 131 falhou com altool 90062/90186: o comboio da 1.0.1 estava fechado porque a build ja aprovada tinha aquele CFBundleShortVersionString. Na Em Dia a versao da loja e 1.0 e ainda nao ha nada aprovado, por isso nao ha problema AGORA, mas a regra fica: quando uma versao e aprovada, o proximo envio tem de subir o CFBundleShortVersionString.
3. FLAKE DO flutter drive. A corrida 130 falhou porque o flutter drive lancou a app mas nunca apanhou o VM service (30 minutos mudo). Resolveram com 2 tentativas no passo. Se a Em Dia tiver passo de varredura, por 2 tentativas.

AINDA EM FALTA NO LADO DA APPLE (Em Dia): a build assinada e as capturas de ecra de iPhone 6,5 polegadas (1242x2688 ou 2688x1242 ou 1284x2778 ou 2778x1284). Sem build nao ha capturas reais.
