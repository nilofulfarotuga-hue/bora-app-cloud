---
id: memoria-claude-ai-em-dia-iphone-identificador
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-22
zona: verde
confianca: alta
estado: atual
---

# Em Dia / iPhone: identificadores da Apple (bundle id, app id, SKU)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `em-dia-iphone-identificador`, origem `claude-ai`, atualizada em 2026-09-22T11:32:07.859568+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: em dia iphone identificador · memoria claude.ai · claude_ai_memoria

ESTES VALORES SAO PERMANENTES. Nao inventar outros, nao mudar.

- Bundle identifier (iOS): com.boraguarda.emdia
- Apple App ID (apple_id, para upload/altool/fastlane): 6814807320
- SKU: emdia-ios-001
- Nome na loja: "Em Dia: Recibos e Impostos"
- Idioma principal: Portugues (Portugal)
- Team ID: 6ZS4ZU3L5P
- Conta App Store Connect: Danilo Fulfaro da Silva

PORQUE NAO E pt.emdia.app
A Apple RECUSOU pt.emdia.app duas vezes: "Nao foi possivel encontrar um ID de aplicativo com o identificador pt.emdia.app. Insira uma sequencia diferente." O dominio emdia.pt nao e do Danilo (pertence a SOPHISKAKI LDA), por isso esse prefixo nao passa. Usei com.boraguarda.emdia, DNS invertido de um dominio que ele tem (boraguarda.com).

CONSEQUENCIAS QUE TEM DE SER TRATADAS NO CODIGO
1. O bundle identifier no projecto Xcode (ios/Runner.xcodeproj, PRODUCT_BUNDLE_IDENTIFIER em todas as configuracoes: Debug, Release, Profile) tem de ser com.boraguarda.emdia.
2. O GoogleService-Info.plist tem de ser gerado para uma app iOS registada no Firebase com o bundle id com.boraguarda.emdia. Se o plist tiver outro bundle id, o Firebase Messaging nao arranca e a app rebenta no arranque.
3. O Android continua pt.emdia.app. Android e iOS ficam com identificadores diferentes de proposito. Isto nao e um erro, nao "corrigir".
4. No workflow de CI de iOS, o apple_id do upload e 6814807320.

ESTADO A 22/09/2026
Registo criado no App Store Connect, em rascunho. Nada enviado para revisao. Falta: build iOS assinada, screenshots, e as respostas da ficha da loja.
