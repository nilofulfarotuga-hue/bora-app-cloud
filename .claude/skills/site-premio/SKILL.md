---
name: site-premio
description: O manual de construir sites que se vendem. Use SEMPRE que a tarefa for criar, refazer, avaliar ou orçamentar um site — para um cliente, para um parceiro do Bora, ou para o próprio Bora. Cobre o funil de 6 passos (referência → design system → prompt longo → construir → imagens reais → segunda ronda), o classificador de 3 perguntas, os 4 níveis de site que decidem o preço, os blocos obrigatórios por nicho, o que reprova um site, a regra anti-genérico, e as regras já pagas com erro real. Triggers - "fazer um site para X", "site do cliente Y", "refaz o site", "que nível é este site", "quanto cobrar por este site", "proposta de site", "mini-site do parceiro".
metadata:
  type: procedural
  zona: verde
  origem: missao site-premio-montra-bora, 2026-08-29
  execucoes: 3
  sucessos: 3
  falhas: 0
  ultima_execucao: 2026-08-31
---

# SITE PRÉMIO — o manual de construir sites que se vendem

> Escrito a 2026-08-29 na missão `site-premio-montra-bora`.
> Antes existia só na cabeça de quem escrevia o prompt. Agora está aqui.
>
> **Hierarquia:** o `PADRAO_BORA.md` manda sobre isto. Isto manda sobre hábitos.
> Nada aqui foi inventado: cada regra dura veio de um erro que já custou trabalho.

---

## 0. A REGRA QUE MANDA SOBRE TODAS

**O gargalo não é construir. É a pessoa responder ao email.**

Um site tecnicamente correcto que não faz o cliente responder é um site falhado. Por isso o
funil começa em **referência** e acaba em **segunda ronda** — e nenhum dos seis passos se
salta, por mais pressa que haja.

---

## 1. O FUNIL DE 6 PASSOS — nunca saltar nenhum

### Passo 1 — REFERÊNCIA primeiro

**REGRA QUE MANDA (2026-08-31, veredito do Danilo): A REFERÊNCIA Nº 1 É SEMPRE
O SITE ATUAL DO CLIENTE.** A maquete do Imoaugusto perdeu ao vivo contra o
site real dele porque o fiscal só comparou com referências de luxo e nunca com
o adversário verdadeiro. A maquete só está pronta quando GANHA do site atual
do cliente à primeira vista — teste dos 3 segundos (ver §6b). Se o site dele
for bom, a fasquia sobe; nunca se assume que é mau.

Depois do site do cliente, ir buscar como é que os melhores fazem isto:

- Pinterest: `layout site <nicho>` — é o mais rápido a mostrar composições inteiras
- Awwwards, Dribbble, Land-book — para hierarquia, movimento e estado da arte
- **Os 3 melhores concorrentes reais do cliente** — isto é o que ninguém faz e é o que mais
  vale: o cliente reconhece o mercado dele e percebe que estudaste o problema dele

Guardar **2 a 4 imagens ou URLs** em `referencias/`. Não é decoração do processo: o Bloco F
(fiscal visual) compara a captura do trabalho **contra estas capturas**. Sem elas o fiscal
não tem contra o que comparar e degrada para opinião.

Nome dos ficheiros: `referencias/<nicho>-<fonte>-<n>.png` (ex.: `clinica-awwwards-1.png`).

### Passo 2 — EXTRAIR O DESIGN SYSTEM da referência, ANTES de escrever HTML

Olhar para a referência e escrever, em texto, o sistema que ela usa. Nove pontos, todos:

1. **Cores** — 4 a 6, nomeadas, em hex. Não "azul": `--tinta:#0B0F0D`. Dizer o papel de
   cada uma (fundo, texto, texto secundário, acento, linha, sucesso).
2. **Tipografia** — display + corpo + utilitária, **com pesos**. Ex.: display Inter 900 com
   `letter-spacing:-.04em`; corpo Inter 400/500 a 17px; utilitária Inter 700 a .78rem com
   `letter-spacing:.18em` em maiúsculas.
