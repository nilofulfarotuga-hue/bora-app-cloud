# CONTINUAR — hora de Lisboa (o que ficou de fora a 06/10/2026)

Missão de origem: `hora-lisboa-2026-10-06` · relatório `.claude/.ai/reports/2026-10-06-hora-lisboa.md`.
Feito e no ar: loja aberta/fechada, aviso do carrinho, dia mínimo e envio das festas, reservas
("hora já passou"), dias fechados do parceiro e "forçar até" do admin — tudo pela hora de Lisboa
(`paredeLisboa` para ler, `instanteDeLisboa` para enviar). Android 652, web #196, iPhone 1.0.12
build 168 no TestFlight.

Por ordem de valor:

1. **iPhone**: a 1.0.12 (build 168) só é submetida no primeiro envio depois de a Apple aprovar a
   1.0.11 (estava `WAITING_FOR_REVIEW` às 16h36 UTC de 06/10). Nada a fazer até lá.
2. **Hora da mesa (reservas)**: `lib/stores/reservation_store.dart`, nas duas funções que criam
   o pagamento do sinal, `'reserved_for': reservedFor.toUtc()` → `instanteDeLisboa(reservedFor)`.
   Não mexido por estar dentro do pagamento (Lista Vermelha na dúvida). Só muda a hora enviada,
   nenhum valor. Num telemóvel em Portugal o resultado é igual.
3. **Dias fechados (`business_hours.special_dates`)**: o servidor lê-os, a app não. Num feriado
   marcado pelo parceiro a app diz "Aberto" e o servidor recusa no fim (`STORE_CLOSED`). Receita:
   ler `special_dates` em `BusinessHours.fromJson` e consultá-los em `isOpenNow`/`statusLabel`
   pelo dia de `paredeLisboa`, com teste por instante.
4. **Outras diferenças app/servidor** (antigas): horário vazio (servidor: aberta; app: 09–22),
   dia sem chave (servidor: fechada; app: 09–22), "24:00" (servidor: aberta; app: 1440 min),
   `is_online=false` (app: fechada; servidor não olha). Decidir qual dos dois cede.
5. **Horas das marcações** mostradas no fuso do telemóvel (`services_store.dart` faz
   `.toLocal()`), e outros ecrãs de mostrar horas. Só aparência; trocar por `horaLisboa`.
6. **TVDE**: o "fim de semana" do plano de viagens usa o dia do telemóvel
   (`tvde_request_ride_screen.dart:390`). Toca em planos (dinheiro) — só com ordem.
7. **Admin "forçar até hoje"** expira logo (meia-noite de hoje já passou). Decidir se "até dia X"
   quer dizer "até ao fim do dia X".
