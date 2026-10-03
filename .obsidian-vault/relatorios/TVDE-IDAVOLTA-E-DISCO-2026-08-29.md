# TVDE IDA-E-VOLTA E DISCO — 2026-08-29

**Sessão:** `tvde-idavolta-e-disco-2026-08-29`
**Porta única:** CEO-AI invocado ✅
**Estado:** Blocos 2 e 3 ✅ fechados · Bloco 1 ✅ preparado e provado, **⚠️ à espera de autorização para aplicar**

---

## A COISA MAIS IMPORTANTE, EM QUATRO LINHAS

O ida-e-volta **não tem duas regras de preço**. Tem uma só, e os €8 são o **piso** dela.
A sessão anterior concluiu mal por ter olhado para a função de cotação e não ter seguido a
função que ela chama. **Mas o prejuízo é real e maior do que se pensava:** a cobrança pela
Stripe manda sempre €8, e numa rota de 20 km o cliente vê €30,40 — a Bora perde €21,90.

---

## PORTÕES MEDIDOS

| Portão | Exigido | Medido | Resultado |
|---|---|---|---|
| RAM (blocos 2 e 3) | 400 MB | **463 MB** | ✅ aprovado |
| Disco no arranque | — | **350 MB livres**, 12 pastas `audio_io_*` já de volta | ⚠️ tratado no Bloco 2 |

Inverti a ordem dos blocos: com 350 MB de disco, o resto rebentava a meio como na sessão
anterior. O Bloco 2 foi primeiro.

---

## BLOCO 2 — DISCO: A CAUSA, NÃO O SINTOMA ✅

### A hipótese da ordem estava perto, mas o defeito era outro

Não é que o guarda "não esteja agendado" nem que "olhe para outra pasta". O `audio_io.py`
**já limpa** — tem `finally: shutil.rmtree(...)` em cada função — e **já tem um varredor
de órfãs**, o `limpar_orfaos()`, que até respeita quem ainda está a trabalhar.

O defeito é onde o varredor é chamado:

```
limpar_orfaos()  definido na linha 220
                 chamado  na linha 275  <- e SO ai
```

A linha 275 está dentro do `mapear()`. E o `mapear()` **não é o caminho que verte**. Quem
verte é o `ler()` e o `escrever()`: criam a pasta, limpam no `finally` — mas o `finally`
**não corre quando o processo é morto** (OOM neste PC de 4 GB, ou o timeout de 3600 s).
Como também não escreviam `dono.pid`, ficavam órfãs sem dono identificável, e ninguém as
varria.

Prova de que era mesmo isso: as 12 pastas continham **só** `a.raw`, sem `dono.pid` — logo
não vinham do `mapear()`.

### A correcção — usa o mecanismo que já existia

Duas linhas em cada um dos dois criadores, nada de novo inventado:

```python
    limpar_orfaos()                  # quem entra varre o que ficou de quem morreu
    d = tempfile.mkdtemp(prefix="audio_io_")
    (Path(d) / "dono.pid").write_text(str(os.getpid()), encoding="utf-8")
```

Backup em `agentes/audio_io.py.bak-limpeza-2026-08-29`. A tarefa `BoraStudioCondutor`
**não foi parada**, como mandado.

### Prova — 3/3

```
=== depois ===
  A) dono MORTO           | apagada=True  | esperado=True  | OK
  B) sem marca, 45 min    | apagada=True  | esperado=True  | OK
  C) dono VIVO (este)     | apagada=False | esperado=False | OK

RESULTADO: 3/3 correctos
```

O caso C é o que interessa para a tua tranquilidade: **não pisa trabalho a decorrer**.

### Espaço

```
antes : 350 MB livres, 12 pastas
depois: 2447 MB livres, 0 pastas
```

---

## BLOCO 3 — LANCHADORES ✅

### Commitadas só as linhas do perfil

Commit **`558fb81a`**, exactamente **36 linhas** (18 em cada lanchador), nada mais:

```
 .../orquestrador-carteiro/deploy/run-claude-loop.cmd   | 18 ++++++++++++++++++
 .../hermes/ponte-pc/hermes-bridge/run-claude.cmd       | 18 ++++++++++++++++++
```

O `run-claude-loop.cmd` tinha 113 linhas alteradas, das quais só 18 eram minhas. Montei a
versão só-perfil sobre a de HEAD e pu-la no índice do git **sem tocar na árvore de
trabalho**, para o auto-fatiamento continuar por commitar, intacto, para o seu dono.

> Gotcha apanhado a tempo: à primeira, o recorte trouxe `\r` do ficheiro de trabalho (CRLF)
> para dentro de um blob que em HEAD é LF — `file` acusou *"with CRLF, LF line
> terminators"*. Normalizei para LF antes de commitar.

### Veredito do auto-fatiamento (testado, já não é incógnita)

O bloco por commitar desde 11/08 **não é só auto-fatiamento** — traz também um interruptor
`--motor-go` que reencaminha o Claude Code para o plano OpenCode Go. Testei as duas partes
isoladamente:

| Mecanismo | Teste | Resultado |
|---|---|---|
| Leitura da chave do `--motor-go` | correr a linha PowerShell do bloco | ✅ chave lida, 67 caracteres |
| Despejo dos marcos | ficheiro com 5 linhas, 3 delas `MARCO:` | ✅ devolveu as 3, aparadas |
| Contagem dos marcos | idem | ✅ `marcos em disco despejados: 3` |

**Veredito: mecanicamente sadio.** Continua por commitar porque não é trabalho desta
missão. Nota útil: o `--motor-go` aponta ao plano Go, que está esgotado até ~08/09 — se
for commitado, fica atrás do interruptor e não se activa sozinho.

---

