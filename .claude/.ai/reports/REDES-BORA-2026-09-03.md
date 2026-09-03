# REDES BORA — 2026-09-03

> Sessão `redes-bora-do-zero`. Motor: Claude Opus 5, Claude Code, PC novo.
> Portão de RAM medido no início: **1845 MB** disponíveis, acima do portão leve
> (400) e do pesado (800). Nada precisou de ser libertado.

---

## O QUE O DANILO TEM DE CLICAR AGORA

**São três coisas, e a primeira desbloqueia-me a mim.**

1. **No Chrome, abre o painel lateral do Claude e inicia sessão.** O Chrome já
   está aberto, mas a extensão não fala comigo até esse painel ser aberto uma vez.
   Enquanto isso não acontecer eu não consigo ver nem tocar em página nenhuma.

2. **Cria a conta do Facebook e a do Instagram tu mesmo.** Eu abro-te as páginas
   no sítio certo e tenho todos os campos escritos, mas criar conta e escrever
   palavras-passe é uma trava minha que não se levanta.

3. **Diz-me o que fazer com o BoraStudio.** Ver a secção do BoraStudio mais abaixo:
   o repositório não tem para onde ser empurrado, e criar-lhe um lugar novo é
   decisão tua.

---

## A trava, dita de frente

A ordem mandava-me criar do zero uma conta pessoal de Facebook, uma conta de
Instagram, e escrever palavras-passe e códigos de confirmação por ti.

**Não posso fazer isso.** Criar contas e introduzir palavras-passe são coisas que
não faço, e não é uma regra que uma ordem tua levante — é uma trava minha, igual à
de não tocar em cartões. Digo-o aqui em vez de tentar e falhar a meio, porque a
meio seria pior.

O que **posso** fazer, e está tudo pronto para o segundo em que as contas
existirem: configurar a página inteira, ligar o Instagram à página, criar a app da
Meta, instalar as credenciais na VPS e pôr o publicador a funcionar.

---

## O que ficou feito nesta sessão

### 1. Um instalador de credenciais que te pede UM valor em vez de três

`/opt/data/scripts/meta-credenciais.sh` (6511 bytes, `bash -n` limpo).

O publicador precisa de três valores no `.env`: `META_PAGE_TOKEN`, `META_PAGE_ID`
e `IG_USER_ID`. Copiar três coisas à mão de um painel da Meta é onde se erra. Este
script pede **só o token da página** e vai buscar os outros dois à própria Meta.

O que ele faz, por ordem:

- Lê o token **pela entrada padrão**, nunca como argumento — para não ficar gravado
  no histórico da shell nem visível num `ps`.
- Pergunta à Meta de quem é o token, e diz-te o **nome da página**. Se lhe deres um
  token de utilizador em vez de um de página (o engano clássico), avisa, porque
  esse publicaria em nome da pessoa e não da página.
- Verifica **quanto tempo o token dura**. Se for um token curto, diz-to à cara:
  o publicador ia parar sozinho quando ele morresse.
- Vai buscar o **Instagram ligado à página**. Se não houver nenhum, grava na mesma
  o que tem e o publicador fica a publicar só no Facebook.
- Grava no `.env` com cópia de segurança ao lado, modo 600, **sem apagar o que lá
  estava**.
- **Nunca imprime o token.**

**Provado com os três caminhos de falha**, sem token verdadeiro nenhum:

```
teste 1 (nada)          -> ERRO: nao veio token nenhum pela entrada padrao
teste 2 (texto qualquer)-> ERRO: isto nao parece um token da Meta (comecam por EAA)
teste 3 (EAA... falso)  -> ERRO: a Meta recusou o token: Malformed access token
```

O terceiro é o que interessa: **"Malformed access token" é a mensagem da própria
Meta**, o que prova que o script chega mesmo aos servidores deles e não morre antes
por um erro meu.

**O `.env` verdadeiro não foi tocado**, e isso está provado pelo md5, igual antes e
depois de os três testes correrem:

```
antes:  3bd4b55ada071021f1a9e56ec0919904  /opt/data/.env
depois: 3bd4b55ada071021f1a9e56ec0919904  /opt/data/.env
```

### 2. Confirmado que o publicador continua inerte, e porquê

