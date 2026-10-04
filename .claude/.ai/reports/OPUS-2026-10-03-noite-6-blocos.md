# Missão 03/10 à noite — 6 blocos (relatório para ouvir)

Sessão: Claude Code no PC, ramo `autonomous-night-2026-04-29`. Motor: Opus 5.5.
Código enviado: commit `c325d7c5` (23 ficheiros, só desta missão) + junção `b2521671`, empurrado às 19:45.
RAM medida no arranque: 578 MB disponíveis; na hora de compilar: 1574 MB (PC novo, 14 GB).
Córtex: o conector está sem autorização nesta sessão — `cortex_buscar`, `cortex_reportar` e
`cortex_nova_ordem` não estavam disponíveis. A continuação foi para ficheiro (ver fim).

## Bloco 1 — Mister Navalha: FEITO (já estava no ar; provado de novo)
- O site no ar é só a frase "Mister Navalha — brevemente", sem imagem nem og:image. As 11 fotos
  (`corte-1..6`, `ernando`, `certificado`, `fundo`, `logo`, `og`) dão **404** no domínio e no
  pages.dev. As publicações antigas (`b860fe12`, `c5056866`) dão 404 à página inteira. No Cloudflare
  só existe 1 publicação (a "brevemente", de hoje às 16:18 UTC). A cache responde `DYNAMIC`: nada guardado.
  A purga deu 401 (os tokens não têm essa permissão), mas não era precisa.
- O que o Danilo viu às 19h era quase de certeza cache do telemóvel.
- App: galeria vazia (`gallery_urls = []`, capa nula); no Storage não há fotos de cortes.
  Pasta local e git intactos.
- Admin: já via, acrescentava, reordenava e removia fotos da galeria. "Remover" só tirava o link;
  o ficheiro ficava público. Agora há **Esconder** (sai da galeria) e **Apagar de vez** (sai e apaga o
  ficheiro). Ficheiro: `lib/screens/admin/admin_service_provider_detail_screen.dart`.

## Bloco 2 — TVDE recusar: FEITO
- Causa provada nos eventos da corrida `540b738a`: recusa às 13:26:05, mais 5 toques até :11, e a
  MESMA corrida voltou ao MESMO motorista às 13:26:48. O varrimento `tvde_dispatch_sweep` apaga
  `tried_driver_ids` ao fim de 35 s sem ninguém.
- Servidor: chave `tvde_reject_cooldown_seconds = 600` (categoria dispatch). `tvde_offer_to_next`
  passa a excluir quem recusou a corrida nesse tempo. Remendo por âncora, com backup em
  `bkp_fn_tvde_despacho_20261003`; provado que, tirando o bloco novo, a função é igual ao backup.
- App: o cartão e o ecrã da oferta fecham logo ao confirmar a recusa (estado próprio, recusa em
  fundo). Uma leitura atrasada do servidor não traz de volta uma oferta recusada.
  Ficheiros: `tvde_offer_overlay_host.dart`, `tvde_offer_screen.dart`, `tvde_driver_store.dart`.
- "A caminho" da reserva concluída (`b4d4b703`: `finalizada` com `reservation_status = ativada`): o
  estado final da corrida manda sobre o da reserva. Ao abrir a app, os avisos TVDE de corridas
  terminadas saem da barra. Tocar num aviso velho já não confirma nada.
- Admin: as 3 chaves novas estão editáveis, com explicação em PT-BR.

## Bloco 3 — Favores: FEITO
- Foto: a causa real do 404 não era só o link. A política de leitura do bucket só deixava o
  estafeta ler quando a pasta tinha o id do pedido, e a foto é enviada antes de o pedido existir.
  Política nova só para fotos de Favor. **Provado: o estafeta do pedido vê (1), um estranho não vê (0).**
  O bucket continua PRIVADO.
- Um gatilho grava sempre o CAMINHO (`order-photos/...`). As 2 linhas de hoje foram convertidas, com
  backup em `bkp_orders_errand_photo_20261003`. Restam 0 links públicos.
- O cliente vê a foto em "Os meus pedidos" e o admin no detalhe do pedido, ambos com link assinado.
- Duplicado: o formulário tem trava própria e sai para "Os meus pedidos" depois de pagar. O servidor
  recusa um Favor igual (cliente, morada e `price`) em `errand_duplicate_window_seconds = 60`.
  **Provado: o igual foi recusado e um com outra morada passou** (prova desfeita no fim, 0 lixo).
- 3c, a varredura dos outros ecrãs:
  - entrega/mercado: OK;
  - TVDE: OK;
  - limpeza: OK;
  - envio de pacote (`send_package_form_screen.dart`) e levar compras (`carry_groceries_form_screen.dart`):
    não esperam pelo resultado do pagamento, por isso provavelmente têm o mesmo defeito do Favor. Não corrigido (fora do âmbito);
  - reserva de mesa (`reservation_checkout_screen.dart`) e marcação de serviço (`booking_flow_screen.dart`):
    a trava só liga depois de a folha de pagamento abrir. Risco baixo.

