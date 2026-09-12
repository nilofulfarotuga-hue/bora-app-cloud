---
id: licao-heartbeat-fantasma
tipo: licao
origem: [drivers.is_online / last_heartbeat_at · dispatch · mega-fix 2026-07-18 Parte 10]
ultima_confirmacao: 2026-07-18
zona: verde
confianca: verificado
---

# Lição — `is_online = true` sem TTL = dispatch para mortos (presença precisa de cron de expiração)

**Problema.** Pedidos ficavam presos à espera de aceitação até expirarem por timeout. Prova: 3
estafetas com `is_online = true` mas `last_heartbeat_at` de 3,5 dias atrás (ou NUNCA) — o
dispatch oferecia-lhes corridas que eles nunca iam ver, porque estavam offline de facto.

**Causa real.** `is_online` é ligado quando o app entra em foreground/heartbeat, mas nada o
**desliga** de forma fiável quando o app morre, perde rede ou o telemóvel desliga. O flag fica
`true` para sempre — um "fantasma" online. O dispatch, que confia em `is_online`, gasta
tentativas com quem não está lá.

**Regra generalizável.**
- Toda presença/online-status precisa de **TTL por heartbeat**: um cron que expira quem não bate
  o coração há X minutos.
  ```sql
  UPDATE drivers SET is_online = false
  WHERE is_online AND (last_heartbeat_at IS NULL
        OR last_heartbeat_at < now() - interval '15 minutes');
  ```
  (pg_cron a cada 5 min, job `drivers-heartbeat-expire`.)
- O flag "estou online" é uma afirmação que caduca, não um facto permanente. Sem expiração,
  "online" quer dizer "esteve online alguma vez", que não serve para dispatch.
- Não mexer no dispatch em si — a cura é a expiração da presença a montante, não lógica de
  matching a jusante.

Presença sem prazo de validade mente. Se algo diz "estou aqui", tem de o repetir, e alguém tem
de o esquecer quando ele se cala.
