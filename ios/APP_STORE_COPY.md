# TEXTOS DA LOJA — App Store Connect

> Missão `ios-lancamento`. Reescrito a 2026-09-08.
> **Prontos a colar.** Idioma principal: **Português (Portugal)**.
>
> Os limites de cada campo estão confirmados na documentação, não de cor:
> nome e subtítulo em
> <https://developer.apple.com/help/app-store-connect/reference/app-information/>
> ("The name must be at least two characters and no more than 30 characters" ·
> subtítulo "can't be longer than 30 characters"); descrição, palavras-chave,
> texto promocional e novidades em
> <https://developer.apple.com/help/app-store-connect/reference/platform-version-information/>.
>
> **Regra que atravessa tudo isto:** nada nestes textos promete loja, serviço
> ou preço que não exista no banco de produção — a mesma regra das capturas.
> E não se nomeiam as cadeias onde a Bora só compra: além da decisão do Danilo,
> a Apple proíbe-o explicitamente nas palavras-chave (ver §4).

---

## 1. Nome (2 a 30 caracteres)

```
Bora — entregas e serviços
```
**26 caracteres.** Alternativa já dentro do limite se o nome estiver ocupado:
`Bora App Guarda` (15).

## 2. Subtítulo (máx. 30 caracteres)

```
Mercado, comida e serviços
```
**26 caracteres.**

## 3. Categorias

- **Primária:** Food & Drink
- **Secundária:** Lifestyle

## 4. Palavras-chave (máx. **100 bytes**)

A Apple diz, textualmente:

> "One or more keywords (each greater than two characters) describing your app.
> You can provide up to **100 bytes** of content. Your app is searchable by app
> name and company name, so you shouldn't duplicate these values in the keyword
> list. **Names of other apps or companies aren't allowed.**"

Por isso: sem acentos (cada acento gasta 2 bytes), sem repetir "Bora", e **sem
uma única marca de terceiros**.

```
mercado,supermercado,entrega,estafeta,barbearia,limpeza,favores,lavagem,farmacia
```
**80 bytes.** Sobram 20 bytes se se quiser acrescentar algo depois.

## 5. Texto promocional (máx. 170 caracteres — muda sem nova revisão)

```
Mercado, restaurantes, barbearia, limpeza, favores e lavagem auto. Tudo na Guarda, entregue por quem conhece a cidade.
```
**118 caracteres.**

## 6. Descrição (máx. 4000 caracteres, texto simples, sem HTML)

```
O Bora é a app de entregas e serviços da Guarda.

Num sítio só, aquilo de que precisa na cidade — e entregue por gente da cidade.

O QUE PODE PEDIR

Mercado
Faça a compra dos supermercados e lojas da Guarda sem sair de casa. Milhares de artigos, com o preço à vista antes de pedir.

Farmácia
Produtos de farmácia e parafarmácia entregues em casa.

Restaurantes
Peça a refeição e acompanhe-a até à porta.

Barbearia e cabeleireiro
Escolha o serviço e a hora, e marque sem telefonar.

Limpeza doméstica
Marque uma limpeza para a sua casa, com dia e hora à sua escolha. O preço depende da tipologia da casa e vê-o antes de confirmar.

Favores
Precisa de uma compra específica, de levantar uma encomenda ou de levar algo a alguém? Descreva o que precisa e um estafeta trata disso.

Lavagem auto
Marque a lavagem do carro e o lavador vai ter consigo.

COMO FUNCIONA

Escolha, pague e acompanhe o pedido no mapa, do preparo à entrega.
Pague como preferir: cartão, MB WAY ou dinheiro à entrega.
Avalie no fim — e o estafeta também o avalia. A confiança é dos dois lados.

FEITO PARA A GUARDA

O Bora não é uma app nacional que passou por aqui. Foi feita para esta cidade, com as lojas desta cidade e estafetas que conhecem as ruas.

A SUA CONTA É SUA

Pode apagar a conta dentro da app, sem enviar email a ninguém e sem esperar por resposta. Os seus dados pessoais são destruídos; só ficam, de forma anónima, os registos que a lei fiscal obriga a guardar.

Suporte: boraappbora@gmail.com
Política de privacidade: https://boraguarda.com/privacidade
Termos e condições: https://boraguarda.com/termos
```

## 7. Novidades desta versão (máx. 4000 caracteres)

```
Primeira versão do Bora para iPhone.

Mercado, farmácia, restaurantes, barbearia, limpeza doméstica, favores e lavagem auto — tudo numa app só, feita para a Guarda.
```

## 8. URLs

| Campo | Valor | Prova |
|---|---|---|
| Marketing URL | `https://boraguarda.com` | HTTP 200 |
| Support URL | `https://boraguarda.com/faq` | HTTP 200 |
| Privacy Policy URL | `https://boraguarda.com/privacidade` | HTTP 200 (o `.html` antigo responde 308 — usar **sempre** sem extensão) |
| Termos | `https://boraguarda.com/termos` | HTTP 200 |
| Email de suporte | `boraappbora@gmail.com` | — |

## 9. Direitos de autor

```
© 2026 Danilo Fulfaro da Silva
```

## 10. Classificação etária e privacidade

Estão respondidas, com a página da Apple de onde saiu cada resposta, em
**`ios/CLASSIFICACAO-E-PRIVACIDADE.md`**. Não repetir aqui, para não haver duas
versões da mesma resposta.

## 11. Capturas de ecrã

As capturas saem da **app real a correr**, nunca de ecrãs desenhados — ver
`integration_test/demo_real_test.dart` e a cicatriz em
`ios/LANCAMENTO-IOS-ESTADO.md` §-2. Só entram as `NN-loja-*`, e passam antes
por `ios/tools/preparar_capturas_loja.py`, que lhes tira o canal alfa (a Apple
recusa capturas com alfa).

**Nunca** incluir carro particular, boleias ou TVDE em captura nenhuma nem em
nenhum destes textos — não é o que se vende nesta versão.

## 12. Contas de demonstração

Ver `ios/NOTAS-AO-REVISOR.md`: `demo@bora.app` para navegar e
`demo.apagar@bora.app` só para testar a eliminação de conta.
