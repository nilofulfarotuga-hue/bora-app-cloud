# Notas da versão do #19 (15/11/2026)

Escrito pelo ajudante A da missão fechar-tudo-15-11, só a ler: commits de
`origin/autonomous-night-2026-04-29..ai/2026-11-15-app` (93 commits às 15:20, cabeça
`fd17054c`) e registos do e2e_log dos fluxos fechar-app-15-11, manha-15-11, app-15-11,
painel-admin-15-11 e fechar-tudo-15-11. Língua das lojas: PT-PT.

Ficou de fora de propósito, porque está desligado ou ainda não chega ao cliente:
- Loja Online: `loja_online_ativa = false` (lido às 15:05).
- Entrar com a Apple: o botão já existe nas versões que estão nas lojas e depende de um
  interruptor do servidor. Não é novidade desta versão (ver nota no RESUMO).
- Farmácias: só funcionam em demonstração (`pharmacy_prescription_real_orders_enabled = false`).
- Painel de administração, robôs do servidor, propostas, regras de dinheiro.
- MB WAY "sem cobrar duas vezes": a proteção completa depende das funções do servidor das
  caixas 30, 31 e 32, que ainda não estão publicadas. As notas só falam do que a app faz
  sozinha: explica porque falhou e guarda o carrinho.

---

## 1. Google Play, "Novidades" (454 de 500 caracteres)

```
• Editar perfil: muda o teu número de telemóvel na app.
• MB WAY mais claro: se o pagamento não passar, dizemos-te porquê e o carrinho fica guardado.
• Amigo Bora: a nossa equipa pode responder-te na própria conversa.
• Estafetas: a compra fica guardada a cada toque, os pedidos seguintes esperam na fila e as entregas aparecem por período, com o total em grande.
• Textos em português de Portugal e várias correções para clientes, estafetas e parceiros.
```

Atenção: o CI do Android não envia este texto. O passo de envio para a Play não tem pasta
de notas. Ver a parte C da LISTA_PUBLICAR.md.

---

## 2. App Store, "O que há de novo" (842 de 4000 caracteres)

```
Nesta versão:

Para clientes
• Novo «Editar perfil»: muda o teu número de telemóvel na app.
• MB WAY mais claro: se o pagamento não passar, dizemos-te porquê e o carrinho fica guardado.
• No Amigo Bora, a nossa equipa pode responder-te na própria conversa.
• Se o estafeta ainda estiver a acabar outra entrega perto de ti, a app avisa-te.
• O botão Partilhar já funciona bem no iPhone e no iPad.

Para estafetas
• Nas compras, cada produto marcado fica guardado logo, mesmo sem rede.
• O pedido em curso já não muda a meio: os que aceitares a seguir esperam na fila.
• Entregas de hoje, da semana e do mês, com o total em grande.

Para parceiros
• Já não ficas preso no ecrã de entrada.

E ainda: textos em português de Portugal e várias correções.

Obrigado por usares a Bora. Se algo não estiver bem, fala connosco pelo apoio dentro da app.
```

### Pronto a colar em `ios/notas_de_versao.json`

O CI do iPhone (`.github/scripts/ios_publicar.py`) escreve o "O que há de novo" a partir
deste ficheiro em cada envio. Hoje o ficheiro ainda tem o texto da 1.0.43 (check-in, Amigo,
Livro de Reclamações), que está à venda desde 15/11 00:40. Se não for trocado ANTES de
juntar o #19, a 1.0.44 sai com o texto da 1.0.43. Depois de submetida, a Apple não deixa
mudar as notas sem tirar a versão da revisão.

Conteúdo inteiro para substituir o ficheiro (a chave `_leia` fica igual à de hoje):

