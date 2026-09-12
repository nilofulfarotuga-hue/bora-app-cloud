---
tema: aprovador-vermelho-relatorio · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-24
---

# 🚦 APROVADOR-VERMELHO — TRIAGEM DA FILA 🔴 (2026-07-24, gatilho FALLBACK_30MIN, 2ª corrida)

**Motivo do disparo:** gatilho FALLBACK_30MIN disparou de novo (fila `nova`=4, item mais antigo
parado ≥3192 min). Confirmado via `execute_sql` direto no projeto `ojykpzwqrtusfeakzrna` (nunca
assumido de memória).

**Achado principal:** esta é a **mesma fila, byte-a-byte**, já triada 12 minutos antes neste mesmo
dia — ver `aprovador-vermelho-2026-07-24-fallback30min-1.md` (gravado às 07:27:50 UTC). Os 4 IDs,
`dedup_key`, `created_at` e `status='nova'` são idênticos; nada mudou no banco entre as duas
corridas. O gatilho normal parece estar a disparar o FALLBACK_30MIN duas vezes seguidas para o
mesmo watermark parado — comportamento a observar (não é bug meu para corrigir; fora do meu
escopo de roteamento, mas registo para o Bibliotecário/maestro avaliarem se o `hermes-aprovador-
vermelho.sh` está a duplicar o disparo).

## Fila `robot_suggestions` status='nova' (SELECT real, 4 itens — inalterados)

| # | id | dedup_key | nível | criado em (UTC) | min. parado |
|---|---|---|---|---|---|
| 1 | `1efa3e60-10de-423c-97fb-8a21148de370` | `marcacoes:liberar-slots-orfãos-ttl` | 2 | 2026-07-22 02:07:13 | ~3212 |
| 2 | `47a4a9e6-07c7-4846-864a-e400064c9b0a` | `marcacoes:ttl-pending-payment` | 2 | 2026-07-22 06:07:13 | ~2972 |
| 3 | `c068f901-e877-4df0-8b43-0ac1b1c04234` | `marcacoes:ajustar-politica-no-show` | 2 | 2026-07-24 04:07:14 | ~212 |
| 4 | `7cf1a393-82b5-40d6-8738-7d300e73f85a` | `marcacoes:resolver-marcacoes-orfas` | 3 | 2026-07-24 05:07:16 | ~152 |

## Balde A (leitura/falso-positivo) — recomendo aprovar
**Nenhum.** Os 4 itens continuam Balde B, sem qualquer mudança face à corrida anterior.
`platform_settings.aprovador_vermelho_auto_baldeA = true`, mas sem efeito porque não há item A.

## Balde B (dinheiro real — precisa do Danilo) — reconfirmação, sem prova nova

### 1) `1efa3e60` — Libertar slots de marcações órfãs
Mesma análise da corrida anterior: automatiza escrita/cancelamento sobre reservas com
pré-pagamento Stripe real, sem regra de refund no payload. Sem mudança de estado no banco desde
07:27:50 UTC.
⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

### 2) `47a4a9e6` — Ajustar TTL para marcações pendentes de pagamento
Mesma família do item 1. Sem mudança de estado.
⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

### 3) `c068f901` — Ajustar política de no-show para marcações
`deposit_required_threshold` continua a ser política nova de exigir depósito — dinheiro real. Sem
mudança de estado.
⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

### 4) `7cf1a393` — Resolver marcações pendentes órfãs
`nivel=3`, `payload_execucao=null`. Proposta em si é sobre automatizar cancelamento/liberação de
slot pago — dinheiro real. Sem mudança de estado.
⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## Telegram — SUPRIMIDO nesta corrida
- Último envio real confirmado: **2026-07-24 07:27:50 UTC** (`admin_audit_log`, 4 linhas
  `robot_suggestion_baldeB_reconfirmado`/`_surfaced`, `telegram_enviado=true`).
- Gap desde então até esta corrida (07:39:28 UTC): **~12 minutos** — abaixo do limiar de ~60min do
  protocolo anti-spam, e **sem prova nova** (mesmo estado de banco). Regra aplicada: NÃO reenviar.
- Nenhuma mensagem Telegram foi disparada nesta corrida.

## Ações desta corrida
- 4 linhas novas em `admin_audit_log` (`robot_suggestion_baldeB_reconfirmado` ×4), cada uma com
  `telegram_enviado=false` e `motivo_supressao_telegram` explícito, para rasto de que a triagem
  correu mas o aviso foi propositadamente suprimido (não é omissão).
- Nenhuma escrita em `reservations`/`appointments`, `platform_settings` financeiros,
  `dispatch_engine`, `pricing_service` ou qualquer zona protegida — só roteamento de aprovação.
- Nenhum item promovido a Balde A; nenhuma auto-aprovação executada.

Auto-Balde-A: **ligado** (`platform_settings.aprovador_vermelho_auto_baldeA=true`) — sem efeito
nesta corrida (zero itens Balde A).

## Nota para o próximo triador
Os 4 itens continuam `status='nova'`, aguardando decisão humana. Se o gatilho FALLBACK_30MIN
disparar de novo em minutos (como aconteceu agora), **não é preciso reanalisar do zero** — só
confirmar via SELECT que `status='nova'` e `created_at` batem, e manter a supressão de Telegram
enquanto o gap ao último envio real (07:27:50 UTC) for <60min e não houver prova nova (ex.: nova
marcação órfã real, mudança de `deposit_status`, novo cron a consumir as settings propostas).
Sinal a levar ao Bibliotecário: o disparo do FALLBACK_30MIN duas vezes em 12 minutos para o mesmo
watermark pode indicar duplicação no `hermes-aprovador-vermelho.sh` ou no cron VPS — vale
investigar fora desta triagem (não é ação de roteamento de aprovação).
