# TEXTOS DA LOJA — App Store Connect

> Missão `ios-lancamento` · Tarefa 3 · 2026-09-07.
> Fonte das referências fixas: memória `carta-de-autonomia-ios`. URLs verificadas
> ao vivo nesta sessão (`curl -o /dev/null -w "%{http_code}"`) — ver secção 6.

Copiar directamente para os campos correspondentes no App Store Connect
("Informações do App" / "Página do App"). Idioma principal: **Português
(Portugal)**.

---

## 1. Nome do app (máx. 30 caracteres)

```
Bora — entregas e serviços
```
(26 caracteres — cabe. Se `Bora — entregas e serviços na Guarda` — 38
caracteres — não couber no campo, este é o fallback já dentro do limite. Se o
nome curto estiver ocupado por outro developer, usar `Bora App Guarda`.)

## 2. Subtítulo (máx. 30 caracteres)

```
Mercado, comida e serviços
```
(26 caracteres.)

## 3. Categoria

- **Primária:** Food & Drink
- **Secundária:** Lifestyle

## 4. Palavras-chave (máx. 100 caracteres, separadas por vírgula, sem espaço depois da vírgula)

```
mercado,supermercado,comida,entrega,delivery,guarda,barbearia,limpeza,favores,lavagem,estafeta
```
(96 caracteres — dentro do limite.) Não repetir palavras já no nome/subtítulo
(a Apple ignora-as em duplicado, mas mantém-se aqui por segurança de indexação
caso o nome final mude).

## 5. Texto promocional (máx. 170 caracteres — editável sem nova revisão)

```
Mercado, comida, barbearia, açaí, limpeza, favores e lavagem — tudo na Guarda,
entregue por quem conhece a cidade.
```
(112 caracteres.)

## 6. Descrição (máx. 4000 caracteres)

```
Bora é a plataforma de entregas e serviços feita para a Guarda.

O QUE PODE PEDIR
• Mercado — faça a compra do super sem sair de casa, com entrega no próprio dia.
• Comida — peça dos restaurantes da cidade, do prato do dia ao fast-food.
• Barbearia — marque hora sem telefonar, escolha o serviço e o horário.
• Açaí e sobremesas — dos copos montados aos gelados, entregues frescos.
• Limpeza — contrate uma limpeza doméstica com data e hora à sua escolha.
• Favores — precisa de uma compra específica ou de levar algo a alguém? Descreva o que precisa e um estafeta trata disso.
• Lavagem — agende a lavagem do seu carro num dos parceiros da cidade.

PORQUÊ O BORA
• Feito de propósito para a Guarda — não é uma app nacional genérica, conhece as ruas e os horários da cidade.
• Acompanhe o pedido em tempo real, do preparo à entrega.
• Pague como preferir: cartão, MB WAY ou dinheiro à entrega.
• Avalie e seja avaliado — a confiança é dos dois lados.

Descarregue o Bora e comece por aquilo que precisar primeiro: o mercado, o
jantar de hoje ou aquele serviço que andava a adiar.

Suporte: boraappbora@gmail.com
Política de privacidade: https://boraguarda.com/privacidade
Termos e condições: https://boraguarda.com/termos
```
(≈1050 caracteres — bem dentro do limite; há margem para o Danilo ou uma
sessão futura acrescentar sem reescrever tudo.)

## 7. "O que há de novo" (release notes da v1)

```
Primeira versão do Bora para iPhone: mercado, comida, barbearia, sobremesas,
limpeza, favores e lavagem, tudo numa app só, feita para a Guarda.
```

## 8. URLs

| Campo | Valor | Prova (HTTP, 2026-09-07) |
|---|---|---|
| Marketing URL | `https://boraguarda.com` | `200` |
| Support URL | `https://boraguarda.com/faq` (decidido em `ios/NOTAS-AO-REVISOR.md`) | `200` |
| Privacy Policy URL | `https://boraguarda.com/privacidade` | `200` (o `.html` antigo dá `308` — usar sempre sem extensão) |
| Termos (dentro da app / rodapé do site) | `https://boraguarda.com/termos` | `200` |
| Email de contacto / suporte | `boraappbora@gmail.com` | — |

## 9. Copyright

```
© 2026 Danilo Fulfaro da Silva
```

## 10. Classificação etária

Sem conteúdo adulto, sem jogo a dinheiro, sem álcool como tema central da app
(é só mais uma categoria de mercado, como no Glovo/Uber Eats). Preencher o
questionário da Apple como **4+** salvo indicação em contrário do próprio
formulário (ex.: "Compras dentro da app" fica marcado como Sim, porque há
pagamento de encomendas).

## 11. Screenshots — ordem obrigatória (ver capítulo §1-b do estado)

`01-mercado`, `02-comida`, `03-barbearia`, `04-acai`, `05-limpeza`,
`06-favores`, `07-lavagem`. **Nunca** incluir carro nem boleias/TVDE em
nenhuma captura nem em nenhum destes textos — não é vendido nesta versão.

## 12. Contas de demonstração para o revisor

Ver `ios/NOTAS-AO-REVISOR.md` — duas contas demo já preparadas
(`demo@bora.app` para navegar, `demo.apagar@bora.app` só para testar a
eliminação de conta).
