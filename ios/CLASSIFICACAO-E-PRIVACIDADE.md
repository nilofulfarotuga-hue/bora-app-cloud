# Classificação etária e etiqueta de privacidade — rascunho respondido

> Missão `ios-lancamento`, 2026-09-08. **Rascunho para colar no App Store
> Connect.** Cada resposta diz de onde saiu: ou de uma página da Apple, ou de
> uma medição ao banco de produção. Onde a resposta é um juízo e não um facto,
> está dito.

---

## 1. Classificação etária

**Página da Apple usada:**
<https://developer.apple.com/help/app-store-connect/reference/age-ratings/>
("Age ratings values and definitions"). As definições abaixo são citadas dela.

### 1.1 O que a app tem, medido

| O que se procurou | Onde | Resultado |
|---|---|---|
| Tabaco à venda | `products` × `restaurants` online, expressão `tabaco\|cigarr\|charuto\|isqueir\|vape\|nicotin\|snus\|shisha` | **10 acertos, nenhum é tabaco**: 6 isqueiros BIC (categoria "Barbecues e Carvão"), 2 ambientadores *anti*-tabaco, 1 bomba de campismo com isqueiro, e gomas **Nicotinell 2 mg** — medicamento não sujeito a receita, vendido pela **Wells**, que é farmácia |
| Álcool à venda | mesma consulta, expressão de bebidas | **4113 produtos em 6 lojas** |
| Jogo a dinheiro | não existe no produto | nenhum |
| Navegação livre na web | não existe navegador embutido | nenhum |
| Conteúdo de utilizadores | avaliações e chat cliente↔estafeta | existe, fechado entre as partes de um pedido |

### 1.2 Porque o tabaco importa e está resolvido

As [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
dizem, em 1.4.3:

> "Apps that encourage consumption of tobacco and vape products, illegal drugs,
> or excessive amounts of alcohol are not permitted."
> "Facilitating the sale of controlled substances (except for licensed
> pharmacies and licensed or otherwise legal cannabis dispensaries), or tobacco
> is not allowed."

Facilitar a venda de tabaco **não é permitido**. Fomos ver um a um: não há
tabaco no catálogo. Isqueiros não são tabaco, e a goma de nicotina é
medicamento para *deixar* de fumar, vendido por farmácia licenciada — a
excepção que a própria regra prevê. **Nada a corrigir, mas a resposta agora
está provada em vez de assumida.**

### 1.3 Respostas ao questionário

| Pergunta (agrupada como a Apple a mostra) | Resposta | Porquê |
|---|---|---|
| Violência (desenhada, realista, prolongada) | **Nenhuma** | não há |
| Temas maduros, profanidade, humor grosseiro | **Nenhuma** | não há |
| Terror / medo | **Nenhuma** | não há |
| Sexualidade e nudez | **Nenhuma** | não há |
| Álcool, tabaco ou drogas — uso ou referência | **⚠️ ver 1.4** | 4113 produtos com álcool no catálogo |
| Informação médica ou de tratamento | **Nenhuma** | a farmácia vende produtos, a app não dá diagnóstico nem orientação |
| Jogo a dinheiro (real) | **Não** | não existe |
| Jogo simulado | **Não** | não existe |
| Concursos | **Não** | não existe |
| Caixas de recompensa | **Não** | não existe |
| Acesso livre à web | **Não** | não há navegador embutido |
| Conteúdo criado por utilizadores | **Sim, limitado** | avaliações e chat de um pedido, não distribuição alargada |
| Mensagens e chat | **Sim** | a Apple lista isto **dentro do 4+** |
| Publicidade | **Não** | a app não mostra anúncios |
| Controlos parentais / verificação de idade | **Não** | não existem hoje |

### 1.4 A única resposta que é juízo e não facto — o álcool

O escalão **12+** cobre, palavras da Apple, *"Infrequent alcohol, tobacco, or
drug use or reference"*. O catálogo tem **4113** artigos com álcool, o que de
infrequente não tem nada.

Mas a pergunta da Apple é sobre **conteúdo** — cenas, imagens, referências
dentro da app — e não sobre uma prateleira de supermercado. Uma app de
mercearia que lista cerveja e vinho entre dezenas de milhares de artigos não
está a "referir consumo de álcool" no sentido do questionário.

**Recomendação:** responder **4+** no questionário, e deixar que a App Review
suba se discordar — subir depois é um clique, e responder alto de propósito
custa descoberta na loja para sempre. Se o revisor levantar a questão, a
resposta honesta é a de cima: é comércio de mercearia, não conteúdo.

**A decidir por quem manda, e é a única coisa deste ficheiro que não decido:**
se se quer, além disto, um **portão de idade** no carrinho quando leva álcool.
A lei portuguesa proíbe vender álcool a menores de 18, e hoje a app não
pergunta a idade a ninguém. Isso é obrigação legal nossa, independente da
Apple. **Fica escrito como pendente, não como feito.**

---

## 2. Etiqueta de privacidade (App Privacy)

**Páginas da Apple usadas:**
<https://developer.apple.com/app-store/app-privacy-details/> — em especial:

> "You'll need to provide information about your app's privacy practices,
> **including the practices of third-party partners whose code you integrate
> into your app**, in App Store Connect. This information is required to submit
> new apps and app updates to the App Store."

### 2.1 O que a app já declara no manifesto

Lido de `ios/Runner/PrivacyInfo.xcprivacy` com `plistlib` (não copiado à mão):

- `NSPrivacyTracking`: **false** · `NSPrivacyTrackingDomains`: **vazio**
- Tipos recolhidos, todos com fim `AppFunctionality` e **nenhum** para rastreio:

| Tipo | Ligado à pessoa |
|---|---|
| Precise Location | sim |
| Name | sim |
| Email Address | sim |
| Phone Number | sim |
| Purchase History | sim |
| Photos or Videos | sim |
| Device ID | sim |
| Crash Data | **não** |

- APIs de motivo declarado: `UserDefaults` (CA92.1), `FileTimestamp` (C617.1),
  `DiskSpace` (E174.1).

### 2.2 Como responder no formulário

Para cada tipo acima: **Data Used to Track You → Não** · **Data Linked to
You → sim**, excepto Crash Data, que vai em **Data Not Linked to You** ·
finalidade **App Functionality** em todos.

Correspondência para os nomes do formulário: Precise Location → *Location ›
Precise Location*; Name/Email/Phone → *Contact Info*; Purchase History →
*Purchases*; Photos or Videos → *User Content*; Device ID → *Identifiers ›
Device ID*; Crash Data → *Diagnostics › Crash Data*.

### 2.3 ⚠️ Duas lacunas encontradas ao cruzar o manifesto com o que a app faz

Isto não veio de ler o manifesto — veio de o comparar com o código:

1. **Payment Info não está declarado.** A app cobra com o `flutter_stripe`, e a
   folha de pagamento da Stripe recolhe os dados do cartão **dentro da app**. A
   página da Apple manda declarar também o que fazem os SDK de terceiros que
   integramos. Falta `Payment Info` no manifesto e no formulário.
2. **Conteúdo de chat não está declarado.** Há chat entre cliente e estafeta e
   suporte; as mensagens são conteúdo do utilizador e provavelmente entram em
   *User Content › Customer Support* ou *Other User Content*. Hoje só está lá
   `Photos or Videos`.

Nenhuma das duas impede submeter, mas uma etiqueta que não bate certo com o que
a app faz é motivo conhecido de recusa e de correcção posterior. **Corrigir o
`PrivacyInfo.xcprivacy` e o formulário antes de submeter.**
