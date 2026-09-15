# PARA O DANILO — o que só tu podes fazer nas redes do Bora
> Escrito 2026-09-02, missão `tudo-02-09`, bloco B.
> Está tudo preparado. Falta só o que as travas de segurança obrigam a ser humano.

---

## 1. O que travou, e porquê

O Chrome está ligado a esta sessão, mas **o Facebook não tem sessão iniciada**.
Deixei o ecrã de login aberto e já recusei os cookies opcionais por ti.
A ordem dizia exactamente isto: se não houver sessão, deixar o login no ecrã e parar.

Além disso há uma trava minha que não posso contornar mesmo com ordem tua:
**não posso criar contas nem escrever palavras-passe.** Isso apanha a conta nova
do Instagram (ponto B2). A página do Facebook e o resto eu faço, assim que
houver sessão.

---

## 2. O clique que falta (por ordem)

**Passo 1 — inicia sessão no Facebook.**
A janela já está aberta no ecrã, no teu Chrome. Escreve o e-mail e a palavra-passe
e carrega em "Iniciar sessão". Depois diz-me "entrei" e eu continuo sozinho a
partir daí: crio a página, meto o logo, a capa, a descrição, a morada, o botão
do WhatsApp e os links.

**Passo 2 — a conta do Instagram.**
Esta tens de ser tu a criar, porque envolve palavra-passe. Quando chegares aí,
abro-te a página e paro. O e-mail a usar é `boraappbora@gmail.com` e o nome de
utilizador a tentar é `boraappguarda`.

**Passo 3 — os botões de autorização da Meta.**
Na app de programador ("Bora Social") há um botão de consentimento que só a
pessoa pode carregar. Deixo-o no ecrã e digo-te numa linha o que carregar.

---

## 3. Campos exactos da página do Facebook (já decididos, não precisas de pensar)

| Campo | Valor |
|---|---|
| Nome da página | **Bora App Guarda** |
| Categoria | Aplicação · Serviço de entregas |
| Nome de utilizador | `boraappguarda` (ou o mais próximo que estiver livre) |
| Site | `https://bora-site.pages.dev` |
| Link da app | `https://play.google.com/store/apps/details?id=pt.boraapp.bora` |
| Morada | Guarda, Portugal |
| Telefone / WhatsApp | +351 937 501 673 |
| E-mail | boraappbora@gmail.com |
| Botão de acção | Enviar mensagem no WhatsApp |

**Descrição curta (PT-PT), para colar tal e qual:**

> O Bora é a app da Guarda. Restaurantes, supermercados, farmácia, boleias,
> limpezas e favores, tudo num só sítio e com o preço à vista antes de
> confirmares. Primeiro pedido com o código BEMVINDO.

---

## 3b. Campos do Instagram (para quando a conta existir)

| Campo | Valor |
|---|---|
| Nome de utilizador | `boraappguarda` (ou o mais próximo livre) |
| E-mail | boraappbora@gmail.com |
| Nome a mostrar | Bora App · Guarda |
| Tipo de conta | Profissional → Empresa, ligada à página do Facebook |
| Foto | `perfil-1024x1024.jpg` (o logo real) |
| Link | `https://play.google.com/store/apps/details?id=pt.boraapp.bora` |

**Bio (PT-PT, 125 caracteres contados, o limite do Instagram são 150):**

```
A Guarda inteira num só ecrã.
Comida, mercado, farmácia, boleias, limpezas e favores.
Primeiro pedido com o código BEMVINDO 👇
```

---

## 4. O material está pronto no disco

| Ficheiro | Para que serve |
|---|---|
| `.claude/.ai/social/bora/perfil-1024x1024.jpg` | foto de perfil (o logo real do Bora) |
| `.claude/.ai/social/bora/capa-facebook-1920x1080.jpg` | capa 16:9 |
| `.claude/.ai/social/bora/textos-pt-pt.md` | 3 textos por tema, todos com BEMVINDO e o link |

A capa foi montada por script, só com material verdadeiro: o logo do Bora e os
ícones de categoria do próprio site. **Zero imagens de IA.**

---

## 5. O que ficou feito sem precisar de ti

- A capa e a foto de perfil.
- Os textos das publicações, sete temas, três textos cada.
- O script de publicação automática e a tarefa agendada (bloco B4) — fica
  preparado e **inerte** até existirem os três valores da Meta
  (`META_PAGE_TOKEN`, `META_PAGE_ID`, `IG_USER_ID`). Assim que tu deres os
  cliques, ele acorda sozinho na segunda-feira seguinte.
