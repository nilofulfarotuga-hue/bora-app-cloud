---
id: memoria-claude-ai-livro-areas-filme-animacao
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Série cristã infantil "A Semente da Luz" — cânone, elenco, e estado da produção do Episódio 1 (parte 1 de 4 — continua em livro-areas-filme-animacao-parte2, -parte3, -parte4)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-filme-animacao`, origem `claude-ai`, atualizada em 2026-10-23T05:51:23.729253+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas filme animacao · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/filme-animacao.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: filme-animacao
description: Série cristã infantil "A Semente da Luz" — cânone, elenco, e estado da produção do Episódio 1
sources: [chat]
aliases: [filme de desenho, Bora Studio, sistema de animação]
---

## Como o Danilo trabalha
- [stated] Sistema 100% autônomo: "Eu não vou entrar pra NADA. Só pego o vídeo final." Um representante_danilo.py decide tudo via canon/gosto_danilo.md
- [stated] Respostas em PROSA corrida legível (ele ouve por leitura de voz), curtas, sem jargão. Manda foto do terminal; Claude responde com o texto exato pra colar
- [stated] Opera o PC pelo celular (Chrome Remote Desktop). PC fraco: 4GB RAM, sem GPU — OOM mata processos
- [stated] Quer MUITOS agentes especializados, um por função, estilo departamento da Disney
- [stated] VALIDAÇÃO SEMPRE EM ECRÃ GRANDE — o telemóvel escondeu o defeito do Wav2Lip e ele aprovou o que depois reprovou

## Cânone fixo
- ELENCO — todos PRIMOS, avó Mônica é avó de todos. Mateus 12, Gustavo 10, Antony 10, Tabita 9, Kaká 9, Tailine 7, Rafinha(menina) 7, Laura 6, Luara 4. Pais: Antony=Alan+Daniela; Gustavo=Irivaldo; Tabita/Tailine(irmãs)=Danilo+Letícia; Mateus/Luara/Laura=Denise; Rafinha=Rafael+Alice. Professora Sônia. Tios Davi e Daniel
- Trindade em 3 PESSOAS (Deus Pai=vovô barba branca; Jesus jovem; Espírito Santo=PESSOA, nunca pomba). A VOZ DA CRIAÇÃO É A VOZ DO DEUS PAI (quem diz "haja luz" é o Pai; R17 proíbe FUNDIR as três, não proíbe o Pai falar). Cão Vento. Vilão O Sussurrador (35-40 anos, ALTO)
- Avó Mônica REAL: NÃO é velhinha — mulher de meia-idade, Danilo diz "uns 50 mais ou menos" (a ficha diz 40); cabelo caramelo comprido solto, t-shirt branca, jeans rasgados. A IMAGEM no computador é a verdade. Ficha nasce SEMPRE de inspecionar a imagem, nunca da palavra "avó"
- Teologia: Gap Theory é escolha editorial. Nada fora da Bíblia como afirmação; nada que faça pais duvidarem; divertido
- Filosofia: diversão primeiro, ensino por consequência (nunca sermão). Nunca escuro/assustador. PT-BR sempre; criança soa a criança DE DESENHO (atuada, nunca lida)
- Lúcifer/anjos: antes da queda = anjo de luz glorioso, NUNCA sombra. Guerra no céu = anjo contra anjo, zero sangue. Forma humanoide só DEPOIS de cair. Serpente do Éden COM PERNAS, simpática
- Sussurrador: assinatura em TODAS as formas = sorrisinho de canto + sombra meio segundo atrasada + o olhar. NUNCA a roupa (fato só era moderna). Manto do recém-caído = cinza-chumbo
- Escala: criança NUNCA maior que planeta/montanha. Terra mantém-se esfera
- Estilo: caricatura 3D Encanto/Pixar. Os 4 protagonistas (feitos pelo Danilo no ChatGPT) são a RÉGUA — tudo se compara visualmente com eles
- Ep1: teaser → tema cantado → escola → casa da avó em mudança → selo → portal → CRIAÇÃO → 1ª aparição do Sussurrador → gancho Ep2 (Arca). Bordão "fica junto". Alvo 15-20min
- 4 canções aprovadas com letras completas em canon/cancoes.md: "Alguém Me Responde", "Um Dia Vão Ver", "Quem São Eles?", "Coincidência"
- R33: a promessa de Gn 3:15 tem de ser DITA no Ep1 — dá nome à série

## PRINCÍPIO CENTRAL (confirmado 6+ vezes)
**Identidade e enquadramento travam-se com IMAGEM, nunca com palavras.** Valeu para: os clipes (a PixVerse não ancorava e trocava personagens inteiros); o animador novo (1º fotograma = o nosso jpg); as 3 imagens do Sussurrador (só bateram quando a 1ª virou âncora das outras); a condução de câmara; os fiscais de visão (só o método imagem-contra-imagem funciona).

## PADRÃO-MESTRE (6 ocorrências) — arestas
Material novo produzido → consumidor a apontar para o VELHO → nada dá erro porque o velho ainda funciona. Casos: vozes v6 vs audio/v5 · bocas vs oval procedural · licença dos dados vs do motor · arte v3 vs v1 · ambiente_fixo.py construído e não ligado · leitos aprovados vs pasta v5 mais alta.
CURA: material velho vai para QUARENTENA (apontar para ele FALHA ALTO) + índice único de assets + fiscal de arestas antes de cada geração e montagem ("quem o lê, lê ESTE?"). Recurso silencioso a material não aprovado = código morto que só faz mal; fora, e falhar alto.

## Lições estruturais gravadas (R27-R46)
- R42: MEDIR O CONTINENTE NÃO É MEDIR O CONTEÚDO — duração/sincronia/níveis mediam a embalagem; ninguém media o que a voz DIZ
- R27: nenhum diagnóstico/log pode derrubar o que observa (matou o teste de lip-sync; abortou a contabilidade de 20 clipes)
- R28: sonda tem de EXERCITAR a operação real, não checar disponibilidade ("cuda_disponivel: True" era verdade e inútil)
- R31: um caso real nunca serve de controlo — só transformações aplicadas por nós
- R43: gerar N amostras independentes para trocar a 24fps CINTILA — é estrutural. Gerar UMA e derivar as outras
- R45: a contaminação de licença entra pelos DADOS DE TREINO, não só pelos pesos
- R46: trocar de motor 5 vezes não é persistência se a causa é sempre o ambiente
- Um comando cujo CÓDIGO DE SAÍDA ninguém lê é um comando que não correu
- O olho apanha o que o número não apanha: 3x num dia o medidor aprovou e a folha de contacto reprovou
- Falha silenciosa é sempre pior que ruidosa

## Produção — pipeline 100% grátis
- PixVerse cancelada. GPU grátis: Kaggle (12h/sessão, 2×T4, 30h/semana) + Colab + Lightning
- Animador: Wan 2.2 I2V com Lightning LoRA (4 passos = 7,6x mais rápido, sem perda visível). 768×432 (16:9 real)
- LIP-SYNC: Wan 2.2 S2V-14B (áudio guia o vídeo, nativo, sem remendo) — APROVADO pelo Danilo em ecrã grande. Wav2Lip REPROVADO (mancha inerente ao método). Custo real: 653s por clipe S2V, não 280
- VOZES: XTTS-v2 e F5-TTS RISCADOS (licença não-comercial pelos dados de treino). CHATTERBOX (MIT) é o motor em uso — amarelo, não verde: risco de terceiro, não proibição nossa. Caminho definitivo = treinar VITS de raiz sobre CML-TTS pt + TTS-Portuguese + MLS pt (78h CC BY 4.0) = 90-140h em 2×T4, 3-5 semanas
- Música: 9 leitos ACE-Step aprovados, filtrados e nivelados. Canções ainda com voz genérica
- Cada fala leva DIREÇÃO DE ATOR escrita do beat emocional (é o que cura o "voz de robô"); intensidade SUBSTITUI a entrega, nunca soma (dizer "sussurrando" e "aos gritos" faz o modelo escolher o meio-termo neutro)
- Texto sanitizado: reticências/maiúsculas/travessões faziam a voz LER A PONTUAÇÃO em voz alta

## Estado do Ep1 (03/08)
- 190/190 clipes, 16m41s. 150 falas regeneradas com Chatterbox + direção de ator, todas passam o fiscal do dito
- Bocas (9 visemas) para 9 personagens, Tailine incluída (38 falas, a que mais importa). 5 personagens com 1-3 falas ficam para o fim
- DIRETOR FINAL funciona e tem veto — 89 erros na 1ª passagem (som 41, sincronia 18, editor 15, gosto 10, imagem 3, decupagem 2)
- ⚠️ BLOQUEIO ATUAL: 36 das 150 falas são CORTADAS a meio (61,2s de diálogo perdido) — clipes S2V saem com ~5s fixos e 45 dos 88 planos falados precisam de mais. Pior caso: a fala da promessa (Gn 3:15/R33) desaparece inteira. DECISÃO DE CLAUDE: partir os planos, com triagem (excesso <0,8s abranda vídeo; 0,8-3s parte em dois; >3s vira plano+contra-plano) e prioridade absoluta ao b6_s19. E criar fiscal "a fala cabe no plano" a correr na DECUPAGEM, não depois de montar
- Lista do Danilo por resolver: Mateus na sala de aula, abertura antes do cartão (fiscal de estrutura já reprova: cartão aos 33,7s), "segura na minha mão" sem dono, música por cima de fala, Gustavo sem reação
- Inconsistência de arte por julgar: avó Mônica, Daniel e Rafinha lêem-se fotorrealistas ao lado de Sônia e Alan (3D estilizado)
- Detalhes do estúdio de agentes em [[bora-studio-agentes]]

## 04/08 — o fiscal não falhou, o filtro é que deitou fora a prova
- O `b3_s12_00_mateus.wav` ("Falei." → "Ali.") ESTAVA na varredura com erro_v7=1,00 e erro_v6=0,00 — o sinal mais forte possível. Foi filtrado fora pela regra `len(texto) > 15`, com o raciocínio "em fala curta uma palavra errada dá 1,00 e não quer dizer nada". Isso vale para RUÍDO, mas o controlo que remove a dúvida existia e não foi usado: **o v6 diz a frase bem**
- PRINCÍPIO NOVO: quando uma versão nova substitui uma velha, **a velha é o CONTROLO**. Fala curta que o motor antigo acerta e o novo erra não é ruído da métrica — é defeito. Critério corrigido: o controlo é o v6, não o comprimento
- Resultado: de 7 falas más passa a **16**, e as 9 novas são todas curtas — incluindo **"Haja luz."** (a fala central da Criação) e **"Fica junto?"** (o bordão que fecha o episódio)
- Cruzamento dos 26 do Diretor: só 3 caem em falas que a transcrição também dá como más — incluindo a que o Danilo confirmou ao ouvido. Os outros 23 mantêm veto até a repesca correr e o Diretor repetir a passagem (se ele reagia a fala errada, o número desce sozinho — isso é o teste, não a opinião)
- ⚠️ QUOTA SEMANAL DE GPU ESGOTADA (30h) — a reanimação dos 49 clipes comeu-a. A repesca das 16 fica em fila até domingo
- AVÓ MÔNICA, ficha escrita do ficheiro: mulher de meia-idade ~50, corpo cheio, de pé e direita. Cabelo castanho-caramelo comprido, solto, ondulado, madeixas claras. T-shirt branca com bolso de padrão aos rabiscos, jeans com vários rasgões, ténis brancos baixos, argolas pequenas. NADA de grisalho, cardigan, óculos ou curvatura
- R53: marcar com "Origem:" NÃO chega — a linha já estava marcada e o Diretor leu-a na mesma como especificação. O leitor retém o FACTO CONCRETO ("68 anos, grisalha, cardigan") e perde o enquadramento. Agora o falso vai RISCADO com a correção na mesma frase, e o briefing leva sempre a ficha real ao lado do histórico

## 04/08 — ponte multi-plataforma + Lightning
- PONTE AGNÓSTICA construída (não existia desenho anterior; feita de raiz): um lote é dados (pasta de código + pasta de dados + saídas esperadas) e cada plataforma é um adaptador com 4 verbos — ha_quota, enviar, estado, colher. Quando uma não serve, DIZ A RAZÃO e passa à seguinte. producao.db ganhou tabelas plataformas/corridas/plano_plataforma; os 97 clipes registados retroactivamente como Kaggle
- CORREÇÕES a premissas do Claude: os limites do Colab NÃO são publicados pela Google (as "15-30h/semana" não são garantia); e o "Lightning dunning decision is deny" do erro de faturação é o sistema INTERNO da Google, não o Lightning AI — dois nomes, coisas diferentes
- COLAB não tem API de submissão (o runtime é criado por browser autenticado) → nunca pode ser disparado sozinho. Fica como plano B manual: colab/k_repesca.ipynb e colab/k_chatter2.ipynb, GPU T4
- LIGHTNING AI é o caminho: tem SDK e token de conta. Plano grátis ~15 créditos/mês ≈ 22h de T4, sem cartão. Setup em LIGHTNING-SETUP.md: lightning.ai → Sign up (Google/GitHub) → avatar → Global Settings → Keys → copiar API key + User ID → colar no .env como LIGHTNING_API_KEY e LIGHTNING_USER_ID → dizer "pronto". Adaptador já escrito até ao fim; os kernels não mudam (já procuram a entrada com rglob sob /kaggle/input, correção que os tornou portáteis sem se saber)
- LIMPEZA: 1922 MB libertados (5583→3661). Apagados: perfis de browser da era PixVerse 631MB, intermédios da montagem 1038MB, segmentos de áudio 194MB, clone do ACE-Step 65MB. NÃO apagadas as saídas cruas dos kernels de GPU (musica_out, regen_out, idoso_out, adulto_out — 130MB): regenerá-las custa quota. Quarentena intacta (_lixo_reprovado 561MB, _substituido 49MB). Não havia cache local de HF/torch — os modelos riscados foram sempre descarregados dentro das sessões do Kaggle
- R54 gravada: "a versão velha é o controlo". Fiscal do dito recalibrado para falas curtas: 6/6 trocas apanhadas, 33% de falso alarme declarado, veredicto = SUSPEITA (não bloqueio). Fila de arte: 5 despachos (avó Mônica ×3, Daniel, Rafinha)

## 04/08 — VoiceBox avaliado (a pedido do Danilo)
- [stated] O Danilo reprova as vozes dos MENINOS no que já ouviu: "não ficou parecendo de criança, ficou de homem". Viu um vídeo do VoiceBox e perguntou se o projeto usa essa ferramenta
- NÃO usamos e não vale a pena a APP: VoiceBox é um desktop app (Tauri) para correr 100% na máquina local — o PC dele é Celeron 4GB sem GPU, e o modelo mais pequeno pede 4-6GB de VRAM. A nossa produção é headless no Kaggle e ele não toca em nada (R do Representante). GUI = trabalho manual, o contrário do sistema
- O que interessa lá dentro é o MOTOR: **Qwen3-TTS** (Alibaba, jan/2026) — Apache 2.0 nos pesos E no código (comercial livre, mais limpo que o Chatterbox), português entre as 10 línguas, clonagem zero-shot com 3s, 0.6B (2,5GB) e 1.7B (4,5GB). Ressalva R45 mantém-se: dados de treino não divulgados (5M+ h), logo continua amarelo pela mesma razão que o Chatterbox — não é a cura da licença, mas não é pior. Candidato real a A/B contra o Chatterbox no Kaggle. NÃO trocar a meio do Ep1 (regra do Batedor); fila de GPU esgotada até domingo
- PONTO CENTRAL: o defeito da voz de criança NÃO é do motor. Clonagem devolve o que se lhe dá — a referência é que manda. Cura definitiva e barata: gravar os miúdos REAIS (10-15s cada, telemóvel, sala silenciosa) e usar como referência no motor que já temos. É outra vez o princípio central do projeto — trava-se com o real, nunca com a descrição ("voz de criança" escrita não produz criança)

## 04/08 — Lightning a produzir + 4 defeitos que só a 2ª plataforma revelou
- LIGHTNING FUNCIONOU: primeira produção fora do Kaggle. A ponte saltou sozinha o Kaggle (30/30h) e o Colab (sem credencial). As chaves do Danilo estavam CERTAS desde o início — a sonda do executor usava um endpoint de consulta errado que dizia "User does not exist"

