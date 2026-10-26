---
id: memoria-claude-ai-livro-areas-divulgacao-bora-parte4
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-26
zona: verde
confianca: alta
estado: atual
---

# Divulgação do Bora App ao público — site oficial (bora-site, agora um só, a crescer para várias páginas), vídeos de apresentação e código promocional BEMVINDO (parte 4 de 4)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-divulgacao-bora-parte4`, origem `claude-ai`, atualizada em 2026-10-26T21:22:50.078863+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas divulgacao bora parte4 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/divulgacao-bora.md), copiada a 26/10/2026 21:15 (hora de Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

(continuação, parte 4 de 4)

- ⚠️ SEGUNDO ERRO MEU no mesmo prompt: escrevi que os dois defeitos da ficha da App Store se arranjavam "sem nova revisão". **Não é verdade.** A Apple recusa mudar a CATEGORIA na versão viva (PATCH appInfos READY_FOR_SALE → 409 INVALID_STATE); só entra com versão nova. E o "Idiomas: Inglês" nem sequer estava na ficha — a ficha já tinha primaryLocale pt-PT —, vinha do BINÁRIO (`languageCodesISO2A=[EN]`), corrigido em `ios/Runner/Info.plist` com `CFBundleLocalizations pt-PT,en`
- FEITO 21/09 pelo executor, com prova: `/baixar` refeita (iPhone → só App Store, Android → só Play com referrer, computador → as duas + QR único, "pedir pelo site" passou a linha de 14px, e ganhou recurso sem JavaScript), provada com Playwright nos três aparelhos no endereço público; 28 peças de arte relidas por OpenCV, 26 já apontam a `/baixar?de=qr-flyer` e 0 têm QR velho; robô das redes passa a dizer as duas lojas em tudo; corrigido um QR que tapava o logo do parceiro desde 05/09. Commits bora-site 4e9ff81, 25fd0f5, 96d3ac6; produção 1221baf9; CI verde e versionCode 614
- iOS 1.0.1 criada no App Store Connect (PREPARE_FOR_SUBMISSION, lançamento manual) com Estilo de vida / Gastronomia preparadas. PENDENTE: a build iOS e a submissão — é isso que leva o idioma e a categoria
- [stated] Mr Kebab continua fechado por decisão dele. ACHADO importante: o dono **nunca entrou na app do parceiro** (0 aparelhos com push), por isso nenhum pedido lhe tocaria, e 22 dos 47 produtos estão sem foto — abrir a loja assim seria pior do que mantê-la fechada
- Sabores de Casa entra na rotação das redes a quinta-feira 24/09 às 12:00; ensaio completo aprovado sem publicar
- [stated] 30/09: quer campanha focada no público do IPG (Politécnico da Guarda) — tráfego pago num raio pequeno (menos de 5 km) à volta do IPG, no Instagram, Facebook e Google; vídeos por loja (fast food, supermercados, Goola, loja dos brasileiros, lavagem). Quer ver e aprovar ele próprio os vídeos antes de publicar
- [stated] 30/09 noite: aprovou os 5 vídeos do IPG ("gostei, pode postar tudo"); autorizou pôr o Bora (grupos da Guarda) e o Em Dia nos grupos do Facebook "do jeito combinado"; quer anúncio pago no Google num raio de 3 km da Guarda, a 10 €/dia; a Meta ofereceu-lhe uma semana grátis de um plano e quer ser lembrado de cancelar se aderir
- [stated] 14/10/2026: pediu propaganda da LIMPEZA (profissional de polo verde com o símbolo do Bora a chegar com aspirador e balde), roteiro passado pelo conselho; aprovou às 08:32 ("pode produzir... com o nome do Bora ainda... divulgar ainda hoje"). PROMPT REGISTADO: `PROMPT_reel_limpeza_2026-10-14.md`, MOTOR OPUS, sessão nova no claude.ai/code "Vídeo propaganda Limpeza Bora" (session_01UcwQ4N83C9rq1KwvDa4Zfr), modo Automático, fluxo e2e_log 'reel-limpeza-2026-10-14'. Scope: reel 20 s + variante 9 s, personagem de IA marcada como IA, ecrã real da app, fiscal ≥80, publicar às 18:00 no Instagram/Facebook + grupos da Guarda, sem dinheiro em anúncios. Estado: a correr
- [stated] 15/10/2026: autorizou registar a app (Android e iPhone) na Meta, para os anúncios pagos poderem ter o botão "Instalar" direto à loja (supera "a app não está registada no Facebook como app"); quer que os anúncios levem o público a baixar a app
- [stated] 17/10/2026: pediu reel dos FAVORES, bem detalhado, com farda e bag do Bora; foco em farmácia, senhora que não pode sair de casa e mãe com bebé (pellets só de passagem, no fim); ecrãs da app um pouco mais lentos que no da limpeza. PROMPT REGISTADO: `PROMPT_reel_favores_2026-10-17.md`, MOTOR OPUS, sessão nova "Reel Favores Bora" no claude.ai/code (session_0196uYecJCSU5cZrxuwesuzH, ambiente bora-app-cloud do PC, modo Automático), fluxo e2e_log 'reel-favores-2026-10-17'. Scope: reel ~28 s + versão 9 s, só produzir e mandar ao Telegram; publicar só depois do ok dele. Estado: concluído — vídeos entregues no Telegram às 16:29 e aprovados por ele às 17:10
- [stated] 17/10/2026 17:10: aprovou os dois vídeos dos Favores — "Pode publicar no Instagram e nos grupos". PROMPT REGISTADO: `PROMPT_publicar_favores_2026-10-17.md`, MOTOR OPUS, sessão nova no claude.ai/code (session_01JHqeSt7xzAQuqgZEMH5WNH, ambiente bora-app-cloud do PC, modo Automático), fluxo e2e_log 'reel-favores-2026-10-17' (passos 10 a 15). Scope: publicar reel + story no Instagram e no Facebook pela API da Meta, sem anúncios nem mexer no vídeo, e preparar a folha dos grupos; o clique de Publicar nos grupos ficou com a Claude.ai. Estado: Instagram e Facebook no ar às 17:27–17:30; 4 grupos da Guarda feitos pela Claude.ai até às 19:10, 1 deles pendente de aprovação dos admins; as 5 publicações do dia gastas (inclui 1 post das 18:00 que não foi da Claude.ai); detalhes no e2e_log
- [stated] 22/10/2026 22:14: mandou fazer ("Faz") o reel do CARRO VOADOR — carro de entregas com o logo do Bora a voar, para apanhar o hype do Roadster da Tesla. PROMPT REGISTADO: `PROMPT_reel_carro_voador_2026-10-22.md`, MOTOR OPUS, porta Claude Code no PC (bora-app-cloud), fluxo e2e_log 'reel-carro-voador-2026-10-22'. Scope: reel 15 s + 8 s, só produzir e mandar ao Telegram; publicar só depois do ok dele. Estado: o classificador bloqueou-me a abrir a sessão em claude.ai/code; ficheiro entregue a ele para colar
- [stated] 26/10/2026 18:16: REPROVOU a versão carrinha do reel do carro voador (feita 26/10 na missão geral-sábado, Telegram 10795/10796) — o carro é o NOVO ROADSTER DA TESLA com o emblema da Bora (sem o T nem o nome Tesla; só orgânico). PROMPT REGISTADO: `PROMPT_reel_tesla_bora_2026-10-26.md`, MOTOR OPUS, sessão nova no claude.ai/code "Tesla Roadster Bora reel production" (session_016wANLzhodav6jXBARFT1u4, Remote Control bora-app-cloud do PC, modo Automático), fluxo e2e_log 'reel-tesla-bora-2026-10-26'. Scope: refazer o reel 15 s + 8 s e mandar ao Telegram; publicar só com o ok dele. Estado: a correr (Flow da conta Bora com ~6 créditos)
- [stated] 26/10/2026 20:14: pôs os 25 € na conta de anúncios e mandou seguir o plano (anúncio Guarda Primeiro, 5 dias)

