/// O mapa de palavras das ENCOMENDAS no motor do Bora Motorista (TVDE).
///
/// 21/10/2026 (fechar-pendencias A1): "Encomendas = cópia exacta do Bora
/// Motorista, só com outras palavras". A chave é o texto de PASSAGEIROS que o
/// ecrã já tinha (fica byte a byte igual para quem pede corrida); o valor é
/// (português, inglês) da mesma frase numa encomenda:
/// passageiro/corrida/boleia/motorista/viagem -> encomenda/entrega/estafeta.
///
/// Regras que o teste `test/ride_kind_textos_test.dart` faz cumprir:
///  * todo o texto do código que passa por `.trK/.trArgsK/.rk/.rkArgs` e tem
///    uma palavra de passageiro está aqui;
///  * nenhum valor em português tem "corrida/motorista/viagem/passageiro/
///    boleia/condutor"; nenhum em inglês tem "ride/driver/trip/passenger";
///  * os marcadores {0}, {1}… são os mesmos da chave (o dinheiro passa intacto).
///
/// Frase nova num ecrã do TVDE com uma dessas palavras = entrada nova aqui.
const Map<String, (String, String)> kTextosEncomendas = {
  // ── Cliente: pedir ──────────────────────────────────────────────────────
  'Bora Motorista': ('Enviar encomenda', 'Send a parcel'),
  'Solicitar corrida': ('Pedir entrega', 'Request delivery'),
  'Nota para o motorista (opcional)':
      ('Nota para o estafeta (opcional)', 'Note for the courier (optional)'),
  'Corrida do plano — só pagas o excesso: {0} km acima de {1} = €{2}': (
    'Entrega do plano — só pagas o excesso: {0} km acima de {1} = €{2}',
    'Plan delivery — you only pay the extra: {0} km above {1} = €{2}'
  ),
  'Já usaste as corridas de hoje — esta fica €{0} (preço de membro).': (
    'Já usaste as entregas de hoje — esta fica €{0} (preço de membro).',
    'You have used today\'s deliveries — this one costs €{0} (member price).'
  ),
  'Incluída no teu plano — não pagas nada ao motorista.': (
    'Incluída no teu plano — não pagas nada ao estafeta.',
    'Included in your plan — you pay the courier nothing.'
  ),
  'Planos Bora Motorista': (
    'Planos mensais Bora (valem também para encomendas)',
    'Bora monthly plans (they also cover parcels)'
  ),
  'Corridas incluídas por dia a partir de €3. Vê e adere.': (
    'Entregas incluídas por dia a partir de €3. Vê e adere.',
    'Daily deliveries included from €3. Have a look and join.'
  ),
  'Tens €{0} em tokens — podes usar até €{1} nesta corrida (no máximo metade dos teus tokens).': (
    'Tens €{0} em tokens — podes usar até €{1} nesta entrega (no máximo metade dos teus tokens).',
    'You have €{0} in tokens — you can use up to €{1} on this delivery (at most half of your tokens).'
  ),
  'Ida + volta com desconto. Poupas €{0} face a duas corridas separadas.': (
    'Ida + volta com desconto. Poupas €{0} face a duas entregas separadas.',
    'There and back with a discount. You save €{0} compared with two separate deliveries.'
  ),
  'Reserva marcada. Pagas em dinheiro ao motorista.': (
    'Entrega marcada. Pagas em dinheiro ao estafeta.',
    'Delivery booked. You pay the courier in cash.'
  ),
  'Reserva marcada e paga. Já estamos à procura de motorista.': (
    'Entrega marcada e paga. Já estamos à procura de estafeta.',
    'Delivery booked and paid. We are already looking for a courier.'
  ),
  'Pacote ida e volta marcado. Pagas o pacote todo agora; se a ida for cancelada ou ficar sem motorista, devolvemos tudo.': (
    'Pacote ida e volta marcado. Pagas o pacote todo agora; se a ida for cancelada ou ficar sem estafeta, devolvemos tudo.',
    'There-and-back package booked. You pay the whole package now; if the first leg is cancelled or no courier is found, we refund everything.'
  ),
  'Ida e volta marcadas. Pagas o pacote em dinheiro ao motorista da ida.': (
    'Ida e volta marcadas. Pagas o pacote em dinheiro ao estafeta da ida.',
    'Both legs booked. You pay the package in cash to the courier of the first leg.'
  ),
  'Ida e volta marcadas e pagas. Já estamos à procura de motorista.': (
    'Ida e volta marcadas e pagas. Já estamos à procura de estafeta.',
    'Both legs booked and paid. We are already looking for a courier.'
  ),
  'Volta marcada para as {0}. Vamos procurar motorista a tempo.': (
    'Volta marcada para as {0}. Vamos procurar estafeta a tempo.',
    'Return leg booked for {0}. We will look for a courier in time.'
  ),
  'Pagamento cancelado. A corrida não foi pedida.':
      ('Pagamento cancelado. A entrega não foi pedida.', 'Payment cancelled. The delivery was not requested.'),
  'Pagamento cancelado. A corrida não foi pedida e não foste cobrado.': (
    'Pagamento cancelado. A entrega não foi pedida e não foste cobrado.',
    'Payment cancelled. The delivery was not requested and you were not charged.'
  ),
  'Pagamento não concluído. A corrida não foi pedida.': (
    'Pagamento não concluído. A entrega não foi pedida.',
    'Payment not completed. The delivery was not requested.'
  ),
  'Já tens uma corrida em curso.':
      ('Já tens uma entrega em curso.', 'You already have a delivery in progress.'),
  'Não foi possível pedir a corrida.':
      ('Não foi possível pedir a entrega.', 'The delivery could not be requested.'),
  'Não foi possível pedir a corrida. Não foste cobrado.': (
    'Não foi possível pedir a entrega. Não foste cobrado.',
    'The delivery could not be requested. You were not charged.'
  ),
  'Não foi possível garantir a volta. A corrida não foi pedida — tenta outra vez.': (
    'Não foi possível garantir a volta. A entrega não foi pedida — tenta outra vez.',
    'We could not secure the return leg. The delivery was not requested — try again.'
  ),
  'A confirmação de segurança do banco não chegou ao fim. A corrida não foi pedida e não foste cobrado.': (
    'A confirmação de segurança do banco não chegou ao fim. A entrega não foi pedida e não foste cobrado.',
    'Your bank\'s security check did not finish. The delivery was not requested and you were not charged.'
  ),
  'A corrida ainda não foi pedida e não foste cobrado. Queres tentar pagar outra vez?': (
    'A entrega ainda não foi pedida e não foste cobrado. Queres tentar pagar outra vez?',
    'The delivery has not been requested yet and you were not charged. Do you want to try paying again?'
  ),
  'Não aprovaste o pagamento a tempo na app do teu banco. A corrida não foi pedida e não foste cobrado.': (
    'Não aprovaste o pagamento a tempo na app do teu banco. A entrega não foi pedida e não foste cobrado.',
    'You did not approve the payment in your banking app in time. The delivery was not requested and you were not charged.'
  ),
  'Não recebemos a confirmação MBWay. A corrida não foi pedida e não foste cobrado.': (
    'Não recebemos a confirmação MBWay. A entrega não foi pedida e não foste cobrado.',
    'We did not receive the MB Way confirmation. The delivery was not requested and you were not charged.'
  ),
  'Ainda estamos a confirmar o pagamento. Vê o estado no ecrã da corrida — se o MB Way passou, ela segue sozinha.': (
    'Ainda estamos a confirmar o pagamento. Vê o estado no ecrã da entrega — se o MB Way passou, ela segue sozinha.',
    'We are still confirming the payment. Check the delivery screen — if MB Way went through, it carries on by itself.'
  ),
  'Não conseguimos confirmar o pagamento agora. Vê o estado no ecrã da corrida.': (
    'Não conseguimos confirmar o pagamento agora. Vê o estado no ecrã da entrega.',
    'We could not confirm the payment right now. Check the delivery screen.'
  ),
  'A confirmar o pagamento… Se foi aprovado, a corrida segue sozinha dentro de momentos.': (
    'A confirmar o pagamento… Se foi aprovado, a entrega segue sozinha dentro de momentos.',
    'Confirming the payment… If it was approved, the delivery carries on by itself in a moment.'
  ),
  'A confirmar o pagamento… Se já confirmaste no MB Way, a corrida segue sozinha dentro de momentos.': (
    'A confirmar o pagamento… Se já confirmaste no MB Way, a entrega segue sozinha dentro de momentos.',
    'Confirming the payment… If you already confirmed in MB Way, the delivery carries on by itself in a moment.'
  ),
  'Cancelar corrida': ('Cancelar entrega', 'Cancel delivery'),
  'Cancelar corrida?': ('Cancelar entrega?', 'Cancel delivery?'),
  'Corrida cancelada. Não foste cobrado.':
      ('Entrega cancelada. Não foste cobrado.', 'Delivery cancelled. You were not charged.'),
  'Abre o MBWay e confirma para a corrida seguir.':
      ('Abre o MBWay e confirma para a entrega seguir.', 'Open MB Way and confirm so the delivery can go ahead.'),

  // ── Cliente: reserva marcada ───────────────────────────────────────────
  'Escolhe o dia e a hora. Procuramos motorista com antecedência e avisamos-te assim que estiver confirmado.': (
    'Escolhe o dia e a hora. Procuramos estafeta com antecedência e avisamos-te assim que estiver confirmado.',
    'Choose the day and time. We look for a courier in advance and let you know as soon as it is confirmed.'
  ),
  'A seguir escolhes como pagas: dinheiro ao motorista, cartão ou MB Way.': (
    'A seguir escolhes como pagas: dinheiro ao estafeta, cartão ou MB Way.',
    'Next you choose how to pay: cash to the courier, card or MB Way.'
  ),
  'Um motorista vem buscar-te a essa hora.':
      ('Um estafeta vem buscar a encomenda a essa hora.', 'A courier will collect the parcel at that time.'),
  'Faltam menos de {0} horas para a viagem. Pode haver uma taxa de cancelamento.': (
    'Faltam menos de {0} horas para a entrega. Pode haver uma taxa de cancelamento.',
    'Less than {0} hours to the delivery. A cancellation fee may apply.'
  ),
  'Dia da viagem': ('Dia da entrega', 'Delivery day'),
  'Hora da viagem': ('Hora da entrega', 'Delivery time'),
  'O motorista é avisado. Se já tiver outra reserva perto dessa hora, procuramos outro motorista.': (
    'O estafeta é avisado. Se já tiver outra reserva perto dessa hora, procuramos outro estafeta.',
    'The courier is notified. If they already have another booking near that time, we look for another courier.'
  ),
  'Hora alterada. O teu motorista mantém-se.':
      ('Hora alterada. O teu estafeta mantém-se.', 'Time changed. Your courier stays the same.'),
  'Hora alterada. Vamos procurar motorista para a hora nova.': (
    'Hora alterada. Vamos procurar estafeta para a hora nova.',
    'Time changed. We will look for a courier for the new time.'
  ),
  'No ecrã de pedir motorista tens "Marcar para depois".': (
    'No ecrã de enviar encomenda tens "Marcar para depois".',
    'On the send-a-parcel screen you have "Book for later".'
  ),
  'Corrida marcada!': ('Entrega marcada!', 'Delivery booked!'),
  'Não encontrámos motorista para esta hora. Podes marcar outra viagem.': (
    'Não encontrámos estafeta para esta hora. Podes marcar outra entrega.',
    'We did not find a courier for this time. You can book another delivery.'
  ),
  'Não encontrámos motorista para esta hora. O reembolso é automático — não precisas de fazer nada.': (
    'Não encontrámos estafeta para esta hora. O reembolso é automático — não precisas de fazer nada.',
    'We did not find a courier for this time. The refund is automatic — you do not need to do anything.'
  ),
  'Pagas {0} a menos ao motorista, em dinheiro.':
      ('Pagas {0} a menos ao estafeta, em dinheiro.', 'You pay the courier {0} less, in cash.'),
  'Pagas {0} a mais ao motorista, em dinheiro, no fim da viagem.': (
    'Pagas {0} a mais ao estafeta, em dinheiro, no fim da entrega.',
    'You pay the courier {0} more, in cash, at the end of the delivery.'
  ),
  'A viagem fica com {0} km.': ('A entrega fica com {0} km.', 'The delivery becomes {0} km.'),

  // ── Cliente: a acompanhar ──────────────────────────────────────────────
  'A tua corrida': ('A tua entrega', 'Your delivery'),
  'Sem corrida ativa.': ('Sem entrega ativa.', 'No active delivery.'),
  'Motorista': ('Estafeta', 'Courier'),
  'O teu motorista': ('O teu estafeta', 'Your courier'),
  'Motorista a caminho': ('Estafeta a caminho da recolha', 'Courier on the way to pick up'),
  'Motorista a caminho · chega em ~{0} min': (
    'Estafeta a caminho da recolha · chega em ~{0} min',
    'Courier on the way to pick up · arrives in ~{0} min'
  ),
  'O motorista chega em ~{0} min':
      ('O estafeta chega à recolha em ~{0} min', 'The courier reaches the pickup in ~{0} min'),
  'O motorista chegou': ('O estafeta chegou à recolha', 'The courier is at the pickup'),
  'Viagem em curso': ('A encomenda vai a caminho da entrega', 'The parcel is on its way'),
  'Boa viagem! O preço é o que viste ao pedir.': (
    'A encomenda vai a caminho! O preço é o que viste ao pedir.',
    'Your parcel is on its way! The price is what you saw when you asked.'
  ),
  '{0} aceitou a tua corrida': ('{0} aceitou a tua entrega', '{0} accepted your delivery'),
  '{0} aceitou a tua corrida · está a terminar outra viagem': (
    '{0} aceitou a tua entrega · está a terminar outra',
    '{0} accepted your delivery · finishing another job first'
  ),
  'O teu motorista aceitou · está a terminar outra viagem': (
    'O teu estafeta aceitou · está a terminar outra',
    'Your courier accepted · finishing another job first'
  ),
  '{0} aceitou a tua corrida · está a terminar outra viagem · chega em ~{1} min': (
    '{0} aceitou a tua entrega · está a terminar outra · chega em ~{1} min',
    '{0} accepted your delivery · finishing another job first · arrives in ~{1} min'
  ),
  'O teu motorista aceitou · está a terminar outra viagem · chega em ~{0} min': (
    'O teu estafeta aceitou · está a terminar outra · chega em ~{0} min',
    'Your courier accepted · finishing another job first · arrives in ~{0} min'
  ),
  'O teu motorista aceitou a tua corrida e está a terminar outra viagem aqui perto. Segue logo para a tua recolha — és o próximo.': (
    'O teu estafeta aceitou a tua entrega e está a terminar outra aqui perto. Segue logo para a recolha — és o próximo.',
    'Your courier accepted your delivery and is finishing another job nearby. They head to your pickup straight after — you are next.'
  ),
  'A ligar-se ao motorista…': ('A ligar-se ao estafeta…', 'Connecting to the courier…'),
  'À espera da confirmação do MB Way. Abre a app do teu banco e confirma o pagamento — só depois começamos a procurar motorista.': (
    'À espera da confirmação do MB Way. Abre a app do teu banco e confirma o pagamento — só depois começamos a procurar estafeta.',
    'Waiting for the MB Way confirmation. Open your banking app and confirm the payment — only then do we start looking for a courier.'
  ),
  'O pagamento não foi concluído — ainda não começámos a procurar motorista e não foste cobrado. Toca em «Pagar de novo» ou cancela sem custo.': (
    'O pagamento não foi concluído — ainda não começámos a procurar estafeta e não foste cobrado. Toca em «Pagar de novo» ou cancela sem custo.',
    'The payment was not completed — we have not started looking for a courier and you were not charged. Tap «Pay again» or cancel at no cost.'
  ),
  'Ainda não começámos a procurar motorista — estamos à espera da confirmação do pagamento. Se já confirmaste, aparece dentro de momentos.': (
    'Ainda não começámos a procurar estafeta — estamos à espera da confirmação do pagamento. Se já confirmaste, aparece dentro de momentos.',
    'We have not started looking for a courier yet — we are waiting for the payment confirmation. If you already confirmed, it shows up in a moment.'
  ),
  'De momento não há motoristas disponíveis. Podes tentar novamente.': (
    'De momento não há estafetas disponíveis. Podes tentar novamente.',
    'There are no couriers available right now. You can try again.'
  ),
  'Pede a corrida outra vez para escolheres o pagamento — a anterior não chegou a ter motorista e não foi cobrada.': (
    'Pede a entrega outra vez para escolheres o pagamento — a anterior não chegou a ter estafeta e não foi cobrada.',
    'Request the delivery again to choose the payment — the previous one never had a courier and was not charged.'
  ),
  'Desistir da corrida?': ('Desistir da entrega?', 'Give up on the delivery?'),
  'Ainda não foste cobrado e nenhum motorista foi chamado. Podes desistir sem custo.': (
    'Ainda não foste cobrado e nenhum estafeta foi chamado. Podes desistir sem custo.',
    'You have not been charged and no courier was called. You can give up at no cost.'
  ),
  'Afinal o pagamento já entrou (ou está a ser confirmado) — a corrida segue.': (
    'Afinal o pagamento já entrou (ou está a ser confirmado) — a entrega segue.',
    'The payment did go through (or is being confirmed) — the delivery goes ahead.'
  ),
  'A corrida já tinha terminado.': ('A entrega já tinha terminado.', 'The delivery had already finished.'),
  'A corrida já estava cancelada.': ('A entrega já estava cancelada.', 'The delivery was already cancelled.'),
  'A corrida já não permite mudar o destino.': (
    'A entrega já não permite mudar o destino.',
    'The delivery can no longer change its destination.'
  ),
  'A corrida já não permite adicionar paragens.':
      ('A entrega já não permite adicionar paragens.', 'The delivery can no longer add stops.'),
  'Esta corrida foi paga por MB Way. A paragem é cobrada agora — só é adicionada depois de confirmares no MB Way.': (
    'Esta entrega foi paga por MB Way. A paragem é cobrada agora — só é adicionada depois de confirmares no MB Way.',
    'This delivery was paid with MB Way. The stop is charged now — it is only added after you confirm in MB Way.'
  ),
  'Esta corrida foi paga no cartão. A paragem é cobrada agora — só é adicionada depois de o pagamento passar.': (
    'Esta entrega foi paga no cartão. A paragem é cobrada agora — só é adicionada depois de o pagamento passar.',
    'This delivery was paid by card. The stop is charged now — it is only added after the payment goes through.'
  ),
  'Escolhe onde o motorista deve passar a caminho do destino.': (
    'Escolhe onde o estafeta deve passar a caminho da entrega.',
    'Choose where the courier should stop on the way to the drop-off.'
  ),
  'Partilhar viagem': ('Partilhar entrega', 'Share delivery'),
  'Resumo da viagem': ('Resumo da entrega', 'Delivery summary'),

  // ── Cliente: fim, avaliação e recibo ───────────────────────────────────
  'Avaliar viagem': ('Avaliar entrega', 'Rate the delivery'),
  'Viagem concluída': ('Encomenda entregue', 'Parcel delivered'),
  'Como foi o motorista?': ('Como foi o estafeta?', 'How was the courier?'),
  'Queres deixar uma gorjeta ao motorista?':
      ('Queres deixar uma gorjeta ao estafeta?', 'Would you like to tip the courier?'),
  'Corrida incluída no teu plano — não pagaste nada.': (
    'Entrega incluída no teu plano — não pagaste nada.',
    'Delivery included in your plan — you paid nothing.'
  ),
  'O recibo fica disponível quando a viagem terminar.': (
    'O recibo fica disponível quando a entrega terminar.',
    'The receipt is available once the delivery is finished.'
  ),
  'Serviço de transporte (motorista)': ('Serviço de entrega (estafeta)', 'Delivery service (courier)'),
  'Valor da viagem': ('Valor da entrega', 'Delivery amount'),
  'Recibo de viagem. Não substitui fatura: a fatura é emitida por software certificado.': (
    'Recibo da entrega. Não substitui fatura: a fatura é emitida por software certificado.',
    'Delivery receipt. It does not replace an invoice: the invoice is issued by certified software.'
  ),
  'Fazer uma queixa sobre esta viagem':
      ('Fazer uma queixa sobre esta entrega', 'Make a complaint about this delivery'),

  // ── Estafeta: oferta ───────────────────────────────────────────────────
  'Nova corrida': ('Nova encomenda', 'New parcel'),
  'Nova corrida — agora': ('Nova encomenda — agora', 'New parcel — now'),
  'Nova corrida — depois desta corrida':
      ('Nova encomenda — depois desta entrega', 'New parcel — after this delivery'),
  'Esta corrida já não está disponível.':
      ('Esta encomenda já não está disponível.', 'This parcel is no longer available.'),
  'Esta corrida já foi para outro motorista.':
      ('Esta encomenda já foi para outro estafeta.', 'This parcel already went to another courier.'),
  'Esta reserva já foi para outro motorista.':
      ('Esta reserva já foi para outro estafeta.', 'This booking already went to another courier.'),
  'Corrida aceite.': ('Encomenda aceite.', 'Parcel accepted.'),
  'Corrida em fila — abre sozinha quando terminares esta.': (
    'Encomenda em fila — abre sozinha quando terminares esta.',
    'Parcel queued — it opens by itself when you finish this one.'
  ),
  'Já tens uma corrida em fila — só podes levar uma de cada vez.': (
    'Já tens uma entrega em fila — só podes levar uma de cada vez.',
    'You already have a queued delivery — you can only take one at a time.'
  ),
  'Não consegui aceitar: já tens outra corrida a decorrer.': (
    'Não consegui aceitar: já tens outra entrega a decorrer.',
    'Could not accept: you already have another delivery in progress.'
  ),

  // ── Estafeta: a fazer a entrega ────────────────────────────────────────
  'Corrida': ('Encomenda', 'Parcel'),
  'Passageiro': ('Cliente', 'Customer'),
  'Cheguei ao passageiro': ('Cheguei à recolha', 'I am at the pickup'),
  'Iniciar viagem': ('Recolhi a encomenda', 'I picked up the parcel'),
  'Finalizar viagem': ('Entreguei a encomenda', 'I delivered the parcel'),
  'Começa ao terminares esta viagem':
      ('Começa ao terminares esta entrega', 'Starts when you finish this delivery'),
  'Recolha da próxima corrida': ('Recolha da próxima entrega', 'Pickup of the next delivery'),
  'Destino da próxima corrida': ('Destino da próxima entrega', 'Drop-off of the next delivery'),
  'Próxima corrida — depois desta': ('Próxima entrega — depois desta', 'Next delivery — after this one'),
  'Próxima corrida na fila ativada.':
      ('Próxima entrega na fila ativada.', 'Next queued delivery activated.'),
  'Largar a próxima corrida?': ('Largar a próxima entrega?', 'Drop the next delivery?'),
  'A corrida {0} volta para outros motoristas.':
      ('A entrega {0} volta para outros estafetas.', 'The delivery {0} goes back to other couriers.'),
  'A corrida que estás a fazer continua igual.':
      ('A entrega que estás a fazer continua igual.', 'The delivery you are doing stays the same.'),
  'Próxima corrida largada — voltou para a roda.': (
    'Próxima entrega largada — voltou para a roda.',
    'Next delivery dropped — it went back to the queue.'
  ),
  'Já não tens nenhuma corrida a decorrer.':
      ('Já não tens nenhuma entrega a decorrer.', 'You no longer have a delivery in progress.'),
  'O cliente cancelou a corrida.': ('O cliente cancelou a entrega.', 'The customer cancelled the delivery.'),
  'Tens a certeza que queres cancelar esta corrida?': (
    'Tens a certeza que queres cancelar esta entrega?',
    'Are you sure you want to cancel this delivery?'
  ),
  'Passageiro não compareceu': ('Ninguém na recolha', 'Nobody at the pickup'),
  'Passageiro não compareceu?': ('Ninguém na recolha?', 'Nobody at the pickup?'),
  'Marca como "não compareceu" se o passageiro não apareceu no local.': (
    'Marca como "não compareceu" se ninguém apareceu com a encomenda no local.',
    'Mark as "no-show" if nobody turned up with the parcel at the spot.'
  ),
  'Registado: passageiro não compareceu. A taxa de espera foi creditada a ti.': (
    'Registado: ninguém na recolha. A taxa de espera foi creditada a ti.',
    'Recorded: nobody at the pickup. The waiting fee was credited to you.'
  ),
  'o motorista devolveu a reserva': ('o estafeta devolveu a reserva', 'the courier returned the booking'),
  'Reserva devolvida. A Bora procura outro motorista.': (
    'Reserva devolvida. A Bora procura outro estafeta.',
    'Booking returned. Bora is looking for another courier.'
  ),
  'Reserva devolvida. Já estamos a procurar outro motorista.': (
    'Reserva devolvida. Já estamos a procurar outro estafeta.',
    'Booking returned. We are already looking for another courier.'
  ),
  'Perto da hora recebes um aviso para confirmares que vais. Se não confirmares, a corrida passa a outro motorista.': (
    'Perto da hora recebes um aviso para confirmares que vais. Se não confirmares, a entrega passa a outro estafeta.',
    'Close to the time you get a notice to confirm you are going. If you do not confirm, the delivery goes to another courier.'
  ),
  'Recebes €{0} desta corrida. A volta já está paga — não cobres nada ao cliente.': (
    'Recebes €{0} desta entrega. A volta já está paga — não cobres nada ao cliente.',
    'You get €{0} for this delivery. The return leg is already paid — do not charge the customer anything.'
  ),
  'Recebes €{0} desta corrida. O cliente já pagou os €{1} online — não cobres nada ao cliente.': (
    'Recebes €{0} desta entrega. O cliente já pagou os €{1} online — não cobres nada ao cliente.',
    'You get €{0} for this delivery. The customer already paid the €{1} online — do not charge them anything.'
  ),
  'Recebes €{0} desta corrida. Os €{1} que o cliente paga NÃO são teus — recolhes em mão por conta da Bora, que acerta contigo no fim da semana.': (
    'Recebes €{0} desta entrega. Os €{1} que o cliente paga NÃO são teus — recolhes em mão por conta da Bora, que acerta contigo no fim da semana.',
    'You get €{0} for this delivery. The €{1} the customer pays are NOT yours — you collect them for Bora, which settles with you at the end of the week.'
  ),

  // ── Estafeta: fim ──────────────────────────────────────────────────────
  'Fim da corrida': ('Fim da entrega', 'Delivery finished'),
  'Como foi o passageiro?': ('Como foi o cliente?', 'How was the customer?'),

  // ── Ronda 1 do revisor (21/10) ─────────────────────────────────────────
  'À espera do passageiro · {0}': ('À espera na recolha · {0}', 'Waiting at the pickup · {0}'),
  'Espera {0} — podes marcar "não compareceu" (menu ⋮)': (
    'Espera {0} — podes marcar "ninguém na recolha" (menu ⋮)',
    'Waiting {0} — you can mark "nobody at the pickup" (menu ⋮)'
  ),
  'Ganhaste €{0} nesta corrida.': ('Ganhaste €{0} nesta entrega.', 'You earned €{0} on this delivery.'),
  'Corrida finalizada — ganhaste €{0}. Próxima corrida ativada.': (
    'Entrega concluída — ganhaste €{0}. Próxima entrega ativada.',
    'Delivery finished — you earned €{0}. Next delivery activated.'
  ),
  'A Bora procura outro motorista. Deixas de ficar com esta corrida e não perdes nada por devolveres — vale mais avisares agora do que o cliente ficar à espera.': (
    'A Bora procura outro estafeta. Deixas de ficar com esta entrega e não perdes nada por devolveres — vale mais avisares agora do que o cliente ficar à espera.',
    'Bora looks for another courier. You no longer have this delivery and you lose nothing by returning it — better to warn now than leave the customer waiting.'
  ),
  'Vamos procurar outro motorista para o cliente. Não és penalizado — avisar cedo é o que ajuda.': (
    'Vamos procurar outro estafeta para o cliente. Não és penalizado — avisar cedo é o que ajuda.',
    'We will look for another courier for the customer. You are not penalised — warning early is what helps.'
  ),
  'Conclui a corrida atual antes de ficar offline.': (
    'Conclui a entrega atual antes de ficar offline.',
    'Finish the current delivery before going offline.'
  ),
  'Código da viagem': ('Código da entrega', 'Delivery code'),
  // estado da corrida em palavras (TvdeRide.statusLabel)
  'À procura de motorista…': ('À procura de estafeta…', 'Looking for a courier…'),
  'Sem motoristas disponíveis': ('Sem estafetas disponíveis', 'No couriers available'),
  'O teu motorista está a terminar uma viagem próxima': (
    'O teu estafeta está a terminar outra entrega aqui perto',
    'Your courier is finishing another delivery nearby'
  ),
  'Motorista atribuído': ('Estafeta atribuído', 'Courier assigned'),
  'Cancelada pelo motorista': ('Cancelada pelo estafeta', 'Cancelled by the courier'),
  'Não compareceu': ('Ninguém na recolha', 'Nobody at the pickup'),
  // fase da corrida no ecrã do estafeta (TvdeRide.driverPhaseTitle)
  'À espera do passageiro': ('À espera na recolha', 'Waiting at the pickup'),
  'Próxima corrida': ('Próxima entrega', 'Next delivery'),
  'Pagas ao motorista no fim.': ('Pagas ao estafeta no fim.', 'You pay the courier at the end.'),
  'Viagem': ('Entrega', 'Delivery'),
  'Recolha a {0} km do destino desta corrida · {1} km de viagem. Abre sozinha quando terminares.': (
    'Recolha a {0} km do destino desta entrega · {1} km até à entrega. Abre sozinha quando terminares.',
    'Pickup {0} km from this drop-off · {1} km to deliver. Opens by itself when you finish.'
  ),
};
