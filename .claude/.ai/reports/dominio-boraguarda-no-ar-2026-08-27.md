# O domínio boraguarda.com está no ar — 27 de agosto de 2026

---

## APAGA O TOKEN

Antes de tudo o resto: podes apagar na Cloudflare o token de DNS que me mandaste, porque passou pelo chat. Já não é preciso para nada. Vais a dash.cloudflare.com barra profile barra api-tokens, encontras a linha do token que criaste, carregas nos três pontinhos à direita e escolhes Delete.

Se um dia precisares de acrescentar outro mini-site, crias um novo pelo mesmo caminho, que está escrito no ficheiro DOMINIOS.md que deixei na pasta do bora-site.

---

## ESTÁ TUDO NO AR. OS CINCO ENDEREÇOS

Fiz um pedido real a cada um, com verificação de certificado ligada, e todos responderam código duzentos com o certificado validado. Digo-te o que cada um devolveu.

O boraguarda.com devolveu duzentos, trinta e seis mil cento e cinquenta e oito bytes, e o título da página é Bora App, Entregas, Viagens e Reservas na Guarda.

O www.boraguarda.com devolveu exactamente o mesmo, os mesmos bytes e o mesmo título, como devia, porque aponta ao mesmo sítio.

O goola.boraguarda.com devolveu duzentos, quinhentos mil setecentos e trinta e oito bytes, e o título é Goola Açaí Guarda, açaí de verdade, entregue em casa.

O ouroeprata.boraguarda.com devolveu duzentos, um milhão e quinhentos mil bytes, e o título é Barbearia Ouro e Prata, Guarda.

O saboresdobrasil.boraguarda.com devolveu duzentos, trinta e nove mil cento e um bytes, e o título é Sabores do Brasil, Keli Barbosa, Guarda.

Os certificados são emitidos pela Google Trust Services e renovam-se sozinhos. O da raiz é válido até vinte e cinco de novembro.

Os endereços antigos continuam todos a servir e não desliguei nenhum. Testei os quatro na mesma corrida: bora-site.pages.dev, goola-guarda.pages.dev, ouro-e-prata.pages.dev e sabores-do-brasil.pages.dev, todos a duzentos, todos com o site certo. Quem já recebeu um desses links continua a poder usá-lo.

Não criei subdomínio para mais nenhuma loja, como mandaste.

---

## O QUE FALTAVA, E PORQUE É QUE O TEU TOKEN RESOLVEU

O que faltava era mesmo só o registo de DNS. A zona estava activa mas completamente vazia, sem um único registo. Por isso os cinco endereços estavam presos em pendente do lado do Pages: o Pages sabia que aqueles nomes eram dele, mas não havia nada no DNS a mandar o tráfego para lá.

Com o teu token novo vi a zona à primeira e criei os cinco registos. São todos CNAME com o proxy ligado, aquela nuvem laranja, a apontar para o endereço pages.dev de cada projecto. Na raiz também deu para usar CNAME porque a Cloudflare trata disso sozinha.

Depois disso os certificados demoraram três minutos e vinte e oito segundos a ficar todos emitidos. Fiquei à espera e só auditei no fim, como mandaste, para não apanhar a Cloudflare a meio.

Aproveito para fechar a dúvida que te tinha deixado em aberto na sessão anterior, sobre a confirmação de email do registo. Com este token consegui finalmente ler o estado da zona: está activa e não está pausada. Uma zona com o contacto por confirmar não fica assim. Portanto está em ordem, e agora é uma leitura minha, não um palpite.

---

## UMA COISA QUE TE PODE ASSUSTAR E NÃO É NADA

Durante quase meia hora depois de criar os registos, os quatro subdomínios ainda diziam que não existiam quando eu os abria daqui. A raiz funcionava, os subdomínios não.

Não era erro de configuração. Era o teu fornecedor de internet a guardar a resposta negativa antiga. A zona tem um tempo de guarda de trinta minutos para respostas de não existe, e o resolver do fornecedor cumpre isso à risca. Pelo servidor público da Cloudflare, o um ponto um ponto um ponto um, os quatro já respondiam certos desde o primeiro minuto.

