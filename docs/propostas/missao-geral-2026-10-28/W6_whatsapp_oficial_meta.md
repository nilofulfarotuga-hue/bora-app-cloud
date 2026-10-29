# W6 — WhatsApp oficial (Meta Cloud API) para o robô das lojas

Missão final-app-2026-10-29, Bloco 2. Escrito a 29/10/2026 pelo Claude Code. **SÓ PREPARAÇÃO: nada foi submetido à Meta, nada foi
pedido, nenhuma conta foi criada.** Fontes: páginas oficiais da Meta lidas a 29/10 (links no fim). Onde a página oficial não dá o
número (preços em euros), diz-se.

## 0. Porque isto existe

Hoje o robô da Boom! Burger fala por um número da Bora ligado ao WhatsApp Web (Baileys, não oficial). Serve para o teste de
segunda/terça com o dono. Para vender o serviço a outras lojas (e para a loja manter o número e a app WhatsApp Business que já
usa) o caminho oficial é a **Cloud API da Meta**, e a forma de o lojista continuar a usar a app dele ao mesmo tempo chama-se
**coexistência**.

**Decisão antiga do Danilo (05/09/2026): "Tech Provider NÃO", porque a Meta diz que a identificação como Tech Provider não se
reverte.** Esta página NÃO a contraria: só descreve o que seria preciso. Para avançar é preciso ordem nova do Danilo, com a frase
e a data.

## 1. Como fica a arquitetura (a que já existe + a oficial)

| | Hoje (teste) | Oficial |
|---|---|---|
| Porta | Baileys na VPS, número da Bora | Webhook da Cloud API (HTTPS) na VPS ou numa Edge Function |
| Cérebro | `assistente-negocio` (Python) | o mesmo; só muda a porta (`/evento` recebe do webhook; a fila de saída chama a API de envio) |
| Número | o da Bora | o do próprio lojista (coexistência) |
| Quem escreve à mão | ninguém (o dono usa outro telemóvel) | o lojista na app WhatsApp Business; as mensagens aparecem espelhadas (`smb_message_echoes`) e o robô cala-se 12 h nessa conversa, como já faz |

O cérebro não muda: tenant com `tipo = restaurante`, allowlist, janela demo, contas do servidor, `order_origem`.

## 2. Coexistência (app WhatsApp Business do lojista + Cloud API no mesmo número)

Requisitos lidos na página oficial:
- o lojista tem a app **WhatsApp Business versão 2.24.17 ou superior**, com o número ligado;
- quem integra é **Tech Provider ou Solution Partner**, e usa o **Embedded Signup** (a Meta avisa que as versões v2 e v3 deixam
  de existir a **15/10/2026**; usar a v4 ou a v5, onde a coexistência já vem ligada);
- o webhook recebe os campos `account_update`, `history`, `smb_app_state_sync` e `smb_message_echoes`;
- sessão de registo (session logging) ligada no Embedded Signup.

O que se ganha: o lojista **mantém a app e o número**; as conversas de um-para-um ficam sincronizadas nos dois lados; com a
autorização dele chegam até **180 dias de histórico** (grupos ficam de fora).

O que se perde ou muda (avisar o lojista ANTES, por escrito):
- **Listas de difusão** ficam desligadas (as que existem passam a só de leitura);
- a Meta lista como **não suportados com a Cloud API ligada**: grupos, mensagens que desaparecem, ver-uma-vez, localização em
  direto, **chamadas de voz e vídeo**, catálogo, encomendas, estados, respostas rápidas, etiquetas, mensagens de ausência e de
  saudação, perfil comercial e Canais. Ler a lista da Meta no dia da ligação e dizer ao lojista o que deixa de ter;
- velocidade fixa de **20 mensagens por segundo** neste número;
- **24 horas** depois da ligação para sincronizar contactos e histórico (uma vez só); passado esse prazo é preciso desligar e
  ligar de novo;
- app principal parada cerca de **14 dias** (ou aparelho companheiro cerca de 30) **desliga** a coexistência: pedir ao lojista
  que abra a app WhatsApp Business pelo menos de duas em duas semanas.

## 3. Bora como Tech Provider — lista do que tem de existir

Só depois de ordem nova do Danilo. Por esta ordem (a Meta pede a verificação do negócio antes do App Review):

1. **Portefólio de negócio (Meta Business)** da empresa (nome e NIPC na base, não aqui: repo público) e uma **app Meta** com o caso de
   uso WhatsApp ligada a esse portefólio. (A app "Bora Social" que já existe foi pensada para o Instagram; avaliar se se cria uma
   app nova só para o WhatsApp, para não misturar permissões.)
2. **Verificação do negócio** na Meta (dados da empresa; documentos se a Meta não a encontrar). Em setembro o Centro de
   Segurança dizia que a organização "não precisa de ser verificada"; ao pedir Tech Provider a verificação passa a ser exigida e o
   ecrã muda. Ver na hora.
3. **Verificação de acesso** (a Meta chama-lhe "access verification"; a página que li não a descreve em detalhe — ver o ecrã na hora).
4. **App Review** com acesso avançado a:
   - `whatsapp_business_messaging` (enviar mensagens em nome dos clientes);
   - `whatsapp_business_management` (aceder às contas WhatsApp dos clientes; sem ela, as chamadas a contas que não são nossas
     devolvem o erro 200).
   Pedem dois vídeos: uma mensagem enviada pela nossa app e recebida no WhatsApp; e a criação de um modelo (template) de
   mensagem. Mais a documentação do acesso avançado, política de privacidade, ícone e categoria na app.
