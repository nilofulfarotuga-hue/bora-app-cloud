# Limpeza semanal — só chama a limpadora depois de pago (19/10/2026)

Missão `limpeza-semanal-pagamento-19-10` · motor Opus · sessão no PC · ramo `autonomous-night-2026-04-29`.
Autorização do Danilo (19/10/2026): "autorizo arrumar as limpezas semanais" + "Pode" + "o divã
tem que fazer o pagamento do MBA…". Nenhum preço nem comissão foi mudado.
Provas literais: `.claude/.ai/provas/limpeza-semanal-pagamento-19-10/PROVAS.md`.

## Fiz isto

- **A limpadora só é chamada depois de pago.** Com MB Way ou cartão por pagar, o sistema já não
  chama ninguém. Quando o pagamento entra, chama sozinho (a Mayra primeiro, porque é a pedida).
  Em dinheiro chama logo, como antes. Provado numa transação desfeita: por pagar → ninguém;
  pago → oferta à Mayra; dinheiro → oferta logo.
- **A série semanal segue o dia e a hora que o cliente marcou**, em hora de Lisboa. Um
  reagendamento pontual já não passa para as semanas seguintes e a mudança da hora (25/10) já não
  muda a hora. Para o Divan: a seguir a sábado 24/10 vem sábado 31/10 às 13:30.
- **Pedido de MB Way automático.** Quando nasce a limpeza da semana seguinte, o pedido de MB Way
  vai sozinho para o telemóvel do cliente. Se ele não pagar, o sistema volta a pedir de 12 em
  12 horas (até 4 vezes) e, a menos de 24 horas, avisa o admin uma vez.
- **Reservas do Divan arrumadas.** A de segunda 26/10 às 08:45 (que estava errada e aceite pela
  Mayra) voltou a **sábado 24/10 às 13:30**, sem limpadora até ele pagar, com a Mayra como
  preferida. Avisei a Mayra e o Divan na app. Enviei os pedidos MB Way de 32,40 € da limpeza de
  hoje e da de sábado.
- **Painel admin:** cada limpeza mostra "Pagamento: pago / pedido enviado (n vezes, hora) / por
  pagar" e tem o botão **"Pedir pagamento MB Way"**.
- **App do cliente:** o botão que já existia ("Pagar agora") passa a dizer **"Pagar com MB Way"**
  quando a limpeza é MB Way.
- Um revisor separado tentou derrubar o trabalho. Corrigi o que ele apanhou e que era meu: já não
  se mandam dois pedidos MB Way ao mesmo tempo pelo sistema, e o telefone nunca vai para os
  registos.
- Guardei tudo no repositório e enviei para produção (commit `0d2e5960`): Android, web e iPhone
  estão a ser construídos pelo CI (estado no fim deste ficheiro).

## Falta isto (e porquê)

- **O Divan não aprovou os dois pedidos MB Way de hoje.** A Stripe diz "o cliente não aprovou"
  nos dois, cerca de 5 minutos depois — ou recusou, ou deixou passar o tempo (a Stripe dá o mesmo
  código aos dois casos). As duas limpezas continuam por pagar.
  - A de **sábado 24/10**: o sistema volta a pedir sozinho (próximo pedido ~12 h depois do
    primeiro) e avisa o admin a menos de 24 h.
  - A de **hoje** (já a decorrer) não é pedida outra vez sozinha. Ou carregas no botão "Pedir
    pagamento MB Way" no painel, ou o Divan carrega em "Pagar com MB Way" na app.
- **Uma segunda correção à base de dados ficou por aplicar**, porque a nossa tranca a bloqueou
  (viu a palavra "Stripe" nos comentários). Não a contornei. O que ela trazia:
  1. avisar o admin se a chamada da limpadora falhar depois de pago;
  2. séries de teste nunca mandarem MB Way a sério;
  3. séries pagas com **cartão** avisarem o cliente e o admin (hoje não há nenhuma, mas uma série
     com cartão ficaria parada: não há cobrança automática do cartão);
  4. não mandar pedidos MB Way de noite (só das 9h às 21h). Sem isto, o 2.º pedido do Divan
     pode sair perto das 22h de hoje.
  Proposta para a tranca: ignorar os comentários das migrações antes de procurar palavras.

