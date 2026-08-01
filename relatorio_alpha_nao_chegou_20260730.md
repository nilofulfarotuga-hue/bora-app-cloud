# Relatório — build #328 (bundle 503) não chegou ao telemóvel — 30/07/2026

## 1. versionCode confirmado do build #328
Run `30466421688`, commit `5ef866c`, 9m21s, sucesso. Log verbatim:
- `Old: 1.0.1+502  ->  New: 1.0.1+503`
- `✓ Built build/app/outputs/bundle/release/app-release.aab (82.6MB)`
- `track: alpha` · `Finished uploading to the Play Store: 09136562230749576195`

**versionCode = 503.** (Havia 2 runs para o mesmo SHA — o segundo é o workflow do
**web** (Cloudflare Pages), não um segundo AAB.)

## 2. Estado exato que encontrei

Consultado pela **Google Play Developer API** (service account local, read-only),
não por leitura de ecrã:

| Track | versionCode | status |
|---|---|---|
| production | 501 | completed (**rejeitado** — envio 121) |
| **alpha** (Teste Fechado) | **503** | completed (rollout 100%) |
| beta (Teste Aberto) | 382 | completed |
| internal (Teste Interno) | 382 | completed |

Bundles na biblioteca: `378…382, 392, 497, 498, 499, 501, 503` → o **503 subiu bem**.

**Testadores por track (API):**
- alpha → `bora-app-testers@googlegroups.com` + `khadem-testers-service@googlegroups.com`
- internal → geridos por *lista de emails* (a API v3 só expõe googleGroups; o PUT
  devolve `403 "The internal track has been upgraded to use open or closed testing"`)

**A CAUSA (Vista geral da publicação):**
> botão **"Enviar 5 alterações para revisão"** · *"As suas alterações já podem ser
> enviadas para revisão"* · banner: *"Algumas alterações que enviou recentemente
> para verificação foram rejeitadas pela Google."* · *Publicação gerida desativada.*

O CI faz upload com **`changesNotSentForReview: true`** (foi preciso adicioná-lo a
28/07, senão a API descartava a edição inteira por causa da produção rejeitada).
Consequência: o 503 é **atribuído** ao alpha mas fica no balde *"alterações por
enviar para revisão"*. **Teste fechado passa por revisão da Google** → enquanto não
for enviado+aprovado, a Google **não distribui**. Daí o telemóvel não ver update.

**Não é rascunho, não é falta de testadores, não é assinatura.** É revisão não enviada.

### Porque NÃO cliquei em "Enviar 5 alterações para revisão"
É tudo-ou-nada: arrastaria o lançamento de **Produção 501** (que não tem a
declaração em destaque nem o vídeo novo) para uma **3.ª rejeição seguida** — risco
de escalada de sanção na conta. E a tua regra era não tocar em Produção.

## 3. O que corrigi

1. **Promovi o 503 para o Teste Interno** (API, `edits.tracks.update` + commit com
   `changesNotSentForReview=true` para não arrastar a Produção).
   **Teste Interno é o único track que NÃO passa por revisão.**
   Confirmado no Console: *"Ativa · Lançamento mais recente: **503 (1.0.1) - teste interno**"*.
2. **Arranjo durável no CI** — `.github/workflows/build_android.yml`:
   `track: alpha` → **`tracks: alpha,internal`** (um só upload, dois tracks; `track`
   singular está deprecated). Assim **todo o build futuro chega ao telemóvel na hora**,
   mesmo com a produção bloqueada.
   Juiz/anti-trapaça: **✅ CLEAN**. Commit `f68ca4c`, pushed → run `30530662172`
   (bumpa para 504 e publica em alpha+internal).

**Não toquei:** Produção, o lançamento pendente de vídeo, preços, IAP, contas,
dados bancários. A tentativa de escrever testadores por API falhou com 403 e foi
descartada (nenhuma alteração aplicada).

## 4. O que o Danilo faz agora (no telemóvel)

1. Play Store → procurar **Bora** (`pt.boraapp.bora`) ou abrir
   `https://play.google.com/store/apps/details?id=pt.boraapp.bora`
2. Deve aparecer **Atualizar** com a versão **503** (ou 504 dentro de ~15 min).
   Se não aparecer logo: Play Store → perfil → *Gerir apps* → *Atualizações
   disponíveis*, ou limpar a cache da Play Store. A propagação leva até ~30 min.

> O Teste Interno já foi usado por ti antes (o CI publicava lá até 28/07 — o
> comentário no workflow dizia "deixou de publicar no internal"), por isso a
> inscrição deve estar activa. **Se não aparecer nada em 30 min**, é sinal de que
> a tua conta saiu da lista de testadores internos — nesse caso: Play Console →
> Testar e lançar → Testar → **Testes internos** → separador **Testadores** →
> adicionar o email do telemóvel e usar o link de participação dessa página.
> (Não consegui ler esse separador: o Chrome congelou 5× a carregar a Play Console
> — o PC de 4 GB não aguenta o SPA. Preferi não insistir a martelar.)

## 5. Precisa de decisão tua? Uma só

Para o **alpha** voltar a fluir (e para a Produção sair do limbo), há 5 alterações
presas por enviar. **Isso continua bloqueado no vídeo de localização em segundo
plano** — é o passo à parte, fora do âmbito desta tarefa. Enquanto isso não se
resolver, o **Teste Interno é o canal de entrega** — e agora é automático.
