# Reparação — imagens da loja, ladrilho da Lavagem Auto, links antigos e site da Goola

Data: 28 de Agosto de 2026. Missão de reparação, sem frentes novas.

---

## Primeiro, uma coisa urgente que é minha culpa

Quando publiquei o site institucional na missão do domínio, publiquei a pasta inteira
em vez da cópia filtrada que o script `deploy-cloudflare.sh` faz de propósito para isso
não acontecer. O resultado é que o ficheiro `.env` da pasta `bora-site`, que tem os teus
dois tokens da Cloudflare lá dentro em texto simples, ficou a ser servido publicamente
em `boraguarda.com/.env` desde as vinte e duas e quarenta e seis de vinte e sete de
Agosto, hora universal. Qualquer pessoa que soubesse pedir aquele endereço lia os tokens.

Já publiquei outra vez, agora pela cópia filtrada, e a origem está limpa. Provei-o de
duas maneiras independentes: o endereço directo da publicação nova devolve a página do
site em vez do ficheiro, e o mesmo endereço com uma pergunta na barra, que fura a cache,
também devolve a página do site. O que ainda sobra é uma cópia guardada na borda da
Cloudflare, com validade de sete dias, e nenhum dos dois tokens tem permissão para mandar
limpar cache — tentei com os dois e os dois foram recusados por falta de autorização.

Portanto ficam duas coisas para ti, e são as duas de trinta segundos:

Primeiro, e isto é o que importa mesmo, **troca os dois tokens da Cloudflare**. Estiveram
públicos várias horas, e uma vez públicos não voltam a ser de confiança, por muito que se
apague o ficheiro. Vais a `dash.cloudflare.com`, carregas na tua fotografia no canto
superior direito, escolhes "My Profile", depois "API Tokens" na barra da esquerda. Para
cada um dos dois tokens carregas nos três pontos à direita e escolhes "Roll". Ele mostra
o valor novo uma única vez — copia-o. Depois diz-me e eu ponho os valores novos no `.env`,
ou pões tu, que é só substituir o texto à frente do sinal de igual.

Segundo, para tirar já a cópia da cache em vez de esperar sete dias: na mesma página
escolhes o site `boraguarda.com`, carregas em "Caching" na barra da esquerda, depois em
"Configuration", e carregas no botão "Purge Everything".

Aproveitei para varrer os outros três sites à procura do mesmo problema e nenhum tem
ficheiros escondidos expostos — o que parecia um duzentos era a página normal do site, que
o Cloudflare Pages devolve para endereços que não existem. Confirmei pelo conteúdo, não
pelo código de resposta, precisamente porque nesse ponto o código de resposta mente.
Daqui para a frente publico sempre por cópia filtrada, e foi assim que publiquei hoje o
Ouro e Prata e o Sabores do Brasil: a lista dos ficheiros que subiram está no registo, e
são só os públicos.

---

## As imagens da loja da Goola

Tinhas razão no essencial: o site tinha as fotos todas e a loja dentro da app não tinha
nenhuma. Site e loja são dois destinos diferentes e a foto tem de entrar nos dois.

Já está. As quatro imagens estão no armazenamento do Supabase, no balde
`restaurant-assets`, dentro da pasta da Goola, e os campos da base apontam para elas.
A capa da loja e a imagem grande do topo são a fotografia real do quiosque no La Vie, com
os balões e os dizeres da marca. O logótipo é o desenho oficial da Goola. Os dois bowls
têm cada um a sua fotografia, tiradas do site oficial da marca e não de banco de imagens
— e isso ficou escrito na própria base, na coluna que regista a origem de cada foto, para
daqui a seis meses ninguém ter de adivinhar de onde veio aquilo.

