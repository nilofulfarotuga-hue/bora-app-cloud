---
id: memoria-claude-ai-livro-areas-filme-animacao-v3
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-10
zona: verde
confianca: alta
estado: atual
---

# Continuação de filme-animacao a partir da 3.ª reprovação (31/08) — estado da produção v3 do Ep1 "A Semente da Luz", prompts entregues e o que trava; ler junto com filme-animacao (parte 1 de 3 — continua em livro-areas-filme-animacao-v3-parte2…)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-filme-animacao-v3`, origem `claude-ai`, atualizada em 2026-11-10T02:16:57.734975+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas filme animacao v3 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/filme-animacao-v3.md), copiada a 2026-11-10 02:16 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: filme-animacao-v3
description: Continuação de filme-animacao a partir da 3.ª reprovação (31/08) — estado da produção v3 do Ep1 "A Semente da Luz", prompts entregues e o que trava; ler junto com filme-animacao
sources: [cowork]
aliases: [Bora Studio v3, episodio1_final_v3, retoma v3]
---
Contexto: [[filme-animacao]] tem o cânone, as leis (R27–R60) e o histórico até 30/08. Este ficheiro continua a partir da 3.ª reprovação. Fábrica em `C:\BoraLocal\BoraStudio` (PC novo "Danilo"); tarefas agendadas BoraStudioRelogio + BoraStudioCondutor de 15 em 15 min.

## 31/08 — 3.ª reprovação, caderno completo
- Caderno em `decisions/2026-08-31-o-dono-reprovou-o-caderno-completo.md`; 14 queixas medidas em `queixas_v3` (producao.db). Régua que ele deu: Superbook. Autorizou reescrever o roteiro
- Feito depois: fiscais e30–e33 (música, silêncio, fluidez, identidade), e34 latido real 3/3, e35 foley da imagem (32 faltas), e38 biblioteca foley CC0 (Openverse→Freesound, licença confirmada na página; BBC fora por licença; Ollama não ouve 2/4; ouvido local faster-whisper 6/6), e11b fiscais de fala ressuscitados, Diretor a 854×480/24 fps

## 02/09 — vento colhido; fábrica parada 50 h; PROMPT-RETOMA-V3 entregue
- [stated] Correu a prova do portão do vento (14/14) e o vento colheu 4. Perdeu o chat e o contexto do Claude Code; pediu ao Claude.ai puxar tudo, ver o que falta e mandar UM prompt para finalizar de vez; continua "a fundo" amanhã
- Portão do vento: `sustentacao` media contra o PICO (um pássaro em 400 s derrubava o ficheiro); passou a ocupação + ataques/s contra o próprio nível; tecto 300→900 s; rejeitados passam a ser gravados com números (`--distribuicao`). Prova `tests/prova_portao_sustentado.py` 14/14. Córtex ref-a5270b
- Lido do disco pelo Claude.ai (sessão sem terminal no PC — só lê/escreve ficheiros): desde 01/09 10:12 o Gemini dá `403 Spend cap breached` (projecto 765097014497, cap de €1 de 13/08) → e07b/Diretor/ouvido/e35/e38 --ouvir à espera; condutor morre em TODOS os tiques com `database is locked` (agentes/espera.py:63, 327×); cão de guarda escreveu 167× PRECISA_DANILO a culpar o Kaggle (errado). Fila promete e36_leitos_por_batida, e37_roteiro_buracos, e39_colocar_foley que NÃO existem. ESTADO.md ainda dizia "ENTREGUE 30/08" — foi por isso que ele se perdeu
- PROMPT LOG: 2026-09-02 — `C:\BoraLocal\BoraStudio\PROMPT-RETOMA-V3-FINALIZAR-2026-09-02.md` (OPUS 4.7, sem ceo-ai) — F0 ESTADO verdadeiro · F1 lock SQLite + cão de guarda diz a causa certa + uma verdade para a quota · F2 duas chaves Gemini (JUIZ = projecto sem faturação a €0; IMAGEM = com cap, só fotogramas; linha de dinheiro ao Danilo sem parar a cadeia) · F3 e38 --ouvir, e39, e36, e37, abertura · F4 12 fotogramas + 39 boca×fala + fluidez por lotes · F5 rejulgar e entregar v3 · F6 provar 2 tiques sozinho · F7 registar — estado: ENTREGUE, por correr. Córtex ref-cfafb3
- Decisão de dinheiro pendente do Danilo: subir o cap `Bora - cap Gemini API` (€1/mês) para regenerar 12 fotogramas — ver [[custos-google-cloud]]
## 05/09 — a quota deixa de ser desculpa
- [stated] O Danilo subscreveu o plano Google AI Plus (€0,49 no 1.º mês, €4,99 depois), que traz Veo e Nano Banana Pro dentro do Gemini
- ⚠️ CORRIGIDO 05/09, MEDIDO: o AI Plus NÃO dá quota de API — 429 nos três modelos de imagem. É subscrição da APP do Gemini, não da API. Fica sem efeito o que aqui estava escrito, de que desbloqueava fotogramas/e07b/Diretor/ouvido/e35/e38. Não faz falta: o Kaggle gera sozinho (trouxe 12 fotogramas a 05/09) e a cascata abaixo continua a valer a partir do 2.º degrau