```
$ social-bora.sh
SALTA: hoje e dia 4 da semana em Lisboa; so se publica segunda, quarta e sexta
codigo de saida: 0

$ grep -c "^META_PAGE_TOKEN=|^META_PAGE_ID=|^IG_USER_ID=" /opt/data/.env
0
```

Nenhum dos três nomes está no `.env`. Hoje é quinta-feira, e a guarda do dia
dispara antes da verificação das credenciais — as duas travas funcionam.

### 3. O material das redes continua intacto e certo

```
capa-facebook-1920x1080.jpg: (1920, 1080) RGB 201028 bytes -> OK
perfil-1024x1024.jpg:        (1024, 1024) RGB  86478 bytes -> OK
```

Mais `PARA-O-DANILO-redes.md` (os campos exactos da página e do Instagram, com a
bio de 125 caracteres já contada), `textos-pt-pt.md` (7 temas × 3 textos) e
`grupos.md`.

---

## BoraStudio — a ordem partia de uma premissa errada

A ordem dizia: *"O BoraStudio tem 20 commits sem push: fazer push desse repo."*

**Fui ver, e não é isso.**

```
ramo:    master
remoto:  NENHUM
commits: 315 no total
```

O repositório **não tem remoto configurado**. Não são 20 commits por empurrar — são
**315 commits que nunca saíram deste PC**, porque não há para onde saírem. Um
`git push` ali dá erro, não dá sucesso.

**Não criei um lugar novo por minha conta**, e explico porquê. Criar um repositório
para o BoraStudio é publicar trabalho teu num sítio novo, e o BoraStudio é
precisamente a pasta que as regras da casa marcam como intocável: a `producao.db`,
o canon, as bíblias, os clipes e as vozes. Escolher onde isso passa a viver, e se
fica privado, é decisão tua e não minha.

**Há uma segunda coisa que tens de saber antes de decidires.** A pasta tem **212
ficheiros alterados por commitar**, e a grande maioria são **apagamentos** dentro de
`_substituido/arte_v1_vetorial_personagens/` — bocas, cabeças, corpos e expressões
da Avó Mónica, entre outros. Não fui eu que os apaguei; já estavam assim. Se se
criasse um repositório e se commitasse tudo às cegas, esses apagamentos ficavam
gravados como se fossem uma decisão. Não toquei em nada.

---

## O que ficou por fazer, e porquê

| Ponto da ordem | Estado | Porquê |
|---|---|---|
| 1. Sessão Google com boraappbora@gmail.com | **não feito** | escrever palavra-passe é trava minha |
| 2. Criar conta de Facebook | **não feito** | criar conta é trava minha |
| 3. Criar a página "Bora App Guarda" | **por fazer** | depende da conta existir |
| 4. Criar o Instagram | **não feito** | criar conta é trava minha |
| 5. App Meta "Bora Social" | **por fazer** | depende da conta existir |
| 6. Publicação de teste pela API | **por fazer** | depende das credenciais |
| 7. Ler o pagamento do Google Cloud | **por fazer** | a extensão do Chrome não liga |
| 8. Deixar as páginas abertas no ecrã | **por fazer** | idem |

**O ponto 7 merece uma nota.** Ler o resumo de pagamentos do Google Cloud é coisa
que eu faço sem problema nenhum — é leitura, não é pagar. Ficou por fazer só porque
a extensão do Chrome não está ligada. Abri o Chrome (15 processos a correr) e
confirmei que a extensão está instalada nos dois perfis, `Default` e `Profile 1`,
versão 1.0.90. Falta abrir o painel uma vez.

---

## O que fica POR CONFIRMAR

1. **As contas não existem.** Nem Facebook, nem Instagram, nem app da Meta.
2. **O instalador de credenciais nunca correu com um token verdadeiro.** Estão
   provados os três caminhos de falha e a conversa com a Meta; o caminho de sucesso
   fica por ver.
3. **O valor em dívida do Google Cloud continua por ler.** O aviso de pagamento
   recusado de ontem mantém-se sem número ao lado.
4. **O BoraStudio continua só neste PC**, com 315 commits e 212 ficheiros por
   commitar, à espera da tua decisão.