3. **Escala de espaçamentos** — a régua real (4/8/12/16/24/32/48/64/96) e onde cada degrau
   se usa.
4. **Raio de cantos** — 0, 8px, 14px, 999px. Um site que mistura três raios ao acaso lê-se
   como amador.
5. **Sombras** — quantas há, e se são difusas (`0 10px 28px -10px`) ou dramáticas.
6. **Estilo de botões** — cheio, contorno, pílula, quadrado; o que acontece no hover.
7. **Grelha** — quantas colunas, largura máxima, onde quebra no telemóvel.
8. **Estilo das fotos** — recortadas a sangrar, com raio, sobrepostas, com gradiente por
   cima, a preto e branco.
9. **Tipo de movimento** — revelação suave, parallax, cena fixa, ou quase nenhum.

Este texto é o que vai para o Passo 3. Sem ele, o Passo 3 escreve-se no vazio.

### Passo 3 — TRANSFORMAR EM PROMPT LONGO (150 a 250 linhas), já adaptado ao nicho

**É aqui que se ganha ou se perde o site.** Um prompt de três linhas dá sempre um site de
três linhas.

O prompt longo tem, por esta ordem:
- quem é o cliente, o que vende, a quem, e em que cidade
- o **objectivo comercial** da página em uma frase (o que a pessoa tem de fazer)
- o design system inteiro do Passo 2, escrito por extenso
- a lista de secções por ordem, com o conteúdo real de cada uma
- os textos verdadeiros (nunca *lorem ipsum*, nunca inventados)
- que componentes do `components-premio/` entram e onde
- o elemento assinatura (ver §7)
- o que está **proibido** neste site em concreto

### Passo 4 — CONSTRUIR a partir desse prompt

Nunca a partir de "faz um site para X". Se te apanhares a construir sem o prompt do Passo 3
à frente, pára e volta atrás — sai sempre mais barato do que refazer.

### Passo 5 — IMAGENS REAIS

Nunca emoji nem ícone a fazer de imagem. A ordem de recolha está no Bloco C
(`docs/motor-media-gratis.md`): fotos do cliente primeiro (Instagram e Facebook públicos,
site oficial), logótipo **sempre** do site oficial da marca.

#### 5b. SÓ MATERIAL DO PRÓPRIO CLIENTE — regra dura (desde 2026-08-31)

> Ordem do Danilo, sem exceções: *"só entra imagem ou vídeo DO PRÓPRIO CLUBE.
> Não basta ser real — se for de outro clube, de banco de imagens ou de vídeo
> genérico, sai. E nada gerado por IA."*
> Escrita depois de a abertura do Guarda FC ter levado três imagens geradas no
> Gemini e um plano de embaixadas tirado de um anúncio de patrocinadores.

Ser **real** não chega. Para entrar, um ficheiro tem de ser **daquele cliente**:

| Entra | Não entra |
|---|---|
| Canal, Facebook, Instagram e site do próprio cliente | Foto de outro clube/loja, mesmo do mesmo campeonato |
| Entrega direta (WeTransfer, pen, email) | Banco de imagens, mesmo pago ou "livre de direitos" |
| Fotógrafo contratado pelo cliente | Vídeo genérico do género (relva, bola, mãos a cozinhar) |
| Imprensa local que cobriu **aquele** cliente | Qualquer coisa gerada por IA — imagem, vídeo ou voz |
| Federação/associação, quando é sobre o cliente | Frame de anúncio ou de material de patrocinador |

Três exceções, e só estas, porque **identificam** em vez de ilustrar: escudo ou
logótipo do adversário/parceiro, logótipo de patrocinador que o cliente forneceu,
e imagens que o próprio site desenha a partir de dados reais (cartões de jogo,
cartões de partilha). Ficam marcadas como tal — nunca passam por fotografia.

**Cada ficheiro tem de ter origem escrita.** Ficheiro sem origem registada é
tratado como material desconhecido: **sai**. O registo é um manifesto no repo
(`data/origens.json`), com uma linha por ficheiro:

```json
"assets/img/jogo-04-ataque.jpg": {
  "origem": "Facebook oficial do clube",
  "link": "https://www.facebook.com/GuardaFutebolClube/",
  "tipo": "clube"
}
```

