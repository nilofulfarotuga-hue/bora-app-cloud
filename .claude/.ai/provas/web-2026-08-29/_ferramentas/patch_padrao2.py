import io
import os

os.chdir(r"C:\Users\danil\Desktop\projetosflutter\_wt-prod")
p = "PADRAO_BORA.md"
s = io.open(p, encoding="utf-8").read()

NOVO = """
### 1.25 Uma conta, uma pessoa, todos os perfis

**Quem tem conta no Bora pode ser tudo o que quiser ser, com o mesmo email e a
mesma palavra-passe.** Estafeta que quer pedir o jantar. Lojista que quer fazer
uma entrega. Faxineira que quer lavar carros. Ninguém cria uma segunda conta,
e nenhuma porta expulsa quem entra por ela.

Três coisas que daqui saem, e que são regra:

**Nunca se faz `signOut` por causa de papel.** A pessoa autenticou-se com a
palavra-passe certa; pô-la fora porque o perfil não bate é dizer-lhe que a
palavra-passe está errada quando não está. Se lhe falta o perfil dessa porta,
diz-se isso — não se corta a sessão.

**A verdade de quem é o quê vive em `user_roles`, nunca no `bora_role`.** O
`user_metadata.bora_role` é um campo **único**: guarda o modo em que a app
ficou da última vez, e é substituído a cada troca. Só `user_roles` aguenta
acumulação, porque é uma linha por papel.

**Cliente não tem candidatura.** Quem tem conta pode ser cliente. Se lhe falta
a linha, cria-se (`add_client_role_to_me`) e segue-se — não se pergunta nada.

> **Cicatriz (28–29/08), e custou um cliente real:** um estafeta com
> candidatura em análise tentou usar a app como cliente. Nos `auth_logs`, o
> mecanismo repetido quatro vezes: `Login 200` às 23:11:33, `logout` às
> 23:11:41. Outra vez às 23:13:58, às 23:15:45, às 23:16:17. A palavra-passe
> estava certa em todas. Era a app que o deitava fora. Teve de lhe ser criada
> uma conta com `+cliente` no email para poder experimentar o Bora.
>
> **Cicatriz gémea, no mesmo dia:** o ecrã de escolha de perfil fazia
> `logout()` em **todos** os botões, mesmo com sessão aberta. Quem já estava
> dentro e queria só mudar de perfil era posto fora e obrigado a escrever a
> palavra-passe. Corrigir só o login não teria chegado.
>
> **Cicatriz irmã:** "Candidatura em análise" era uma parede com um único
> botão: "Sair". O perfil que está a ser revisto é **um**; a app é a mesma. Um
> pedido pendente nunca bloqueia os outros perfis.

E as portas do arranque dizem **a quem se destinam**. Uma pessoa sozinha caiu
nas três numa noite porque "Sou Estafeta" e "Sou Parceiro" não explicavam nada.
As três são iguais nisto, e as três têm caminho de volta — a do parceiro não
tinha.

### 1.26 Nenhum ecrã fica preso à espera de uma permissão

Toda a espera por uma permissão ou por hardware tem **limite de tempo**, e toda
a recusa tem **ecrã que explica**, em português, com o que fazer a seguir.

Um `try/catch` com recurso **não chega e engana**: parece coberto.

> **Cicatriz (29/08):** o ecrã do estafeta bloqueia a render até ter uma
> posição de GPS. O código tinha `try/catch` e caía no centro da Guarda — mas
> `Geolocator.getCurrentPosition()` **não devolve e não rebenta** quando a
> posição nunca chega (no browser, ou com o pedido de permissão por responder).
> O `catch` nunca corria, a variável nunca deixava de ser nula, e o carregador
> rodava **para sempre**, sem uma palavra. Quem instala, recusa o GPS e vê
> isto, desinstala e não volta.
>
> **Cicatriz gémea:** o mesmo `await` sem limite no ecrã do motorista TVDE,
> onde prendia o arranque do fluxo de posição inteiro.

**Lei que daqui sai:** procura `await` sobre hardware ou permissões sem
`.timeout(...)`. Cada um é um ecrã que pode ficar preso.

"""

ancora = "\n## 2. ONDE CADA COISA VIVE — A REGRA DOS GÉMEOS"
assert ancora in s
s = s.replace(ancora, NOVO + ancora, 1)
s = s.replace(
    "## 1. LISTA FECHADA — categoria nova ou papel novo",
    "## 1. LISTA FECHADA — categoria nova ou papel novo", 1)

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("PADRAO_BORA: 1.25 e 1.26 escritas")