## BLOCO 1 — IDA-E-VOLTA 🔴 PREPARADO, NÃO APLICADO

### A premissa corrigida

A ordem dizia "os €8 deixam de ser lidos". Na verdade **eles já são parte da regra única**:

```sql
tvde_roundtrip_price_for_km(km) = GREATEST(
    tvde_roundtrip_price_cents,                                    -- o PISO (800)
    ROUND( 2 * tvde_calculate_fare(km) * (100 - discount_pct)/100 )  -- o preço por rota
)
```

O piso manda até aos 6 km; acima disso o preço por rota é maior. **A chave não se apaga —
tem função.** Ficou documentada como piso, como a ordem pediu.

### E a trava de prejuízo? Não é precisa — e a premissa também estava trocada

A ordem dizia que o motorista recebe €3,50 fixos pela volta. **Não recebe fixos:**

```sql
v_return_reserve := tvde_roundtrip_return_driver_cents + v_extra_km * v_d_perkm
```

Escala com a distância, tal como o ganho da ida. Consequência: a margem da Bora é
**constante em €0,50**, em qualquer rota. Não há rota curta em que o cliente pague menos do
que o motorista recebe — desde que a cobrança use a fonte única.

**A partir de que distância deixa de morder?** Nunca morde. O que morde é o defeito.

### A PROVA DAS TRÊS ROTAS — calculada pelas funções reais em produção

| Rota | Cliente vê | Cobrado **hoje** | Cobrado **depois** | Motorista recebe | **Bora hoje** | **Bora depois** |
|---|---|---|---|---|---|---|
| curta (3 km) | €8,00 | €8,00 | €8,00 | €7,50 | +€0,50 | +€0,50 |
| média (10 km) | €14,40 | €8,00 | €14,40 | €13,90 | **−€5,90** | +€0,50 |
| longa (20 km) | €30,40 | €8,00 | €30,40 | €29,90 | **−€21,90** | +€0,50 |

O que o cliente vê **não muda em nenhuma das três** — muda o que é cobrado, que passa a
igualar o que ele viu. É exactamente o que a tua decisão pedia: corrigir a cobrança por
trás, não o preço à frente.

### O que foi mudado no código (local, sem deploy)

**`tvde-plan-payment/index.ts`** — deixa de ler a chave do piso; recebe a distância (que o
Flutter já enviava e a função ignorava) e pergunta à fonte única:

```ts
const distanceKm = Number(body?.distance_km);
if (!Number.isFinite(distanceKm) || distanceKm <= 0) {
  return json({ error: 'roundtrip_distance_required' }, 400);
}
const { data: rtPriceCents, error: rtPriceErr } = await rtAdmin
  .rpc('tvde_roundtrip_price_for_km', { p_distance_km: distanceKm });
const amountCents = Number(rtPriceCents);
if (rtPriceErr || !Number.isFinite(amountCents) || amountCents < 50) {
  // Sem fallback para 800 de proposito: cobrar o valor errado e pior do que nao cobrar.
  return json({ error: 'roundtrip_price_unavailable' }, 400);
}
```

O servidor **nunca aceita um preço vindo do cliente** — recebe a distância e pergunta à
base de dados. E não há fallback para 800: se não souber o preço, não cobra.

**`notify-tvde-driver/index.ts`** — em vez de recalcular, lê o que **foi acordado naquele
vale**, numa coluna que a função já tinha à mão:

```ts
.from('tvde_roundtrip_credits').select('payment_intent_id, paid_cents')
...
const rtPrice = Number(credit?.paid_cents)
```

### Verificação

```
deno check notify-tvde-driver/index.ts  -> Check ... (limpo)
deno check tvde-plan-payment/index.ts   -> 1 erro, IDENTICO ao da versao ANTES do patch
                                            (npm:@types/node ausente no ambiente local)
```

Comparei com a versão de HEAD para não confundir ruído do ambiente com defeito meu.

### Painel admin — já existia

`tvde_roundtrip_discount_pct` **já é editável** em
`admin_platform_settings_screen.dart:86`, por decisão explícita tua de 2026-08-01. Não
mexi, como a ordem manda.

### Fonte de verdade actualizada

- **`business_rules.md`**: nova **§56** (ida-e-volta por rota com piso, tabela da
  repartição, marcações €0,50 vs reservas €3 repartidos 2/1) + corrigida a janela de
  cancelamento de **4 h → 2 h** em §12.3 e §14.5 + fechada a nota de inconsistência que
  pedia essa correcção. Backup em `.bak-idavolta-2026-08-29`.
- **`CONTEXT.md`**: §13 reescrito com a correcção da premissa e a tabela das três rotas;
  §14 reduzido ao que falta mesmo decidir.

---

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

O que falta é **uma coisa só**: fazer deploy das duas Edge Functions
(`tvde-plan-payment` e `notify-tvde-driver`). O código está escrito, verificado e provado
nas três rotas. Não fiz o deploy porque publicar uma função que cobra é acto teu.

Enquanto não for feito, cada pacote ida-e-volta pago por cartão ou MB Way acima dos 6 km
sai a perder — **€5,90 aos 10 km, €21,90 aos 20 km.**

Responde **"vai"** e eu aplico.

---

## PARA O DANILO — outras duas

1. **O BoraStudio vai voltar a encher o disco?** Já não deve. O varredor passou a correr em
   cada entrada e as pastas passam a levar a marca do dono, por isso a próxima corrida
   apanha a anterior. Mas o produtor continua a criar 175 MB de cada vez: se voltares a ver
   o disco a apertar, diz que eu vou ver porque é que o processo está a ser morto a meio.
2. **O auto-fatiamento está testado e sadio** (ver Bloco 3). Dizes e committo-o, agora que
   já não é uma incógnita de 18 dias.
