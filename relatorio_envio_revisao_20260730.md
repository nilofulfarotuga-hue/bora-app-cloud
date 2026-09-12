# Relatório — 3.º envio para revisão da Google — 30/07/2026

App: **Bora App** (`pt.boraapp.bora`) · Conta: `boraappbora@gmail.com`
Painel de Produção:
`https://play.google.com/console/u/0/developers/5372142912736686834/app/4974665836977103534/tracks/production`
Vista geral da publicação:
`https://play.google.com/console/u/0/developers/5372142912736686834/app/4974665836977103534/publishing`

---

## 1. Vídeo trocado na declaração — ✅ FEITO

Página: **Política → Conteúdo da app → Autorizações de acesso à localização**
(`/app-content/background-location-permissions`)

| | |
|---|---|
| URL antigo | `https://youtube.com/shorts/JEyOj7und6M?is=jdRzahw2m7iQs01n` |
| **URL novo (guardado)** | **`https://youtube.com/shorts/Y3R9g-hpHcM`** |

Prova: banner **"As suas alterações foram guardadas."** e, depois de recarregar a
página, leitura directa do campo:

```json
{"val":"https://youtube.com/shorts/Y3R9g-hpHcM","b":[{"t":"Guardar","d":true}]}
```

`Guardar` **desativado** (`d:true`) = sem alterações pendentes = persistido.

O texto da declaração (261/500 caracteres) e as 3 autorizações declaradas
(`ACCESS_BACKGROUND_LOCATION`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`)
ficaram como estavam.

**Nota (a UI só dá para escrever à mão):** a Play Console é AngularDart — injectar
valor por JavaScript é cosmético (o `Guardar` fica cinzento). Só teclado real regista.

---

## 2. Bundle da Produção — ✅ agora é o **504**

A tarefa dizia "editar o rascunho de Produção". **Não havia rascunho**: o `501`
estava como versão `completed` da faixa, e a UI da Play Console **não deixa trocar
o bundle** de uma versão já submetida (o modal "Editar detalhes da versão" só mexe
em nome + notas). Resolvido pela **Play Developer API v3**
(`edits → tracks.update → commit`), que é fiável neste PC.

Estado final da faixa `production` (lido pela API, depois de aplicar):

```
504 (1.0.1)   status=completed   (implementação completa)
```

— uma única versão, o **504**, que é o bundle **com** a declaração em destaque
(o mesmo que já está no Teste Interno e no Alpha).

Mantidos: notas `<pt-PT>` exactamente como estavam · países **Portugal + Brasil**
(ambos "Segmentado") · faixas de teste intactas.

### ⚠️ Desvio ao pedido: rollout ficou 100%, não 10%

Foi o ponto que **não batia certo** e que te perguntei antes de enviar. Motivo técnico:

- Um rollout faseado a 10% obriga a Play a ter uma versão base para os outros 90%.
  Sempre que pus só o 504 a 10%, a API **repunha automaticamente o 501** como
  "implementação completa" — ou seja, **90% dos utilizadores receberiam o 501**,
  o bundle **sem** a declaração em destaque → 3.ª rejeição pelo mesmo motivo.
- Tentativas de neutralizar o 501 (testadas em *edits* descartáveis, sem commit):
  - `501` como `halted` → PUT 200 mas **COMMIT 500** (Internal error).
  - `501` como `draft` → commit passou mas **duplicou** o 501 na faixa (rascunho + completo).
    Foi revertido de imediato.
- Único estado coerente com "a Produção só entrega o 504": **504 a implementação
  completa**. Escolheste esta opção.

---

## 3. Erros de "declaração em destaque" e "vídeo" — ✅ desapareceram

Na Vista geral da publicação, antes do envio:

> **"As suas alterações já podem ser enviadas para revisão. Podemos encontrar
> problemas adicionais durante a revisão da sua app."**

Nenhuma menção a *"Não há uma declaração em destaque"* nem a *"Problemas com o
vídeo enviado"* — os dois erros do Envio 121.

Continua a aparecer, como informação (não erro), a linha:
> Conteúdo da app: declaração "Atualizar autorizações de acesso à localização em segundo plano"

que é apenas a marcação de que a declaração vai ser tida em conta na revisão.

O banner vermelho **"Algumas alterações recentes foram rejeitadas"** é o histórico
do Envio 121 — mantém-se até a nova revisão terminar.

---

## 4. Estado final — ✅ **ENVIADO PARA REVISÃO**

Clicado **"Enviar 5 alterações para revisão"** → diálogo de confirmação:

> "Estas alterações vão ser enviadas para a Google para revisão. Normalmente, as
> revisões são concluídas no prazo de 7 dias, mas podem demorar mais tempo."

→ **"Envie as alterações para verificação"**. Depois do clique a secção passou de
*"Alterações ainda não enviadas para revisão"* para **"Alterações em revisão"**
(com a opção "Remover alterações"), e o banner vermelho de rejeição desapareceu.

As 5 alterações em revisão:

| Faixa / secção | Alteração |
|---|---|
| Produção | **504 (1.0.1)** — Inicie a implementação completa |
| Produção | Países/regiões — Adicione 2: **Brasil, Portugal** |
| Testes abertos | 1.0.1 — Inicie a implementação completa |
| Testes fechados – Alpha | 1.0.1 — Inicie a implementação completa |
| Conteúdo da app | Segurança dos dados — questionário |

Estado das verificações rápidas no momento do envio:
> "A executar verificações rápidas para problemas comuns … **As alterações vão ser
> enviadas para revisão assim que as verificações forem concluídas com êxito.**"
> (faltavam ≤ 12 minutos)

Ou seja: o envio está **armado e garantido pela própria Google** — só sai quando as
verificações passarem. Não há mais nada a fazer do teu lado; é esperar a revisão
(normalmente até 7 dias).

### Confirmação final (verificado ~5 min depois)

As verificações rápidas **concluíram com êxito** e o envio saiu. A Vista geral da
publicação mostra agora:

> **"As suas alterações estão agora em revisão. Podemos encontrar problemas
> adicionais durante a revisão da sua app."**

Secção **"Alterações em revisão"** com os 5 itens · banner de rejeição desaparecido ·
já não existe nenhuma secção "Alterações ainda não enviadas para revisão".

**Nada mais a fazer — é esperar a Google.**

---

## 5. Links

- Produção: `https://play.google.com/console/u/0/developers/5372142912736686834/app/4974665836977103534/tracks/production`
- Vista geral da publicação: `https://play.google.com/console/u/0/developers/5372142912736686834/app/4974665836977103534/publishing`

---

## Regras respeitadas

Não se tocou em preços, subscrições, IAP, contas de programador nem dados bancários.
Nenhuma faixa de teste apagada. Ficha da loja não alterada.