## Bloco 4 — Limpeza: código FEITO, prova no emulador NÃO feita
- A Mayra tem 3 papéis: estafeta aprovada (mota), limpeza aprovada e cliente. O ecrã da limpeza
  abria por cima sem botões de saída, e no modo cliente a troca de perfil não conhecia a limpeza.
- Agora há um botão **"Mudar de modo"** sempre visível no ecrã da limpeza e no Perfil do cliente.
  Lista cliente, estafeta, parceiro, limpeza e lavagem. A limpeza abre por cima do modo base, por isso
  ao reabrir a app ela nunca fica trancada. Ficheiros: `profile_switcher_button.dart`,
  `cleaner_home_screen.dart`, `portao_do_prestador.dart`, `washer_home_screen.dart`, `profile_screen.dart`.
- Admin: já via e ligava/desligava papéis. Faltava "Lavador/a", que foi acrescentado.
- Prova no emulador por fazer: precisa de uma conta de teste com limpeza + cliente em produção, e eu
  não posso criar contas fora do servidor local.

## Bloco 5 — Mapas: código FEITO, medição de frames NÃO feita
- Comparação completa feita. Causas da travagem do motorista: a seta saltava de ponto em ponto; a
  câmara animava 900 ms com pontos a cada 700 ms (cada animação cortada a meio); o ecrã inteiro era
  reconstruído; e o poll da home notificava sempre.
- Feito: a seta e a câmara deslizam a cada 16 ms, como no estafeta. Só o mapa se redesenha a cada
  passo. O toque no mapa pausa o seguimento. Mantidos: paragens na rota, rota que se apaga atrás e
  recálculo só por desvio.
- A linha dos dois mapas vem de `map_route_line_width = 12`; o estafeta tinha 6. Não havia contorno em
  nenhum.
- Não feito: notificar só quando algo muda no poll da home (risco de esconder mudanças reais) e a
  medição de frames com GPX. Esta pede uma corrida e uma entrega reais em produção, e o caminho conhecido
  é a oferta fugir para um motorista real. Fica para a continuação.
- geolocator e `location` não foram tocados.

## Bloco 6 — Gmail do robô vendedor: BLOQUEADO
- Estado real: o envio NÃO está ativo. `caca_clientes_enabled = false`, não há passo `c5-ligar`, e o
  "Permitir" nunca foi carregado (a janela de hoje expirou às 16:54). A app OAuth "Bora Carteiro"
  está em modo de teste.
- Bloqueio: a extensão do Chrome não está ligada a esta sessão, e publicar pede o formulário de branding.
  Pedi-lo ao Danilo seria tarefa técnica. Já conferi os endereços para o formulário:
  `https://boraguarda.com/` e `https://boraguarda.com/privacidade`, ambos 200.

## Testes e envio
- `flutter analyze`: 0 erros (numa cópia limpa do HEAD com só estas mudanças).
- `flutter test`: 882 verdes na cópia limpa; 885 na árvore com o trabalho da outra sessão.
- Teste-guarda dos botões: 16/16. Anti-trapaça do Juiz: CLEAN.
- versionCode: não foi tocado.
- CI: a correr no momento do envio (Web, Android, golden, iOS) — resultado na linha de fecho abaixo.

## Erros encontrados pelo caminho (não corrigidos, fora do âmbito)
1. **Segurança:** no bucket `restaurant-assets`, qualquer utilizador com sessão pode APAGAR ou SUBSTITUIR
   qualquer ficheiro (as políticas de delete/update não veem o dono). São as fotos de todas as lojas.
2. Outra sessão está a trabalhar nesta mesma pasta (pagamentos de cartão presos, chat da limpeza,
   iOS), com 28 ficheiros no index por gravar. O `admin_cleaning_bookings_screen.dart` dela tinha um
   erro de compilação (`_advance` não existe) à hora da minha análise. Nada disso viajou no meu envio.
3. A Trava leu `DROP TRIGGER IF EXISTS … ON public.orders` como "DROP de tabela financeira" (falso
   positivo). Resolvi sem a contornar: usei `CREATE OR REPLACE TRIGGER`, sem DROP.
4. Na minha primeira versão da guarda de duplicados, `total`/`customer_total` são colunas geradas e
   estão vazias num gatilho BEFORE. Corrigido antes de valer: compara `price`.
5. Avisos antigos do analyze: `BRDriver` sem uso em `driver_map_screen.dart`, `user` sem uso em
   `profile_screen.dart` e `_myRole` em `chat_bubble_button.dart`.
6. O agente `vendedor` em `agentes_estado` está desligado desde 18/09. Quem envia é o carteiro do
   caça-clientes.

## PARA O DANILO
- **A foto do Ernando** (o barbeiro) continua como foto de perfil dele na app (`ernando.jpg`). Não é
  foto de cliente, por isso ficou. Se também é para sair, diz "tira a do Ernando".