Tipos válidos: `clube` (material do próprio cliente), `proprio` (desenhado pelo
site a partir de dados reais), `adversario` e `parceiro` (escudos e logótipos de
identificação). Qualquer outro valor, ou origem em falta, **reprova**.

O fiscal verifica isto sozinho (§8c) e chumba a página. Não é aviso: é chumbo.
Quando faltar material, a resposta certa é **ir buscar mais ao cliente** — nunca
tapar o buraco com uma foto bonita de outro sítio.

### Passo 6 — SEGUNDA RONDA, obrigatória

Devolver **o próprio prompt do Passo 3 mais o site construído** e mandar melhorar.
**A v1 nunca é a boa.** Não é opinião: é o passo que separa um site que se mostra de um site
que se manda por email.

Na segunda ronda perguntar sempre três coisas: onde é que a hierarquia falha, que secção
está fina de conteúdo, e qual é a coisa que um estranho não percebe em cinco segundos.

---

## 2. O CLASSIFICADOR — 3 perguntas antes de tocar em código

**1. Objectivo.** Vender online, marcar hora, pedir pelo Bora, credibilidade, ou marca
pessoal? Um site com dois objectivos não tem nenhum.

**2. Público.** Jovem e digital, ou mais velho e pouco à vontade com o telemóvel?
Esta é a pergunta que quase toda a gente erra — ver §4.

**3. Dono e orçamento.** Presente grátis, site vendido, ou marca internacional?

**Saída obrigatória do classificador**, escrita antes de qualquer HTML:

```
NÍVEL: <1|2|3|4>
BLOCOS OBRIGATÓRIOS: <lista, do §5 do nicho>
FICA DE FORA: <lista explícita>
ELEMENTO ASSINATURA: <um só>
```

O "fica de fora" escreve-se sempre. É o que impede o site de crescer para os lados e é o que
protege a proposta de "mas eu pensei que também vinha com...".

---

## 3. OS 4 NÍVEIS — o nível decide o preço, não a beleza

Um site de Nível 1 pode ser mais bonito que um de Nível 3. O preço não vem da beleza: vem
do que o site **faz**.

### NÍVEL 1 — ESSENCIAL
Loja pequena, público mais velho, grátis ou muito barato.
Uma página. Letra grande. Contraste alto. **Botão de ligar sempre à vista.** Movimento quase
nenhum. Morada com mapa. Horário. É só isto, e é de propósito.

### NÍVEL 2 — PROFISSIONAL
O padrão dos mini-sites do Bora.
Design system próprio, revelação ao scroll, galeria, prova social, SEO básico, favicon,
imagem de partilha, página 404, e mobile impecável. Testado a 360px.

### NÍVEL 3 — PRÉMIO
Cliente que paga bem.
Multi-página, multi-idioma, dados estruturados JSON-LD, muro de imprensa, cronologia, vídeo,
media kit, domínio próprio. LCP abaixo de 2,5s. Acessibilidade a sério (foco visível,
contraste, rótulos). Movimento cinematográfico **com moderação**.

### NÍVEL 4 — SISTEMA
**É aqui que está o preço alto.**

O site deixa de ser montra e passa a **fazer** alguma coisa: conta de utilizador com login
Google, base de dados, pagamento real por cartão, área privada, conteúdo fechado que só abre
depois de pagar, e painel para o dono ver quem comprou.

> Um site bonito vale algumas centenas de euros. Um site que cobra dinheiro sozinho vale
> milhares. Quem pede orçamento a uma agência para isto ouve "isso é um projecto à parte".

---

## 3b. O QUE O DANILO JÁ TEM E MAIS NINGUÉM NA GUARDA TEM

**Supabase** (base de dados, contas, ficheiros, funções de servidor) e **Stripe em modo Live**
já a funcionar em produção, no Bora, provados com dinheiro real.

Isto quer dizer que o Nível 4 **não é teoria**: é ligar peças que já existem e já estão
provadas. Sempre que um cliente tiver conteúdo que se possa vender, aula que se possa marcar
e pagar, fotografias que se possam comprar, ou uma área só para membros — **propor Nível 4 em
vez do site simples.**