```json
{
  "_leia": "Textos do 'O que ha de novo' da App Store, usados pelo .github/scripts/ios_publicar.py em cada envio automatico. A chave e' o codigo do idioma da ficha (hoje so existe pt-PT; se um dia se abrir a ficha em ingles, acrescenta-se 'en-US' aqui e o script apanha sozinho). 'padrao' e' a rede: 'pt' serve qualquer idioma pt-*, 'en' serve todos os outros. {versao} e' trocado pelo numero da versao. App = PT-PT (regra da casa), maximo 4000 caracteres.",

  "padrao": {
    "pt": "Nesta versão:\n\nPara clientes\n• Novo «Editar perfil»: muda o teu número de telemóvel na app.\n• MB WAY mais claro: se o pagamento não passar, dizemos-te porquê e o carrinho fica guardado.\n• No Amigo Bora, a nossa equipa pode responder-te na própria conversa.\n• Se o estafeta ainda estiver a acabar outra entrega perto de ti, a app avisa-te.\n• O botão Partilhar já funciona bem no iPhone e no iPad.\n\nPara estafetas\n• Nas compras, cada produto marcado fica guardado logo, mesmo sem rede.\n• O pedido em curso já não muda a meio: os que aceitares a seguir esperam na fila.\n• Entregas de hoje, da semana e do mês, com o total em grande.\n\nPara parceiros\n• Já não ficas preso no ecrã de entrada.\n\nE ainda: textos em português de Portugal e várias correções.\n\nObrigado por usares a Bora. Se algo não estiver bem, fala connosco pelo apoio dentro da app.",
    "en": "New in this version: change your phone number in Edit profile, clearer MB WAY messages, our team can reply to you in the Amigo Bora chat, and improvements for couriers and partners.\n\nThank you for using Bora. If something is not right, reach us through in-app support."
  }
}
```

Mudar este ficheiro dentro do #19 faz correr outra vez a build-ios do pedido de revisão
(o caminho `ios/**` está no filtro). Para não gastar uma volta a mais (cerca de 2 horas),
juntar esta mudança ao último envio de consertos.

---

## 3. Web (261 caracteres)

```
Atualizámos o Bora na web: já podes mudar o teu telemóvel em «Editar perfil», o MB WAY diz-te porquê quando um pagamento não passa e a nossa equipa pode responder-te na conversa com o Amigo Bora. Para pedir a eliminação da conta: app.boraguarda.com/apagar-conta
```

A web atualiza-se sozinha (o `versao.json` muda e a página recarrega). Este texto serve para
uma publicação ou mensagem, se se quiser avisar.

---

## 4. Opcional: frase do aviso de atualização dentro da app

A app mostra um aviso "há versão nova" com a frase da definição `app_update_notes_pt`.
Hoje diz "Corrigimos erros e melhorámos a rapidez do app." (desde 16/08). Proposta (88
caracteres), a mudar só quando a versão já estiver nas lojas:

```
Nova versão: editar o telemóvel no perfil, MB WAY mais claro e melhorias para estafetas.
```

---

## 5. De onde vem cada frase (para conferir)

- Editar perfil, só o telemóvel; o nome muda pelo apoio: `0a7764fa`, `3c2e702c`, ecrã
  `lib/screens/edit_profile_screen.dart` ("Para mudar o nome, fala com o suporte").
  Servidor já aplicado: `client_update_my_profile` existe.
- MB WAY explica e guarda o carrinho: `ea1e450a`, `9d3ad594`, `c9ff9945`, `37246ea7`,
  `a16e3d9c`; textos em `lib/utils/mensagem_mbway.dart` ("O teu carrinho continua aqui").
- Equipa responde no Amigo: `054e360b`, `eaf2fdd1`; servidor das conversas ao vivo
  aplicado (caixa 55, `admin_conversa_responder` existe).
- Aviso de estafeta noutro pedido perto: `lib/widgets/aviso_estafeta_noutro_pedido.dart`,
  função `cliente_fila_do_meu_pedido` existe.
- Partilhar no iPhone e iPad: `26faca7d`, `42511924` (origem da partilha nas 7 chamadas).
- Compra guardada a cada toque e fila do estafeta: `3451e519`, `e99d9007`; servidor
  aplicado (caixa 39, `estafeta_guardar_progresso_compra` e `estafeta_minha_fila` existem);
  textos "A guardar…", "Guardado", "Guardado no telemóvel · envia com rede", "Pedidos na fila".
- Entregas por período com total grande e ganho da oferta uma vez: `a37e03bc`, `2b346f76`,
  `83a65f1c`, `dbc0ce71` (Hoje, Esta semana, Semana passada, Este mês).
- Parceiro já não fica preso na entrada: `f56097bd`.
- Textos PT-PT, valores e horas de Portugal, correções: `42511924`, `367bd4a4`, `26faca7d`,
  `aed9ab8e`, `19e0444e`.