Puxei as quatro pela internet, uma a uma, e todas responderam duzentos com bytes a sério:
a capa tem trinta e um mil bytes e mede quatrocentos e sessenta e um por duzentos e
oitenta e oito, o logótipo tem trinta e dois mil e mede quinhentos e doze por quinhentos
e doze, o bowl clássico tem cinquenta e quatro mil e mede trezentos e setenta e sete por
trezentos e setenta e sete, e o bowl grande tem quarenta e três mil e mede trezentos e
oitenta e um por trezentos e oitenta e um. Deixei-as todas lado a lado numa folha de
contactos em `provas-app/loja_imagens_no_storage.png` para veres de relance.

A loja está marcada como parceira, aprovada, com a categoria de restaurante e com a
categoria extra de sobremesa — que é o que faz aparecer no ladrilho novo das Sobremesas
sem lhe mexer no fluxo normal de compra. Os preços na base são nove euros e vinte e dois
e onze euros e cinquenta e cinco, que são os que já lá estavam.

Uma limitação que quero dizer com todas as letras: **não tenho capturas do interior da
app** para estas quatro imagens. Para entrar no ecrã da loja é preciso iniciar sessão, e
escrever uma palavra-passe num formulário é coisa que eu não faço, nem em conta de teste.
O que tenho é a prova pelo lado dos dados, que é mais forte para saber se está lá, mas não
substitui ver com os olhos. Se quiseres a confirmação visual em meio minuto: abres
`app.boraguarda.com`, entras como cliente, e vais à Goola. Se alguma coisa não aparecer,
diz-me e eu ataco no ponto certo.

---

## O ladrilho da Lavagem Auto

Eram dois defeitos e estão os dois resolvidos.

O primeiro era não ter desenho nenhum — era só um ícone genérico de carro. Agora tem a
ilustração própria, no mesmo estilo dos outros ladrilhos. Tive de a limpar primeiro: a
imagem vinha com o fundo aos quadradinhos que os editores mostram para dizer que é
transparente, e esse xadrez ia aparecer na app tal e qual. Em vez de a recortar, que já
tinha corrido mal duas vezes por o carro ter mais cores do que o xadrez, medi a cor exacta
do quadrado claro e pintei-a por cima com o azul do fundo. Foram cento e noventa e oito
mil oitocentos e noventa e oito pixéis tapados, e o carro e as bolhas de sabão ficaram
intactos.

O segundo era o nome partir em três linhas e tapar o desenho. Agora quebra em duas linhas
limpas, "Lavagem" em cima e "Auto" em baixo, como já fazem o "Levar Compras" e o "Reservar
Mesa". O teste de imagem corre nas três larguras que pediste, trezentos e sessenta,
trezentos e noventa e quatrocentos e trinta, e passa nas três: nenhum rótulo transborda e
nenhum fica cortado, com as catorze categorias a caberem em quatro linhas de quatro, quatro,
quatro e duas.

---

## Os links antigos espalhados

Varri os quatro sites por inteiro e troquei cento e duas moradas em trinta ficheiros. Não
foi só o botão que viste no fim do site da Goola: apanhei canónicos, og:url, sitemaps,
robots, botões, rodapés, texto corrido e, o que mais importava, os próprios geradores dos
sites — o `site_base.py`, o `build.py` e os modelos do Sabores do Brasil. Se não se
arranjasse o gerador, a próxima construção punha os endereços velhos outra vez.

Faltavam três subdomínios para isto poder ficar completo, porque havia endereços públicos
sem casa no domínio novo, e a app no browser era o caso maior com sessenta e oito
referências espalhadas. Criei os três, cada um com as duas metades que isto exige, o
registo no DNS e o domínio próprio registado do lado do Pages: `app.boraguarda.com` para
a app no browser, `mrkebab.boraguarda.com` para o Mr Kebab e `festas.boraguarda.com` para
a demonstração das Festas.

Os oito endereços responderam todos duzentos com certificado válido quando os testei um a
um: o `boraguarda.com` e o `www` com o site institucional, o `app` com a app, o `goola`, o
`ouroeprata`, o `saboresdobrasil`, o `mrkebab` e o `festas`. E as páginas servidas já não
anunciam nenhum `.pages.dev` — contei as ocorrências no que está no ar e deu zero nos
quatro sites. Os endereços antigos continuam todos a servir, como pediste, porque há links
já enviados a clientes; deixaram foi de ser anunciados.

