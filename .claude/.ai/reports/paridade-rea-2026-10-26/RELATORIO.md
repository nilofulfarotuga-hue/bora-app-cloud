# Relatório — missão paridade-rea-2026-10-26 (26/10/2026, 05:26–07:40)

**Acessos e o que se criou nesta missão**
- O Danilo não precisou de entrar em nenhuma conta, e não se usou nenhuma conta dele nem da Bora
  nos sites dos outros.
- **Criado no PC:**
  - O REA (`rea-agents` 6.8.0) ficou registado para o Claude Code em `C:\Users\danil\.claude.json`.
    Há uma cópia de segurança em `.claude.json.rea.backup`. A skill `reverse-engineer-anything`
    foi instalada.
  - Instalei um Node 24.22.1 portátil em `C:\Users\danil\.rea-node`. É o mínimo que o README do
    REA pede, e não mexe no Node do sistema.
  - A pasta temporária do Chrome, `C:\Users\danil\_rea_perfil_paridade`, ficou no PC: a tranca não
    deixou apagá-la (ver "Falta isto").
- **Prints:** `C:\Users\danil\Desktop\Bora\paridade-rea-2026-10-26\`. São 66 imagens, mais a pasta
  `rea\` com as observações passivas.

## Para o Danilo (texto para ouvir)

**Fiz isto.**

Instalei o REA no PC, a ferramenta do vídeo, só da fonte oficial. Abri um Chrome à parte, com
perfil novo e vazio, e vi a Glovo e a Uber Eats da Guarda como um cliente qualquer. Fiz tudo:
página inicial, lista, uma loja, um produto com extras, o cesto, até ao momento em que pedem conta.
Aí parei, como manda a regra.

O iFood mostrou logo a verificação de segurança da Cloudflare. Pela regra, parei nesse site. Do
iFood ficou só o que é público em notícias.

Depois vi o Bora da mesma maneira. Ao mesmo tempo, três ajudantes leram o código do cliente, do
parceiro e do painel, e comparei tudo.

**O que se viu:**
- O Bora já tem coisas que eles não têm: reservas de mesa, Favores, limpeza, o assistente que monta
  o carrinho a partir de uma foto da lista, e a pesquisa que encontra produtos e não só lojas.
- Também cobra muito menos ao restaurante. A Glovo cobra 30%. A Uber cobra 30% mais 3,49 € por
  semana.
- Onde o Bora está atrás é na loja e no carrinho:
  - não diz quando a loja está fechada;
  - não tem a ficha com a morada e o horário;
  - não tem "mais vendidos";
  - não tem filtros na lista;
  - não mostra a morada antes de pagar;
  - quem vem de uma ligação partilhada não consegue acabar o pedido.

**O plano tem 15 melhorias.** As primeiras onze ajudam o cliente a comprar, sem mexer em dinheiro.
Três são para a loja e o painel. A última junta o que mexe em dinheiro (cupão, assinatura mensal,
promoções, agendar entregas), e isso fica à espera do teu "autorizo".

**Falta isto.**
- Não implementei nada. Pela tua regra, o plano é revisto primeiro pela Claude.ai.
- O perfil temporário do Chrome ficou no PC, porque a tranca não deixou apagar a pasta.

**Erros que encontrei pelo caminho** (estão na secção própria, mais abaixo):
- A entrada como convidado continua partida, como em setembro.
- A loja fechada parece aberta.
- O interruptor das gorjetas no painel não grava.
- Os preços aparecem como "€9.65", e não como "9,65 €".
- Alguns extras do Burger King dizem "SIN" em vez de "SEM".

**Próximo passo.** A Claude.ai revê o plano no Córtex, na página `paridade-rea-2026-10-26-plano`.

---

## Bloco 5 — Comparação por etapa

Legenda:
- **igual** — o Bora tem o mesmo;
- **pior** — o Bora tem, mas mais fraco;
- **melhor** — o Bora tem mais;
- **não tem** — o Bora não tem;
- **?** — não visto (no iFood, o site foi bloqueado).

| Etapa | Glovo | Uber Eats | iFood (só notícias) | Bora |
|---|---|---|---|---|
| Ver sem conta | sim, tudo até ao checkout | sim, tudo até ao checkout | ? | **pior**: "Sou Cliente" pede login logo; só a ligação da loja abre sem conta |
| Morada | sugestões + tipo de local + pino | sugestões | ? | igual (automática pelo GPS e moradas guardadas); sem tipo de local nem pino |
| Pesquisa | só lojas, separadores por vertical | só lojas | ? | **melhor**: lojas + produtos agrupados (`cliente_pesquisar`) |
| Faixas e categorias | categorias + populares da cidade | verticais + faixas por tema | ? | igual (14 ladrilhos + faixas no painel + Pede outra vez / Mais pedidos / Novidades) |
| Cartões de loja | tempo/estado, % gostos, promoção, NOVO | estrelas, favorito, estado | ? | **pior** na página inicial (só foto, nome e cozinha); igual na lista de restaurantes |
| Filtros e ordenação | Promoções, Tipo; Ordenar 4 | 6 chips; Ordenar 3 | ? | **não tem** nos restaurantes; mercados só Nome/Avaliação |
| Loja fechada | janela "lojas abertas parecidas / agendar" | janela "Agendar entrega" 7 dias | ? | **pior**: mostra "5-20 min" como se estivesse aberta |
| Topo da loja | promo, gostos, taxa riscada GRÁTIS, agendar | estrelas, €, Entrega/Recolha, taxa | ? | igual (capa, estrelas, tempo, taxa, favorito, reservar mesa) |
| Dados da loja | morada + horário por dia | horário + morada | ? | **não tem** |
| Destaques no menu | Promoções / Mais vendidos / Novidades | Os mais apreciados + % por artigo | ? | **não tem** (os dados existem e não se mostram) |
| Pesquisa na loja | (não visto) | lupa | ? | igual (`search_products`) |
| Produto | obrigatório, quantidade, preço | obrigatório/"até N", populares, calorias, alergénios | ? | igual (obrigatório/opcional mín/máx, alergénios, variantes) |
| Nota | — | nota do pedido no carrinho | ? | igual, mas só no ecrã de pagamento |
| Carrinho | painel lateral, Editar linha, −/+/caixote | página do carrinho, −/+ | ? | igual em −/+/caixote; **não tem** Editar linha nem "leve também" |
| Trocar de loja | um carrinho por loja (sem aviso) | (não testado) | ? | **pior**: aviso e apaga; compara a loja pelo nome |
| Taxas | "Informações sobre as taxas" | "Outras taxas (i)" | taxa de serviço | **melhor** em clareza (linha a linha + "faltam X €") |
| Gorjeta | (dentro da conta) | (dentro da conta) | ? | **melhor**: no carrinho, 100% para o estafeta |
| Finalizar | pede conta (tel/SMS/WhatsApp, Google, FB, email) | pede conta (tel/email, Google, Apple, QR) | ? | **pior**: sem conta, o botão não faz nada; a morada não aparece no checkout |
| Pagamento | (atrás do login) | (atrás do login) | ? | Cartão, MB Way, Dinheiro, Tokens, carteira (**melhor** para PT) |
| Cupão | no perfil (FAQ) | (atrás do login) | Clube | **pior**: só vira tokens no Perfil |
| Agendar | sim | sim, 7 dias | ? | **pior**: só Festas |
| Recolha | sim (15% ao parceiro) | sim, botão no topo | sim (retirar) | **pior** a mostrar: existe mas está escondida (0 pedidos) |
| Assinatura | Prime 4,99 €/mês | Uber One 4,99 €/mês ou 49,99 €/ano | Clube iFood | **não tem** (só planos TVDE) |
| Depois do pedido | (atrás do login) | (atrás do login) | — | **melhor**: estafeta ao vivo, partilhar o seguimento, PIN, chat, reportar com foto |
| Parceiro | 30% / 15%; promoções e anúncios pagos | 30%/20%/15% + 3,49 €/sem; tablet e impressora | ~12%/23% (terceiros) | **melhor** em custo e em pausa/esgotado/fecho semanal; **não tem** modo ocupado, mudar hora de pronto, responder a avaliações, impressão |
| Admin | — | — | — | 150 ecrãs; **faltam** favoritos, alergénios, editar cupões, interruptores gerais |
| Reservas de mesa | não | não | sim (jun/2026, só SP) | **melhor**: com pré-pagamento e lista de espera |

## Faltas das listas de 13/10 e 17/10 confirmadas NO CÓDIGO (o passo que nunca tinha corrido)

**Já feito (pode sair da lista):**
- pesquisa única;
- estafeta ao vivo no mapa;
- check-in diário;
- Receita do Dia;
- assistente que monta o carrinho a partir de uma foto da lista (`client-assistant`);
- favoritos;
- recolha;
- alergénios no detalhe do produto;
- "Pedir de novo" (enche o carrinho);
- pausar loja e esgotado só hoje (parceiro).

**Parcial:**
- foto de prova de entrega (o cliente não a vê);
- sugestões para chegar ao mínimo (só texto);
- recompensa por voltar (só check-in e tokens);
- substituições (texto, fotos do estafeta);
- editar o pedido (só a loja propõe; o interruptor nasce desligado);
- Livro de Reclamações (escondido em Perfil);
- agendamento (só Festas e TVDE).

**Não tem:**
- pedido em grupo;
- dividir a conta;
- assinatura de entregas;
- cartão-presente;
- carimbos por loja;
- compra pelo WhatsApp;
- preço mais baixo dos 30 dias nas promoções;
- modo ocupado;
- mudar a hora de pronto;
- impressão automática;
- responder a avaliações;
- descrições feitas por IA.

O detalhe, com ficheiro e linha, está em `bora.md`.

## O que o Bora tem A MAIS (não estragar; serve para a propaganda)

Está na secção 6 do `bora.md`. Os pontos mais fortes:
- reservas de mesa com pré-pagamento;
- Favores, limpeza e lavagem;
- o assistente de carrinho por foto (41 propostas no banco);
- a pesquisa de produtos;
- a gorjeta 100% para o estafeta;
- partilhar o seguimento;
- comissão muito abaixo da Glovo e da Uber.

## Erros encontrados pelo caminho (REPORTADOS, não corrigidos — e2e_log passo 04-bora-erros)

1. **A entrada como convidado continua partida, desde 08/09.**
   - A consola da app no ar mostra "guest sign-in failed 400" e "guest session FAILED 422".
   - Por isso:
     - "Finalizar pedido" sem conta fica mudo;
     - as taxas lidas do servidor ficam em valores de recurso;
     - `client_checkin_premios` dá permission denied (42501).
2. **A loja fechada parece aberta.** O Burger King (horário 11:00–23:00 no banco) às 06:55 mostra
   "5-20 min ETA" e não diz "fechado".
3. **O ecrã do produto em computador (1440 px):** a foto ocupa o ecrã inteiro e esconde as opções
   e o botão.
4. **Formato dos preços:** aparece "€9.65" e "+€2.15". Em PT-PT devia ser "9,65 €". Também aparece
   "ETA" em inglês na loja.
5. **Catálogo do Burger King:** os extras dizem "SIN Molho barbecue", "SIN Bacon"… "Sin" é
   espanhol; devia ser "SEM".
6. **O interruptor das gorjetas no painel não grava.**
   - `admin_gorjetas_screen.dart:63-67` faz um UPDATE direto em `platform_settings`, mas essa
     tabela só aceita leitura (`pg_policies`).
   - Resultado: muda 0 linhas, o ecrã diz que mudou e não fica auditoria.
   - O valor real hoje é `tips_enabled = true` (desde 04/10).
7. **`home_banners` existe no banco e não tem migração no repo:** o banco está à frente do repo.
8. **`create_order` (zona protegida, só relato):**
   - procura a loja pelo NOME (`WHERE name = v_vendor_name`; hoje não há nomes repetidos, por
     isso o risco é latente);
   - não verifica `is_available`;
   - aceita o preço da app quando o `product_id` não existe;
   - nos pedidos em dinheiro, não há chave contra o toque duplo no servidor (só a app trava).
   - Mín/máx dos extras: só a app verifica.
9. **Parceiro:**
   - os extras são apagados e reinseridos sem transação, e um grupo obrigatório pode ficar vazio;
   - `/partner/ratings` não tem caminho, nem pela notificação;
   - "esgotado só hoje" pode ser desfeito pelo cron depois de uma edição;
   - recusar o pedido é um toque só, sem confirmação;
   - `prep_time_minutes` é regravado quando a aceitação é repetida.
10. **Textos sem tradução:** `cart_screen.dart:569` e `:647`, `product_detail_screen.dart:520`.
11. **A confirmar (dinheiro):** no carrinho do visitante, a loja não-parceira mostra "Taxa de
    serviço 0,48 €" (5%). A secção 2.2 do `business_rules.md` diz que os não-parceiros não têm
    percentagem. Pode ser só o valor de recurso sem sessão (erro 1). A Claude.ai ou o Danilo devem
    ver.
12. **Painel admin:**
    - 4 entradas arquivadas abrem o mesmo ecrã de acertos;
    - faltam ecrãs de favoritos e de alergénios;
    - os cupões só se criam e desativam.

## Bloqueios desta missão

- **iFood:** Cloudflare na primeira página (Ray ID a5075bf3efe10fee). Parei pela regra 3 e não o
  contornei.
- **Apagar `C:\Users\danil\_rea_perfil_paridade`:** a bora-tranca recusou ("apagar recursivo fora
  de build/…"). Não contornei. A pasta fica no PC (sem conta nenhuma).
- **REA:**
  - O `observe-web-session` só regista navegação; os cliques na mesma página não aparecem.
  - Para o cesto, a prova é o print e o texto lido pelo Playwright.
  - Os comandos de leitura de código de terceiros (analyze-web-bundle e afins) **não** foram usados.

## Regras cumpridas

- Sem login, sem conta, sem pedido, sem pagamento e sem cupão nos sites dos outros.
- Cookies: "Rejeitar".
- Moradas: só praças e moradas públicas.
- No máximo 1 restaurante e 1 mercado por app, com pausas de 1,5 a 4 s entre cliques.
- Nenhum código, cookie ou token dos outros guardado. O REA redige os valores sozinho
  (`values_redacted: true`).
- Nenhum dado pessoal nos relatórios.
- As 3 decisões de 25/10 que estão nesta sessão não foram tocadas.
- O código do app não foi mexido. Nada foi publicado.