### As cinco receitas do Nível 4, prontas a usar

1. **Conta com login Google.** O visitante entra com a conta que já tem. Zero senhas para
   gerir, zero recuperação de senha para construir.
2. **Catálogo com pré-visualização protegida.** A imagem mostra-se com marca de água por
   cima; o ficheiro limpo só sai depois do pagamento confirmado. É o componente 13 do
   `components-premio/`. Serve fotógrafos, escolas, estúdios e clubes.
3. **Marcação com sinal pago.** A hora só fica reservada depois de o sinal entrar. Mata as
   faltas e é o argumento de venda mais fácil de explicar a um dono de negócio.
4. **Assinatura mensal.** Receita que se repete — para o cliente e, indirectamente, para
   quem construiu.
5. **Área de membros.** Conteúdo que só abre a quem tem conta activa.

### A regra de segurança que não se discute

**NUNCA meter chaves secretas do Stripe dentro do HTML.** O HTML é público por definição:
qualquer visitante lê o código-fonte da página.

O segredo vive numa **função do lado do servidor** (no caso do Danilo, uma Edge Function do
Supabase). O site só fala com essa função, e a função é a única que fala com a Stripe.
No site só pode existir a chave **publicável** (`pk_...`), que é pública por desenho.

O mesmo vale para a chave de serviço da base de dados: no site entra a chave anónima, e o
que protege os dados é a RLS do lado do servidor — nunca o silêncio do JavaScript.

---

## 4. A REGRA DO PÚBLICO — a que quase toda a gente erra

**Prémio NÃO é sempre mais efeitos.**

Público mais velho quer dizer: menos passos, letras maiores, **um só botão**, e zero animação
que esconda informação.

> **Efeito que confunde o cliente do cliente é defeito.**

Quando o público é mais velho, aquilo que num site de Nível 3 seria elegante — texto que só
aparece ao chegar, secções que se montam, números que contam — passa a ser barreira. Nesse
caso o movimento reduz-se ao mínimo e o telefone fica fixo no fundo do ecrã.

Isto não é fazer menos: é acertar. Um site de Nível 1 bem acertado converte mais do que um
Nível 3 no público errado.

---

## 5. BLOCOS OBRIGATÓRIOS POR NICHO

**Alojamento e turismo** — reserva directa, galeria grande, mapa, multi-idioma, política de
cancelamento, avaliações reais, e o argumento da **reserva sem comissão** (é o que faz o dono
querer o site).

**Clínica e dentista** — marcação, equipa com credenciais, tratamentos em linguagem simples,
mapa e estacionamento, sinais de confiança.

**Restaurante** — menu com **preços verdadeiros**, fotos do prato real, horário, alergénios,
e botão de pedir pelo Bora.

**Barbearia e estética** — marcação, tabela de serviço com preço e duração, equipa, galeria,
horário com a pausa incluída.

**Loja** — catálogo, carrinho, favoritos, troca de imagem no hover, filtros.

**Advogado e contabilista** — áreas de actuação, credenciais, formulário, paleta sóbria,
**zero truques**. Aqui o movimento é o inimigo da credibilidade.

**Imobiliária** — fichas com filtros, galeria grande, simulação, contacto imediato, idiomas.

**Clube desportivo** — plantel, calendário, resultados, classificação, palmarés, loja,
patrocinadores.

---

## 6. O QUE REPROVA UM SITE

### Lê-se como amador
Secções finas (três linhas e passa à seguinte) · cores por omissão do browser · **emoji a
fazer de imagem** · tudo centrado sem hierarquia · zero movimento · texto inventado ·
imagens esticadas fora de proporção · rodapé vazio.

### Lê-se como profissional
Logótipo tratado (não o favicon esticado) · paleta com regra · hierarquia tipográfica clara ·
imagens que flutuam ou se sobrepõem às secções · hover que aproxima ou troca a imagem ·
carrossel que **pára no hover** · revelação ao scroll · navegação que muda ao descer ·
botão de acção fixo no telemóvel · rodapé completo.

