---
id: memoria-claude-ai-livro-areas-metodo-sites
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Método obrigatório para construir QUALQUER site (referência → design system → prompt → build → prémio) + agente classificador por nicho, público e nível — ler ANTES de qualquer site novo

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-metodo-sites`, origem `claude-ai`, atualizada em 2026-10-23T05:37:29.032024+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas metodo sites · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/metodo-sites.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: metodo-sites
description: Método obrigatório para construir QUALQUER site (referência → design system → prompt → build → prémio) + agente classificador por nicho, público e nível — ler ANTES de qualquer site novo
sources: [chat]
aliases: [método de sites, agente de sites, arquiteto de sites, como fazer site, site profissional, site prémio, site cinco estrelas]
---

Vale para os mini-sites de presente ([[mini-site-business]], [[ouro-e-prata]], [[sabores-de-casa]], [[beunique]], [[mister-kebab]]), para os sites vendidos ([[guarda-fc]], [[happy-site]], [[prospecao-sites-clubes]]) e para tudo o que venha a seguir.

## Decisão

- [stated] 26/08: Danilo mandou fixar o método de um vídeo que gostou (site amador vs profissional) e ir MAIS ALÉM — nível mundial, sites prémio/cinco estrelas — e criar um agente que classifica cada site antes de o construir
- [stated] O agente tem de distinguir: este é para dentista, logo precisa disto; este tem loja, logo precisa de carrinho; este merece nível prémio; este é para outro público e tem de ser mais simples senão "eles não entendem mais"

## O funil de 6 passos (nunca saltar nenhum)

1. REFERÊNCIA primeiro. Nunca construir às cegas. Buscar no Pinterest "layout site <nicho>", Awwwards, Dribbble, Land-book, e os sites dos 3 melhores concorrentes reais do cliente. Guardar 2 a 4 imagens/URLs.
2. EXTRAIR O DESIGN SYSTEM da referência antes de escrever HTML: paleta exacta, tipografia (títulos + corpo + pesos), escala de espaçamentos, raio de cantos, sombras, estilo dos botões, grelha, estilo das fotos, tipo de movimento.
3. TRANSFORMAR EM PROMPT LONGO (150–250 linhas) já adaptado ao nicho do cliente. É AQUI que se ganha ou perde o site — um prompt de uma linha dá sempre site genérico.
4. CONSTRUIR a partir do prompt, nunca a partir de "faz um site para X".
5. IMAGENS REAIS. Nunca deixar emoji/ícone default a fazer de imagem. Fotos do cliente (o executor vai ao Instagram/Facebook público buscar), ou geradas, PNG com fundo transparente onde precisa de flutuar.
6. SEGUNDA RONDA obrigatória: devolver o próprio prompt + o site e mandar melhorar, trocar imagens, apertar espaçamentos. A v1 nunca é a boa.

Reforço: uma "skill" com biblioteca de componentes prémio prontos (carrossel infinito que pára no hover, cards com troca de imagem, logo com motion) muda o resultado mais do que trocar de modelo de IA.

## O agente classificador — 3 perguntas antes de tocar em código

1. OBJETIVO: vender online / marcar hora / pedir pelo Bora / mostrar credibilidade / marca pessoal / institucional?
2. PÚBLICO: jovem e digital, ou gente mais velha e pouco à vontade com telemóvel?
3. ORÇAMENTO E DONO: presente grátis, site vendido, ou marca pessoal internacional?

Saída do agente: NÍVEL + lista de blocos obrigatórios + o que fica de fora.

## Os 3 níveis

NÍVEL 1 ESSENCIAL — loja pequena, público mais velho, grátis. Uma página. Hero com foto real, o que faz, preços, horário, mapa, telefone, um CTA gigante. Movimento quase nenhum. Letra grande, contraste alto, botão de ligar sempre à vista.

NÍVEL 2 PROFISSIONAL — o padrão dos mini-sites de presente. Design system próprio, secções com revelação ao scroll, galeria, prova social, faixa co-branded do Bora, SEO básico, favicon, OG image, 404, mobile impecável.

NÍVEL 3 PRÉMIO / CINCO ESTRELAS — cliente que paga, clube, marca pessoal. Multi-página, multi-idioma, JSON-LD (Person/Organization/LocalBusiness), muro de imprensa, cronologia, vídeo, media kit, domínio próprio, Search Console, orçamento de performance (LCP abaixo de 2,5s), acessibilidade a sério, motion cinematográfico com moderação.

## Regra do público (a que quase toda a gente erra)

Prémio NÃO é sempre mais efeitos. Se o público é mais velho ou pouco digital, prémio é: menos passos, letras maiores, um só botão, zero animação que esconda informação. Efeito que confunde o cliente do cliente é defeito, por mais bonito que seja.

## Blocos obrigatórios por nicho

- Dentista / clínica / medicina: marcação, equipa com credenciais, tratamentos explicados em linguagem simples, mapa e estacionamento, sinais de confiança, antes/depois SÓ se a lei da publicidade de saúde do país permitir.
- Restaurante / comida: menu com preços verdadeiros, fotos do prato real (nunca stock), horário, alergénios, CTA de pedido pelo Bora.
- Barbearia / salão / estética: marcação, tabela serviço+preço+duração, equipa, galeria de trabalhos, horário com pausa de almoço.
- Loja / e-commerce: catálogo, carrinho, favoritos, troca de imagem no hover, filtros, e caminho de compra até ao fim (ou encomenda por mensagem se não houver pagamento).
- Advogado / contabilista / seguros: áreas de atuação, credenciais, casos ou números, formulário de contacto, paleta sóbria, zero truques.
- Marca pessoal: história, galeria completa, muro de imprensa com links vivos, cronologia, vCard, JSON-LD Person, idiomas.
- Clube desportivo: plantel, calendário, resultados, classificação, palmarés, notícias, loja, patrocinadores visíveis e reconhecíveis.
- Imobiliária / stand / oficina: fichas com filtros, galeria grande, simulação/financiamento, contacto imediato.
- Ginásio / escola / academia: horários, planos e preços, professores, aula experimental.

## Assinaturas — o que reprova um site

Amador: secções finas, cores default, ícones/emoji a fazer de imagem, tudo alinhado ao centro sem hierarquia, zero movimento, textos "lorem" ou inventados, imagens esticadas, rodapé vazio.
Profissional: logo tratado, paleta com regra, hierarquia tipográfica clara, imagens que flutuam/sobrepõem, hover que aproxima ou troca a imagem, carrossel que pára no hover, revelação ao scroll com opacidade, navegação que muda ao descer, CTA fixo, rodapé completo.

## Regras próprias já provadas (não repetir os erros)

- GUARDAR O FICHEIRO. Os sites da [[beunique]] e do [[sabores-de-casa]] ficaram prontos e DESAPARECERAM do PC. Todo o site nasce numa pasta fixa em projetosflutter e vai para git no mesmo dia.
- HTML self-contained com imagens em base64 (link externo não renderiza no visualizador do telemóvel dele). Google Fonts por CDN funciona.
- Publicação: Cloudflare Pages por wrangler, token em bora-site/.env, subdomínio .pages.dev. Ficheiro acima de 25MiB é recusado pelo Pages.
- [stated] DOMÍNIO PRÓPRIO (27/08): Danilo comprou `boraguarda.com` na Cloudflare (mesma conta do token). O site do Bora passa a viver em `boraguarda.com` + `www`, e os sites de parceiros passam a subdomínios desse domínio (`goola.`, `ouroeprata.`, `saboresdobrasil.`) — só para as lojas que já confirmaram; as outras ficam de fora até confirmarem. Os `.pages.dev` antigos NÃO se desligam, há links já enviados a clientes.
- [stated] REGRA DA LOJA vs SITE (27/08, falha grave apanhada por ele na Goola): montar o site NÃO é montar a loja. O executor fez o site da Goola com imagens bonitas embutidas em base64 e deixou a loja no app COMPLETAMENTE SEM IMAGENS — photo_url, cover_url e hero_image_url vazios e os 2 produtos sem photo_url. Resultado: ladrilho sem logo, loja sem capa e produtos sem foto. REGRA QUE FICA: sempre que houver imagens de um parceiro, elas entram nos DOIS sítios — Storage + colunas da base (restaurants.photo_url/cover_url/hero_image_url e products.photo_url, needs_photo a false) E no site; e a prova é sempre um SELECT, nunca o site publicado.
- [stated] IMAGENS DE PRODUTO (27/08, reclamação dele): não servem imagens genéricas de banco de imagens que qualquer um acha na internet. As fotos vêm das fontes reais da marca — Instagram, Facebook, site oficial da franquia — e o logo vem do site oficial.
- [stated] DOMÍNIO NOS SITES (27/08): depois de mudar para `boraguarda.com`, ficaram links antigos `.pages.dev` espalhados dentro dos sites (o da Goola ainda mandava para bora-app-web.pages.dev). Ao mudar de domínio, varrer TODOS os links internos e externos de todos os sites, não só o canonical e o sitemap.
- [stated] VÍDEO OBRIGATÓRIO EM TODOS OS SITES (28/08, ordem dele, deixa de ser só do nível 3): todo site que fizermos leva vídeo — do cliente se houver (Instagram/Facebook/material próprio), senão montado a partir das fotos reais com movimento suave. Já é assim no site do Bora (assets/video/bora-apresentacao.mp4) e no da Keli. O vídeo NÃO vai em base64 (pesa demais e mata o primeiro pintar); fica em assets/ com caminho relativo, e o poster é imagem real. Ao publicar, confirmar que os ficheiros de vídeo passaram a lista branca do deploy-cloudflare.sh — na Goola o vídeo foi construído mas não chegou ao ar.
- [stated] DUAS PORTAS PARA PEDIR (28/08, ordem dele, corrige a regra do CTA abaixo): o convite a pedir deixa de ser só a app. Passa a haver DOIS botões com o MESMO peso visual — "Descarregar a app" (Play Store) e "Pedir pelo site" (app.boraguarda.com) — cada um com uma linha curta por baixo (um diz Android, o outro diz que funciona no iPhone e no computador sem instalar nada). Nenhum em letra pequena nem com ar de secundário. Vale para TODOS os sites, não só o da Goola. Razão dele: metade das pessoas anda de iPhone ou está no computador e não instala nada.
- Auditar só uns segundos DEPOIS do deploy — auditar em cima apanha a Cloudflare a meio e dá falso negativo.
- Uma sessão de cada vez por repositório de site.
- Fotos: ninguém cortado de fora, duplicados por hash percetual, e confirmar sempre que a pessoa da foto é mesmo a pessoa (a regra do sósia veio de um erro real).
- Nunca gerar retrato fotorrealista por IA de pessoa identificável.
- Factos (resultados, datas, prémios) confirmados em duas fontes antes de publicar.
- CTA dos mini-sites é sempre ENCOMENDAR/MARCAR PELO BORA APP; WhatsApp do cliente só discreto no rodapé.
- Entregar sempre com: favicon, OG image, sitemap, robots, 404, e QR quando houver parede de loja.
- [stated] PROMPT ENTREGUE 29/08 como ficheiro: `PROMPT_site_premio_montra_bora_2026-08-29.md` (motor OPUS, Claude Code janela Pro, repo bora-site). Scope: criar a skill `.claude/skills/site-premio/` com este método todo (e copiá-la para os outros repos de site); biblioteca `components-premio/` (cena em scroll, revelação, cabeçalho que muda, carrossel que pára no hover, antes/depois com arrastar, contador, lightbox, formulário que abre o WhatsApp já preenchido, CTA duplo fixo); motor de imagem/vídeo a custo zero; reconstruir boraguarda.com como MONTRA; página de portfólio `/trabalhos`; fiscal visual que compara captura contra captura. Estado: ver a linha seguinte — foi endurecido e correu a 29/08
- [stated] MESMO PROMPT ENDURECIDO 29/08 (2.ª versão, depois de ele mandar um 3.º vídeo — "Rei do Site"/Herbert Carnaúba, venda de sites ao estrangeiro): acrescentado NÍVEL 4 SISTEMA (login Google + base de dados + pagamento real + conteúdo fechado com marca de água), herói com vídeo real em fundo, parallax de camadas, pré-visualização protegida, gerador de proposta em PDF, página `/orcamento` sem preços que acaba no WhatsApp, e guião de vídeo curto para TikTok/Instagram. Estado: CORREU e fechou no mesmo dia — skill `site-premio` escrita, 13 componentes, montra do boraguarda.com refeita com a cena assinatura (história do pedido), página `/trabalhos` com 7 trabalhos e capturas reais (o [[guarda-fc]] só com captura, sem link, porque responde 401), `/orcamento` sem preços, fiscal visual, gerador de proposta em PDF e guião do canal. Tudo no ar e publicado. ⚠️ FALHA A CORRIGIR NA 2.ª RONDA: a pasta `referencias/` ficou VAZIA — a montra foi refeita a partir do design system que o site já tinha, logo houve medição de geometria mas NUNCA houve comparação de imagem contra imagem, que era o coração do fiscal. O site está correto, não está provado bonito. Pendente também: os repos do [[guarda-fc]], do [[happy-site]] e da [[goola-acai]] não têm remoto no GitHub (só git local)
- [stated] 29/08, POSIÇÃO DELE: quer ser especialista em sites e fazer "o melhor site possível" para poder cobrar caro mais à frente; por agora ainda não vende caro. Aceitou a ideia de que o preço alto vem do site FAZER coisas (nível 4), não da beleza
- [stated] 31/08, REGRA NOVA dele (a maquete do Imoaugusto PERDEU à vista para o site real do cliente — a casa bonita em ecrã cheio deles ganhou da nossa página minimalista): a referência nº1 passa a ser sempre o SITE ATUAL do cliente e a maquete só serve se ganhar dele à primeira vista, lado a lado; método = "pegar o melhor do site do cliente + o melhor do mundo do nicho e fazer o melhor dos dois"; a fasquia inclui vídeo bem detalhista (ex.: câmara a percorrer o imóvel com voz a ler a descrição), não só design
- [stated] 30/08: a falha da pasta `referencias/` vazia foi FECHADA na missão propostas-3-por-dia (referências capturadas, design systems escritos, fiscal imagem contra imagem) — o caso Imoaugusto mostrou que falta também comparar contra o site do próprio cliente
- [stated] 31/08, REGRA DO LINK ÚNICO (ele viu a proposta do Imoaugusto e não percebeu nada): ao cliente vai UM link só. As fichas/páginas interiores têm de abrir a partir de dentro do site (clicar no cartão do imóvel), nunca como links soltos entregues à parte — três moradas para a mesma proposta confundem e parecem amadoras
- [stated] 31/08, MOTOR DE VÍDEO = BORA STUDIO: o vídeo dos sites faz-se com o sistema dele ([[bora-studio-agentes]], Wan no Kaggle), nunca com serviço pago; quando faltar capacidade, procurar ferramenta GRATUITA no mundo e incluí-la no Bora Studio (regra dele, disse chateado por eu ter proposto serviço pago)
- [stated] 31/08, PRÓXIMO PASSO que ele mandou montar: sistema que estuda a fundo o que faz um site valer muito dinheiro — ver umas 200 fontes (vídeos do YouTube sobre sites premiados/caros) e daí sair o método, ANTES de continuar a fazer maquetes. Eu afinei e ele ouviu: além dos vídeos, capturar os próprios sites premiados e transformar tudo num livro de regras que o fiscal aplica; correr com Ollama, de graça
- [stated] PROMPT REGISTADO: `PROMPT_livro_de_regras_e_gfc_v7_2026-08-31.md`, entregue 31/08, MOTOR OPUS (janela Pro, PC novo; leitura em massa no Ollama local), sessão `livro-de-regras-e-gfc-v7`. Duas fases: (1) livro de regras dos sites caros — ~200 transcrições de YouTube (sites premiados, sites caros e sites feitos por IA) lidas pelo Ollama + captura de 40-60 vencedores reais (Awwwards/FWA/Webby), saída em LIVRO-DE-REGRAS.md, ANTI-PADROES.md e grelha de pontuação 0-100 integrada no fiscal; (2) só depois, cópia de trabalho `guarda-fc-site-v7` num endereço de pré-visualização separado com palavra-passe (o site no ar fica INTOCADO), a bater Benfica/Juventus/Inter/PSG e o site atual, com mensagem em inglês escrita mas NÃO enviada para o [[jai-agarwal]] aprovar. Inclui ainda 3 correções: vídeo de herói no telemóvel (muted/autoplay/playsinline/poster, nunca barra de controlos), regra do link único, e pasta pública `/provas/<slug>/` em bora-site (noindex mas permitida no robots.txt) para eu poder VER as capturas em vez de julgar por relatório. Estado: entregue como ficheiro; nada disparado
- [stated] 31/08, IMAGENS GERADAS POR IA — a posição dele de manhã (queria imagens fotorrealistas geradas, não desenho) foi SUPERADA à noite pelo veredito do cliente: o [[jai-agarwal]] recusou a v7 por causa das imagens geradas, e no [[guarda-fc]] não entra nenhuma imagem de IA
- [stated] 31/08, REGRA DA ORIGEM (ele apanhou um plano de um jogador a fazer embaixadas que era real mas de outro clube): não basta a imagem ser real — tem de ser DO PRÓPRIO cliente. Nada de vídeo genérico de futebol, banco de imagens ou material de outro clube; cada imagem/plano leva a origem registada e o fiscal reprova o que não tiver
- [stated] 02/09, ARMADILHA PROVADA no iPhone do Danilo (iOS 26.6.1): tem "Reduzir movimento" (prefers-reduced-motion) LIGADO nas definições de acessibilidade. Três voltas seguidas do executor disseram "feito" testando num simulador com isso desligado — e no telemóvel real dele o efeito de scroll ficava parado e os cartões voltavam, porque o código tratava "reduzir movimento" como "não fazer nada" e saía antes do ramo móvel. REGRA QUE FICA para todos os sites: testar sempre com prefers-reduced-motion ligado E desligado; "reduzir movimento" desliga zoom/transições mas a imagem continua a obedecer ao dedo; e uma página /diag.html que ele abre no telemóvel e manda a captura é a única fonte de verdade sobre o aparelho dele — o Jai pode ter a mesma definição