Enquanto esperei, provei que os sites já estavam bons forçando o endereço IP directamente, sem depender do resolver. Os quatro devolveram duzentos com o certificado validado e cada um com o seu título próprio. Ao fim dos trinta minutos passaram a resolver normalmente também aqui, e foi aí que fiz a auditoria final.

Deixei isto escrito no DOMINIOS.md com o comando exacto, para não te assustares se acontecer outra vez com um site novo.

---

## OS TOKENS, E PORQUE SÃO DOIS

Guardei o token novo no ficheiro .env da pasta do bora-site, numa variável nova chamada CLOUDFLARE_DNS_TOKEN. Não substituí o que lá estava: o antigo, o CLOUDFLARE_API_TOKEN, é de Pages e continua intacto. São dois tokens com funções diferentes e os dois são precisos.

O de Pages cria projectos, publica sites e regista os endereços do lado do Pages, mas não vê zonas nem mexe em DNS. O de DNS faz só os registos, e só na zona boraguarda.com. Foi exactamente por faltar o segundo que os cinco endereços ficaram presos em pendente na sessão passada.

Sobre a segurança do ficheiro, verifiquei antes de escrever lá dentro, como mandaste. O .env está no .gitignore, e confirmei com o próprio git que ele o ignora mesmo. Confirmei também que nunca esteve registado no git e que nunca apareceu no histórico.

Houve um pormenor que apanhei e corrigi. Ao escrever no .env, fiz primeiro uma cópia de segurança chamada .env.bak-antes-dns, por hábito. Só que o .gitignore protege o nome .env exacto, não protege nomes parecidos, e essa cópia ficou visível ao git com o token lá dentro. Apaguei-a logo e confirmei que o git já não vê ficheiro nenhum com tokens. Não chegou a ir a lado nenhum, mas ficas a saber que aconteceu.

Antes de fazer o commit, verifiquei ainda que nenhum ficheiro que ia entrar continha o token. Deu zero.

---

## O QUE ACTUALIZEI DENTRO DOS SITES

O site institucional tinha o endereço antigo escrito em quinze ficheiros, num total de setenta e seis sítios, entre canónicos, og:url, sitemap, robots e as migalhas de navegação. Troquei todos para boraguarda.com e voltei a publicar. Confirmei no que está servido agora: tanto o boraguarda.com como o bora-site.pages.dev anunciam o mesmo canónico, o novo, que é o que evita o Google indexar a mesma coisa duas vezes.

A pasta backup-2026-07-19 não toquei, porque é histórico.

O mini-site da Goola já tinha sido actualizado na sessão anterior e continua certo.

Os sites da barbearia e do Sabores do Brasil não têm canónico nem og:url nenhum no HTML, por isso não havia lá nada para trocar. Ficam a servir bem nos dois endereços na mesma.

---

## FICOU REGISTADO PARA NÃO SE PERDER

Escrevi um ficheiro chamado DOMINIOS.md na pasta do bora-site, e já está em git. Tem a tabela de quem aponta para onde, a explicação de que são precisas as duas metades, o registo de DNS e o endereço do lado do Pages, a nota dos dois tokens, a receita passo a passo para acrescentar um mini-site novo, e o aviso da cache de trinta minutos com o comando para provar que o site está bom antes de o DNS assentar.

O commit no bora-site é o 41ad7b2.

---

## SOBRE A MANUTENÇÃO DE SÁBADO

Avisaste que a Cloudflare tem manutenção no sábado, dia vinte e nove, das nove às dez da manhã em UTC, e que nessa hora mudanças de zona podem falhar. Não apanhei essa janela: fiz tudo hoje, quinta-feira à noite. Fica a nota para o caso de quereres acrescentar algum endereço novo, que nessa hora é melhor esperar.

---

## O QUE FICA POR FAZER

Nada do que pediste neste adendo. Os cinco endereços estão no ar, com certificado, provados um a um. Os antigos continuam vivos. Os canónicos apontam ao sítio certo. Está tudo registado em git.

A única coisa que continua pendente, e que vem de trás, é o telefone, o email e as fotografias próprias da Goola, que não existem em fonte pública nenhuma que eu consiga alcançar. Os campos estão prontos no painel para quando os tiveres.