## Erros que encontrei pelo caminho (reportados, não corrigidos)

1. **O stripe-webhook não lê a resposta `ok` de `confirm_cleaning_payment_webhook`.** Se o valor
   pago não bater certo, a recusa fica calada (só aparece no registo). Confirmado no código.
2. **`create_cleaning_booking` chama a oferta antes de o pagamento entrar** — confirmado. Com a
   trava nova isso já não chama ninguém (provado).
3. **O botão do cliente pode criar um segundo pedido MB Way** enquanto o automático ainda está à
   espera. Se ele aprovar os dois, o segundo fica cobrado sem estorno. Está na função de
   pagamento da limpeza (lista vermelha), por isso só reporto.
4. **Pagamento aprovado depois de cancelar** fica marcado como pago numa limpeza cancelada e
   ninguém estorna (a janela é de ~5 minutos).
5. **Reagendar a 1.ª limpeza de uma série arrasta as seguintes**, porque a série conta a partir da
   1.ª reserva, como a ordem pediu. Para corrigir é preciso guardar a data original da série.
6. **A migração `20261010073000_limpeza_duas_voltas_de_ofertas.sql` está no repositório mas nunca
   foi aplicada.** Se alguém a aplicar, apaga a trava do pagamento e a regra "papel desligado não
   recebe ofertas". Tem de ser refeita antes.
7. **Limpeza MB Way por pagar e sem limpadora é cancelada com a mensagem "Não conseguimos
   encontrar uma profissional"** 15 minutos depois da hora. A mensagem certa seria "não foi paga".
8. Se o cliente pagar depois de a limpeza estar concluída, ela fica "paga, por libertar" e nunca
   passa a "libertada".
9. A série morre se uma data passar sem ser gerada, e pára se o cliente cancelar a última — já
   vinha de antes.

## Próximo passo

- Decidir se a 2.ª correção à base de dados pode ser aplicada (ou corrigir a regra da tranca).
- Falar com o Divan sobre o MB Way, ou carregar no botão do painel para a limpeza de hoje.

## PARA O DANILO

- Posso aplicar a 2.ª correção (lista acima)? A tranca só deixa com a tua ordem.
- Os erros 1, 3 e 4 mexem no circuito do pagamento: só com o teu "autorizo".

## Outras notas

- RAM: 2326 MB livres no início, 3727 MB antes do `flutter analyze` — acima dos portões.
- O Córtex (MCP) pedia nova autorização nesta sessão: não registei lá; ficou no e2e_log
  (fluxo `limpeza-semanal-pagamento-19-10`) e no `claude_ai_memoria` (digest).
- Ficou no ar uma função só de leitura, `diag-pagamento-limpeza`, que diz porque é que um pedido
  falhou (só o servidor a pode chamar).

## CI — as 3 publicações (commit `0d2e5960`)

| Plataforma | Resultado | Prova |
|---|---|---|
| Web | ✅ success (11:22 UTC) | `main.dart.js` no ar (HTTP 200, 11,6 MB): "Pedir pagamento MB Way" ×1, "Pagar com MB Way" ×2, "Pay with MB Way" ×1, `cleaning_request_payment` ×1 |
| Android | ✅ success (12:01 UTC) | commit `39bb2d33 ci: bump versionCode to 677`; `platform_settings.app_latest_version_code = 677` (último passo, depois do envio ao Play) |
| iPhone | ✅ success (12:43 UTC) | job A (simulador) e job B (IPA assinado → App Store Connect, versão seguinte com lançamento automático + submeter) verdes. Fica no ar quando a Apple aprovar. |
| Golden | ✅ success | `olho-golden` |