5. **Embedded Signup** na página da Bora (botão "Ligar o meu WhatsApp") com a opção "ligar a minha conta WhatsApp Business
   existente" visível. No fim, guardar `waba_id`, ids dos ativos e o token; **saltar** o registo do número (já existe).
6. **Webhook** público com verificação de assinatura (a chave da app, nunca no repositório) e a rotina das 24 h: chamar a SMB App
   Data API, primeiro `smb_app_state_sync` (contactos) e depois `history`, **cada uma uma só vez**.
7. **Cada lojista** tem de pôr um **cartão** na conta da plataforma WhatsApp Business dele antes de poder ser cobrado (a Meta cobra
   ao lojista, não à Bora, quando a conta de pagamento é a dele; confirmar no dia se a Bora quer revender com margem — isso já
   é negócio de preços e pede "autorizo" do Danilo).

Riscos a pôr por escrito ao Danilo antes de decidir:
- **Irreversível**: a Meta diz que depois de identificados como Tech Provider não se volta atrás e que há revisões e regras de
  dados mais apertadas.
- **Dados de clientes**: passamos a tratar mensagens e telefones de clientes de outras lojas. É preciso contrato de tratamento de
  dados (RGPD) com cada loja, e o texto "Ninguém pode saber que o Danilo é o dono" continua a valer no atendimento.
- **Modelos obrigatórios** (templates) para começar conversa fora das 24 h: cada um é aprovado pela Meta; os avisos "pedido
  aceite / pronto / saiu" são **utilitários** e enviam-se normalmente dentro das 24 h do último "olá" do cliente.

## 4. Preços em Portugal (páginas oficiais, lidas a 29/10/2026)

- Desde **1/07/2025** a Meta cobra **por mensagem** (a cobrança por conversa de 24 h acabou). Categorias de modelos:
  **marketing, utilitário, autenticação**; respostas livres dentro da janela de 24 h = **serviço**.
- Portugal **não tem tarifa própria**: está em "**Resto da Europa Ocidental**" (9 mercados, com Portugal +351).
- **1 000 mensagens de serviço por mês e por número são grátis** (não acumulam). **A partir de 1/10/2026** as de serviço acima das 1 000
  passam a ser cobradas, e os modelos **utilitários enviados dentro da janela de 24 h** (que eram grátis) também passam a ser
  cobrados. Isto pesa no robô das lojas: **os avisos do pedido são utilitários dentro da janela e passam a custar**.
- Janela gratuita de 7 dias quando o cliente chega por anúncio "Click-to-WhatsApp": mensagens de marketing, utilitárias,
  autenticação e serviço grátis dentro dela.
- **Valores em euros: a página oficial só tem links para os ficheiros (CSV "EUR list rates", CSV "volume tiers", PDF "EUR rates and
  volume tiers") e eu não os consegui abrir.** Um guia de terceiros (a confirmar!) dá para o Resto da Europa Ocidental,
  em euros por mensagem: marketing ≈ 0,049; utilitária ≈ 0,0142; autenticação ≈ 0,0142; serviço grátis dentro da janela
  (já desatualizado para a regra de 1/10/2026). **Não usar estes números em nenhum preço ao lojista sem os confirmar no CSV oficial
  EUR** (https://business.whatsapp.com/products/platform-pricing#rates).
- Estimativa para uma loja como a Boom (só como ordem de grandeza, com os valores de terceiros): um pedido gera ~4 avisos
  utilitários; 300 pedidos/mês ≈ 1 200 avisos ≈ 17 € por mês só de avisos. Se o preço certo for outro, este número muda.
- A Bora pode ainda cobrar uma taxa própria pelo robô (decisão de preço do Danilo, fora desta página).

## 5. O que o robô já traz pronto para o oficial (nada a refazer)

- Fila de saída própria e allowlist por tenant (basta trocar quem entrega: Baileys → chamada à API).
- Silêncio de 12 h quando o dono escreve à mão (na coexistência, vem pelo campo `smb_message_echoes`).
- Avisos do pedido (recebido, aceite com tempo, pronto/saiu, entregue, em falta com novo total) como mensagens curtas e
  utilitárias.
- Link da app no fim, uma vez por cliente (`?de=whatsapp-<loja>`), já medido na página /baixar.
- Texto sempre do servidor (resumo e pedido feito), contas pelo servidor, só cria depois do "sim".

## 6. Ordem de trabalho sugerida (quando o Danilo mandar)

1. Danilo decide Tech Provider (sim/não) e escreve a ordem com a data.
2. Verificação do negócio + app Meta WhatsApp (perfil Bora no navegador, com o Danilo à frente se a Meta pedir documentos).
3. Webhook de teste com o número de teste da Meta (grátis) e a Boom como primeira loja, ainda com o Baileys em paralelo.
4. App Review (2 vídeos, ~1–2 semanas de espera, a Meta decide).
5. Embedded Signup + coexistência com a app WhatsApp Business da Boom! Burger; 24 h para o histórico.
6. Desligar o Baileys só depois de uma semana de pedidos reais sem falhas.

## Fontes oficiais (lidas a 29/10/2026)

- Preços: https://developers.facebook.com/docs/whatsapp/pricing e https://business.whatsapp.com/products/platform-pricing#rates
- Coexistência: https://developers.facebook.com/docs/whatsapp/embedded-signup/custom-flows/onboarding-business-app-users
- Tech Provider: https://developers.facebook.com/docs/whatsapp/solution-providers/get-started-for-tech-providers
