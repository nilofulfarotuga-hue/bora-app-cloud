# Missão única 03/10 — sessão 04/10 (Opus, PC do Danilo)

Arranque 08h45 · RAM 468 MB (portão leve ok). Worktree próprio `C:/BoraLocal/wt-missao-04-10`,
ramo local `missao-04-10`. Escritas na base: o conector Supabase do PC prende nas escritas
(regra da Claude.ai 08h55) e o token do CLI expirou (401) → **todo o SQL ficou em ficheiro
para a Claude.ai aplicar**. Leituras e provas por SELECT pelo conector.

## Uma linha por bloco

| Bloco | Ficou feito | Prova | Falta / causa |
|---|---|---|---|
| 1 Storage fotos lojas | Aplicado pela Claude.ai; o meu ficheiro `20261004090000_restaurant_assets_dono_ou_admin.sql` ficou igual ao que está no ar | pg_policies lido: `restaurant_assets_owner_insert/update/delete` + `can_write_restaurant_asset` | Nada. Nota: só olha `restaurants.user_id` (0 lojas só com `user_`) |
| 2 Duplicados | Trava própria nos botões: Enviar pacote, Levar compras, carrinho "Finalizar pedido", lavagem "Pagar X €", planos TVDE "Aderir" (tirado o `store.busy`); guarda de entrada na lavagem (pedido), dívida da carteira, "Marcar para depois". Servidor: gatilho do Favor alargado a `sendPackage`/`carryGroceries` | Suite 885/885; teste-guarda dos botões 0 falhas | Aplicar `20261004093000_pedido_duplicado_pacote_e_compras.sql` + prova `supabase/provas/20261004_b2_prova_duplicado.sql` |
| 3 Gorjeta | **Causa achada:** no checkout a gorjeta nunca saía do telemóvel (a `create_order` não a recebe); no ecrã de avaliação só se escrevia um número no pedido, sem cobrar, e escondida a quem pagou em dinheiro (só 2 avaliações de estafeta em pedidos não-dinheiro em toda a história). Feito: tabela `tips`, Edge Function `charge-tip` (PaymentIntent próprio `kind=tip`, cartão do pedido/guardado ou folha Stripe, MB Way pedido novo, reembolso só admin), dinheiro só no checkout (soma ao que paga em mão, respeita os 40 €), fecho semanal soma as gorjetas online (patch por âncora com cópia), TVDE: gorjeta no ecrã de avaliação como a Uber, linha "Gorjeta" nos ganhos, admin "Gorjetas" (ver, exportar, reembolsar, ligar/desligar) | Código + prova escrita | ⚠️ DINHEIRO. Aplicar `20261004100000_gorjetas.sql`, deploy `charge-tip` (verify_jwt=true), prova `20261004_b3_prova_gorjeta.sql`. Interruptor `tips_enabled` nasce **false**: enquanto não se ligar, ninguém vê gorjeta. Sem chaves de teste da Stripe neste PC → **ninguém foi cobrado**. Taxa Stripe fica gravada por gorjeta (`stripe_fee_cents`) e aparece no admin |
| 4 Fotos Pôr do Sol | 56 fotos da Glovo copiadas para o nosso Storage (`restaurant-assets/pordosol-guarda/`), capa e logo também; cópia de segurança dos links antigos | SELECT: 97 produtos, 56 com foto, 56 no Storage, 0 ainda na Glovo; link novo responde 200 image/jpeg | 38 sem foto (16 pizzas × 2 tamanhos, falafel, pita, extra carne, asas): a Uber Eats tem estas pizzas **sem foto** (só 14 artigos com foto, nenhum destes) e as fotos do Facebook não dizem que pizza é qual → não se inventou. Logo real não encontrado (o "logo" é foto de produto). Preços intocados |
| 6 Lojas por telefone | Marca por loja (`order_by_phone`, número, minutos de espera, minutos de preparo) ligada nas 6 lojas; **porteiro** que segura o pedido em "em preparação" até à hora (não toca no motor de despacho nem no webhook); alerta Telegram + push com o resumo a preço de BALCÃO; avisos aos 3 e 6 min; botão "Encomendado à loja" (quem e quando); estafeta chamado 15 min depois (ou desde a hora do pedido se ninguém carregar); estafeta vê "Pagar ao balcão: X €"; cliente vê "A loja está a preparar o teu pedido — pronto por volta das HH:MM"; admin "Encomendas por telefone" | Código + prova escrita (b6-1…b6-5, tempo acelerado) | Aplicar `20261004110000_lojas_encomenda_por_telefone.sql` + prova `20261004_b6_prova_telefone.sql` |
| 5 Secretário Virtual | Caçador Portugal inteiro (OSM, só quem tem WhatsApp no site e email público com MX; fora serviços públicos); negócio de demonstração **escondido** + tenant `secretario-demo` no número da Bora em modo teste; código "TESTE 1234" põe o número na demo por 7 dias e tira sozinho; boas-vindas; email (96 palavras, sem preço, assinado Bora App — Guarda); página `boraguarda.com/secretario` (noindex); admin "Secretário Virtual" | Caçador em seco: 8 negócios em 6 min; email passa o validador do carteiro sem erros; sintaxe Python/JS ok | Aplicar `20261004120000_secretario_virtual.sql`; instalar na VPS `ferramentas/assistente-negocio` (instalar.sh) + `ligar.js` + `carteiro_caca.py`; publicar `secretario.html` (bora-site, commit 0aab051 no ramo `motorista-ficha-legal-2026-09-23`); correr o caçador sem `--seco`; ligar o envio no admin. **Fila partilhada** com o caça-clientes: o tecto de 5 novos/dia é o total (mais seguro para a conta Gmail) |