## 05/09 — o que trava mesmo o filme: as duas irmãs trocadas pelo cabelo
- 39 dos 128 planos (30%) param no MESMO defeito: a Tabita sai de cabelo solto (assinatura da Tailine) e a Tailine de coques (assinatura da Tabita). Não é quota nem base de dados. É a R08 do cânone (Tabita↔Tailine confundíveis) a cobrar-se — já tinha aparecido a 04/08 e a 25/08 com outros nomes
- Estava escondido atrás de um defeito do juiz, entretanto corrigido: `regras_duras()` entregava ao juiz do fotograma regras da secção 1.4 do `gosto_danilo.md` ("fundo branco liso, só o personagem"), que são de como se constrói a FICHA e nenhum plano de cinema pode cumprir → planos regeneravam para sempre. 19 regras → 7, prova 15/15 com defeito plantado
- Cirurgia com máscara na cabeça: mecanismo provado 16/16, mas a LOCALIZAÇÃO deu 0 caixas utilizáveis em 5 planos reais (uma faixa de 69% do quadro; outra pousada em duas crianças de fundo). Travada — caixa errada com denoise 0,90 não falha, acerta, e estraga um plano bom
- DECISÃO MINHA, contra o que o executor propôs: NÃO aceitar o cabelo como está (as duas irmãs deixavam de se distinguir, e a criança reconhece pela silhueta). E não resolver por PALAVRAS na ficha — o princípio central deste projecto, provado 6+ vezes, é que identidade se trava com IMAGEM. Caminho dado: âncora de imagem própria por irmã na geração + segundo diferenciador que ele tem de IR PROCURAR aos planos já aprovados (se inventar um novo, os 89 aprovados ficam fora da ficha)
- [stated] CASCATA DE FERRAMENTAS a usar na fábrica (também escrita no Córtex, página `estado-vivo`): imagem = API do Gemini enquanto houver quota → Gemini web/Nano Banana pelo clique → ChatGPT web pelo clique; vídeo = Veo no Gemini web pelo clique → Bora Studio na GPU do Kaggle quando o Veo esgotar ou o plano for cancelado (quota do Kaggle renova ao sábado). O tecto de €1 do projecto antigo NÃO se mexe e deixa de ser o caminho
- [stated] Fica sem efeito a decisão de dinheiro pendente de subir o cap de €1 para regenerar os 12 fotogramas — resolve-se pelo plano novo