**Teste rápido antes de entregar:** tapa o logótipo. Se o site pudesse ser de qualquer outro
negócio do mesmo ramo, não está pronto.

### 6b. O TESTE DOS 3 SEGUNDOS (obrigatório desde 2026-08-31)

Composto lado a lado — site atual do cliente à ESQUERDA, maquete à DIREITA,
a 1440px e a 390px, a MESMA secção (herói contra herói) — gerado por
`propostas/ferramentas/tres_segundos.py` e guardado em `prova/3segundos/`.
O juiz de visão olha e responde a UMA pergunta:

> **"Qual destes dois parece o site mais caro e mais profissional?"**

Se a resposta não for a maquete, com justificação concreta (o que é que o
outro tem que o nosso não tem), a maquete VOLTA PARA TRÁS. Sem exceções,
sem "mas as referências…". O veredito escreve-se em
`prova/3segundos/VEREDITO.md`: GANHA ou PERDEU, e porquê.

### 6c. PROIBIÇÃO DO HERÓI VAZIO (desde 2026-08-31)

**Herói sem imagem ou vídeo em ecrã cheio é proibido. Texto sobre fundo liso
nunca mais abre uma maquete.** Foi assim que a página creme minimalista do
Imoaugusto pareceu vazia ao lado da casa em ecrã cheio do site real dele.
O primeiro ecrã abre SEMPRE com fotografia ou filme do próprio cliente a
sangrar — a elegância tipográfica vem por cima, nunca em vez.

---

## 7. ANTI-GENÉRICO — regra dura

Está **proibido** entregar um dos três defaults de inteligência artificial:

1. Fundo creme com serifada de alto contraste e um acento terracota.
2. Fundo quase preto com um acento verde-ácido.
3. Jornal com filetes finos e zero raio de canto.

Se o design cair num destes **sem o briefing o pedir**, refaz-se e explica-se o que mudou.

**Gasta a ousadia num sítio só.** Escolhe **UM** elemento assinatura por site — a cena em
scroll, o herói com vídeo, o antes/depois, o parallax de camadas — e mantém tudo à volta
disciplinado. Dois elementos assinatura no mesmo site anulam-se: nenhum dos dois é lembrado.

---

## 8. REGRAS JÁ PROVADAS — não repetir estes erros

**8.1 GUARDAR O FICHEIRO.** Todo o site nasce numa pasta fixa dentro de `projetosflutter` e
vai para git **no mesmo dia**. Já se perderam sites prontos no disco.

**8.2 HTML self-contained com as imagens em base64.** Um link externo não renderiza no
visualizador do telemóvel do Danilo — e é aí que ele vê o trabalho. Google Fonts por CDN
funciona. **Acima de 25 MiB o Cloudflare Pages recusa o ficheiro.**

**8.3 Vídeo NUNCA em base64.** Fica em `assets/` com caminho relativo, com poster de imagem
real, e **tem de passar a lista branca do `deploy-cloudflare.sh`** — se não estiver na lista,
não é publicado e ninguém dá por isso.

**8.4 Auditar só uns segundos DEPOIS do deploy.** Auditar cedo demais dá falso negativo.
E o Cloudflare Pages devolve `200` com a página do site para endereços que não existem — por
isso **olha-se o conteúdo, nunca o código de resposta**.

**8.5 Uma sessão de cada vez por repositório de site.** Duas sessões no mesmo repo arrastam
commits uma da outra.

**8.6 Nunca gerar retrato fotorrealista por inteligência artificial de pessoa
identificável.** Nem do cliente, nem da equipa dele, nem de figura pública.

**8.7 Factos confirmados em duas fontes antes de publicar.** Datas, prémios, números,
palmarés. Um número errado no site de um cliente é um estrago que não se desfaz.

**8.8 Fotos: ninguém cortado de fora, e sem duplicados por hash percetual.** Uma foto com
meia cara fora do enquadramento lê-se como descuido.