## Código

- Commits no ramo local `missao-04-10`: `168246ea` (blocos 1-4, 6) e `b788bd82` (bloco 5), já
  rebaseados sobre `origin/autonomous-night-2026-04-29` (versionCode 643).
- **O `git push` foi recusado pelo classificador de segurança do Claude Code.** Não se tentou
  outro caminho. Para enviar (fora de hh:05–09):
  `cd C:/BoraLocal/wt-missao-04-10 && git push origin HEAD:autonomous-night-2026-04-29`
- Verificação: `dart analyze` nos ficheiros mexidos 0 erros/0 avisos; suite completa 885/885
  verde; teste-guarda dos botões 0 falhas; dicionário EN completo; anti-trapaça do Juiz CLEAN.
- RAM no analyze/suite: 358–695 MB (abaixo dos 800). Avançou-se porque o consumidor era um
  modelo do Ollama (4,3 GB, arrancado 06:34, não desta sessão) e o PC tem 14 GB com paginação.

## Achados para reportar (não corrigidos)

1. A função `upload-restaurant-asset` (Edge, service_role) aceita envio para a pasta de
   **qualquer** loja sem verificar quem é (não substitui ficheiros: nome com hora). Mesmo tipo de
   buraco do bloco 1, noutro caminho.
2. `map_screen.dart` "Confirmar pedido" e `reservation_flow_screen.dart` não têm trava, mas
   nenhum ecrã os abre (código morto).
3. `business_rules`/CONTEXT diz gorjeta 80% estafeta / 20% Bora; a regra de 03/10 do Danilo é
   100% para o prestador — foi o que se fez. Falta atualizar o BR §4.5.
4. Gorjeta em dinheiro: o estafeta não vê no cartão que o cliente vai dar gorjeta (o cliente
   entrega-a em mão; fica registada e nos ganhos dele).

## PARA O DANILO

- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (gorjeta). Está tudo pronto e desligado — confirma que eu
  (ou a Claude.ai) ligo `tips_enabled` depois da prova.
- Fotos das 16 pizzas da Pôr do Sol: só a loja as tem. Pedir-lhes 10 minutos de fotos, ou
  autorizar fotos genéricas marcadas como "imagem ilustrativa".