Dois sítios ficaram de fora de propósito e quero dizer quais. Os relatórios antigos e as
pastas de cópia de segurança mantêm os endereços velhos, porque são o registo do que
aconteceu naquele dia e reescrevê-los seria falsificar história. E o ficheiro `DOMINIOS.md`
também os mantém, porque a função dele é exactamente documentar que os antigos continuam
vivos.

Há um endereço antigo que **não** mexi e que é decisão tua: o link de recuperação de
palavra-passe dentro da app aponta para o endereço antigo da app no browser. Mudá-lo sem
mudar ao mesmo tempo a lista de endereços autorizados no Supabase parte a recuperação de
palavra-passe para toda a gente. Quando quiseres, faço as duas coisas na mesma corrida.

---

## O site da Goola, reconstruído

Reconstruí-o pelo método completo, e a peça que faltava era o vídeo.

O vídeo é feito das fotografias reais da Goola — as mesmas que estão na loja da app. Não
há nada gerado por inteligência artificial e nada de banco de imagens. São sete planos com
aproximação lenta e deriva, com fundido entre eles, dezoito segundos ao todo, sem som,
a repetir sozinho. A ordem conta uma história curta: chega-se à loja e vê-se quem atende,
depois o bowl, depois o pormenor dos acompanhamentos, depois o gelado, depois o copo na
mão do cliente, e fecha na fachada com clientes lá. Sai em dois formatos para o browser
escolher, e quem tiver o computador configurado para não querer animações vê uma imagem
parada em vez do filme.

Duas fotos tinham transparência e, ao converter à bruta, ficavam com fundo preto e as
margens serrilhadas. Assentei-as no creme da marca. E deixei a fotografia dos frutos de
açaí fora do vídeo: tem duzentos e trinta pixéis de largura, e esticada ao ecrã inteiro
virava papa. Continua no site, em tamanho pequeno, onde fica bem.

A segunda ronda, que é obrigatória e é onde a versão boa aparece, apanhou um defeito a
sério: o mapa em "onde estamos" estava vazio, era um quadro cinzento com o endereço a
transbordar por cima. Era um mapa de outro sítio, metido dentro da página, que não
carregava. Troquei-o por um mapa verdadeiro embutido na própria página, montado a partir
dos mosaicos do OpenStreetMap com um marcador desenhado na posição exacta da loja. Agora
aparece sempre, não depende de nada em tempo de execução, e o clique abre a rota no Google
Maps. As ruas da Guarda estão lá e o marcador está no La Vie.

O site foi publicado e está em `goola.boraguarda.com`. Confirmei que os três ficheiros do
vídeo estão mesmo a ser servidos: o mp4 com dois milhões e duzentos mil bytes, o webm com
um milhão e oitocentos mil, e a imagem de espera com cento e catorze mil, cada um com o
seu tipo certo. As capturas da segunda ronda ficaram em `goola-site/provas`.

---

## O estado das verificações

O `flutter analyze` corre com zero erros. São duzentos e cinquenta e seis avisos, que é a
linha de base desta branch e nenhum deles é erro. Os testes correm todos: duzentos e
cinquenta e dois passaram, nenhum falhou.

---

## O que fica por fazer, e de quem é

Teu, e urgente: trocar os dois tokens da Cloudflare, pela razão que está no princípio
deste relatório. E, se quiseres tirar já a cópia da cache, o purge de trinta segundos.

Teu, quando quiseres: ver com os olhos a loja da Goola dentro da app, que é a parte que eu
não consigo fotografar sem iniciar sessão.

Meu, quando disseres: o link de recuperação de palavra-passe passar para o domínio novo, ao
mesmo tempo que a lista de endereços autorizados no Supabase.