**8.10 Vídeo no telemóvel (2026-08-31 — apanhado pelo Danilo ao vivo).** Todo o
vídeo de fundo/herói leva OBRIGATORIAMENTE `muted autoplay loop playsinline
preload="metadata"` + `poster` de imagem real, largura 100% e ALTURA DEFINIDA
(aspect-ratio ou altura explícita, com fallback `100vh` ANTES de `100svh` —
os webviews do WhatsApp/Instagram não conhecem svh e o herói colapsa numa
linha fina que só toca o som). Nada de controlos nativos a fazer de herói;
o som liga-se num botão visível. O fiscal REPROVA (grave) qualquer captura
a 390px onde um vídeo apareça como barra (<120px de altura).

**8.11 UM link só por cliente (2026-08-31).** Ao cliente vai UMA morada — a
raiz da maquete. As páginas interiores (fichas, serviços) abrem-se clicando
de dentro do site, nunca por links soltos na mensagem. Um cliente com três
links perde-se; com um, entra e explora.

**8.9 Entregar sempre com** favicon, imagem de partilha, sitemap, robots, página 404 — e
**QR** quando houver parede de loja. O QR usa correcção de erro **M** (nunca menos), com pelo
menos 500 px de lado na arte A4, e prova-se por leitura do QR **isolado** em várias reduções.

---

## 8c. O LIVRO DE REGRAS E A GRELHA (2026-08-31)

O método ganhou um livro tirado de provas: `propostas/fase1/LIVRO-DE-REGRAS.md`
(regras com contagem de fontes: sites premiados MEDIDOS + fichas de vídeo
lidas pelo Ollama + cicatrizes) e `propostas/fase1/ANTI-PADROES.md` (o que
denuncia barato ou IA). O fiscal dá a NOTA DA GRELHA 0-100 (função
`pontuar` no fiscal.py): **mínimo 70 para publicar**, GRAVE encosta a 49,
e o teste dos 3 segundos continua eliminatório à parte. Ler o livro antes
do prompt longo; em conflito, o livro perde só para o veredito do Danilo.

### A verificação de origem (desde 2026-08-31)

O fiscal lê `data/origens.json` e recolhe da página **todas** as imagens
mesmo — `<img>`, `srcset`, `<source>` de `<picture>`, `<video poster>` e
fundos por CSS. Cada uma tem de estar no manifesto com um `tipo` válido.
Falha se: não estiver registada, tiver `tipo` desconhecido, ou trouxer
`POR CONFIRMAR`. É defeito **GRAVE** — chumba a página, não avisa.

O manifesto também é auditável ao contrário: um ficheiro registado que já
não é usado por nenhuma página aparece como sobra, para se apagar.

## 9. COMO SE USA ISTO NUMA TAREFA

1. Ler este ficheiro inteiro. É curto de propósito.
2. Correr o classificador (§2) e escrever a saída de 4 linhas.
3. Passos 1 e 2 do funil → `referencias/` fica com 2 a 4 ficheiros.
4. Passo 3 → o prompt longo fica guardado em `prompt-<cliente>.md` no repo do site.
   Guarda-se porque a segunda ronda precisa dele.
5. Passo 4 → construir, puxando componentes de `components-premio/`.
6. Passo 5 → imagens pelo `docs/motor-media-gratis.md`, **só do próprio cliente**
   (§5b), e cada ficheiro registado em `data/origens.json` à medida que entra.
7. Correr o fiscal visual (`tools/fiscal-visual/`) a 360, 768 e 1440.
8. Passo 6 → segunda ronda com o prompt e o site na mão.
9. Proposta em PDF pelo `tools/proposta/` — **nunca preço solto por mensagem.**

---

## 10. PARA O DANILO

Nada nesta skill decide preços nem toca em dinheiro. Quando uma proposta concreta precisar de
um número, a decisão é tua: a skill prepara a proposta inteira e deixa o valor por preencher.

---

*Escrito na missão `site-premio-montra-bora`, 2026-08-29.
Peças irmãs: `components-premio/` (caixa de ferramentas), `docs/motor-media-gratis.md`
(imagem e vídeo a custo zero), `tools/fiscal-visual/` (o crítico), `tools/proposta/`
(o PDF que fecha).*