## 07/09 — Vibes (Meta) acrescentado à cascata de vídeo
- [stated] REGRA DELE ao decidir sobre o Vibes: "não sei se é bom substituir nada, é bom ACRESCENTAR, fazer uma hierarquia; se esse aí for melhor que algum, põe lá pra testar, e vê qual que é melhor, e deixa a hierarquia" — motor novo nunca substitui, entra em último, e a ordem sai de medição; delegou a decisão ("é você que decide, não vai por mim")
- Apurado por pesquisa: Vibes é da Meta, grátis sem plano pago (Movie Gen, até 1080p com som), na Europa desde nov/2025, em vibes.ai / meta.ai/vibes; faz imagem→vídeo. A extensão de terceiros "Vibes Automation" (id mikmoieklgpbgikeemkfffncmcmnhhab) existe mas as avaliações de jul/2026 dizem que encrava no 1.º prompt em lote → adaptador próprio pelo navegador do executor, extensão só plano B
- PROMPT LOG: 2026-09-07 — PROMPT-CASCATA-VIDEO-VIBES-2026-09-07.md (OPUS 4.7, sessão NOVA na pasta borastudio, sem ceo-ai) — F0 estado verdadeiro · F1 cascata como config `canon/cascata_video.yaml` espelhada na VPS · F2 adaptador Vibes pelo Chrome do executor · F3 prova dos 3 motores com 5 planos aprovados + defeito plantado · F4 ordenar por medição e gravar no Córtex · F5 mesma prova para as redes com fiscal_video.py · F6 2 tiques sozinho · F7 registar — estado: CORREU na noite de 07→08/09
- Medido (mesmo fotograma, mesmo prompt, com defeito plantado a validar os instrumentos): Veo 1280×720, 10 s, com som, enquadramento 0–0,1%, sinal das duas irmãs 2/2 · Kaggle/Wan 768×432, 5 s, sem som, deriva até 4,5%, 1/2 — o rosa da Tabita cai de 2,485% para 0,148% e desaparece. Ordem confirmada e agora em config (`canon/cascata_video.yaml` + `agentes/cascata_video.py`, queda automática e telemetria): 1 Veo, 2 Kaggle, 3 Vibes
- Dois tectos medidos pela 1.ª vez: o Veo trava a ~2 clipes por janela; o Kaggle recusou as corridas 356–360 por quota semanal esgotada. Ficou sem motor de VOLUME — daí o Colab (0 de 30 h, nunca usado) entrar como degrau novo e os planos com as duas irmãs passarem a ir pelo motor que guarda o sinal
- Vibes NÃO chegou a gerar: para num botão que cria conta da Meta e aceita termos — só o Danilo pode clicar. Fica vivo na config, não apagado. Recomendação dada: usar a conta pessoal dele, não a `boraappbora`, que é a que corre os anúncios

## 30/09 — Sussurrador muda de forma por era
- [stated] Regra do cânone: o Sussurrador, depois de cair, é uma figura diferente em cada lugar/época — no jardim é a serpente; nos tempos atuais é uma pessoa de boa aparência — mas é sempre ele. Delegou a decisão do manto do recém-caído ("pode decidir aí pra mim")
- [stated] 30/09 — 4.ª reprovação: personagens mudam de cor de pele/cabelo entre planos (Tailine), vozes feias, sem música de entrada, canção do Gustavo horrível. Quer RECOMEÇAR DO ZERO sem o Kaggle ("está a atrapalhar"), reaproveitando só imagens, nomes e fichas dos personagens, roteiro novo empolgante; régua visual = desenho "Turminha da Graça"; música empolgante estilo Família Madrigal (Suno ou outra IA), com música nas várias partes; nível Disney. Pediu para avaliar o Kimodo (NVIDIA, animação 3D por texto)
- [stated] 30/09 — o Ep1 NÃO é para publicar, é só para ele assistir em casa. Vozes que quer: estilo Turminha da Graça — Tabita↔Liquinha, Tailine↔Florzinha, Gustavo↔Zequinha, Antony↔o 4.º menino; NÃO quer a voz das filhas reais; aceita voz de criança de desenho muito parecida, desde que não robotizada. Quer tudo de uma vez, sem prova à parte
- [stated] 30/09 — o Ep1 tem de ter 15 a 30 minutos (não quer vídeo curto); diz que o contexto e a história do episódio estão bons — é aproveitar o que já foi feito e torná-lo divertido e empolgante para as crianças aprenderem a Bíblia
