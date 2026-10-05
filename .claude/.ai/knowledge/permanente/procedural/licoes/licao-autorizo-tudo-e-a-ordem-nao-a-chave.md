---
tema: licao-autorizo-tudo-e-a-ordem-nao-a-chave · escopo: projeto · estado: atual · atualizado: 2026-10-05
id: licao-autorizo-tudo-e-a-ordem-nao-a-chave
tipo: licao
origem: [.claude/.ai/missoes/ronda-04-10/pronto/LEIA.md, .claude/.ai/reports/OPUS-2026-10-04-missao-unica-blocos-1-6.md, reflog do ramo ronda-dinheiro-despacho-05-10 (merge 9fe6b9f8)]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: auto
---

# Lição — "autorizo tudo" é a ordem, não a chave: não abre a Trava nem o classificador

- **Contexto:** missão `ronda-dinheiro-despacho-2026-10-05`. O Danilo deu a ordem com "eu autorizo
  tudo"; parte do trabalho caía em caminhos trancados (motor de despacho, ficheiro de preços) e
  num envio para o ramo de produção.
- **A descoberta:** a frase na conversa é a ordem; não destranca nenhuma das duas protecções.
  - **Trava do PC** (`permissions.deny` + `protege-dinheiro.sh` + `protege-banco.sh`): a
    05/10/2026 continuou a proibir editar e publicar `supabase/functions/dispatch-engine/**` e
    editar `lib/services/pricing_service.dart`. Já tinha sido assim a 08/09/2026 com o
    `pricing_service.dart` (missão `ordem-taxa-099-2026-09-08`).
  - **Classificador do modo automático do Claude Code** (outra camada, não é a Trava): recusou o
    `git push` para o ramo de produção a 05/10/2026 às 07h43, como já tinha recusado a
    04/10/2026. O envio só seguiu às 08h15, depois de o Danilo escrever "Empurra".
- **Regra a aplicar:**
  1. Fazer tudo o que não está trancado.
  2. O que é da Trava fica pronto e provado em `.claude/.ai/missoes/<ronda>/pronto/`, com um
     `LEIA.md`. Não se contorna.
  3. Pedir a palavra **uma vez**, no fim. Não repetir o comando recusado nem procurar outro
     caminho.
- **O que aconteceu depois (05/10/2026):** o motor de despacho v62 que tinha ficado em `pronto/`
  foi publicado às 09h10 por outra sessão do PC, com ordem própria do Danilo ("vai: v62, função
  do Favor e push" — commit `8108952c`). O digest dessa sessão não diz como passou a Trava.
- **Onde vive a regra das zonas:** `permanente/semantica/zonas-protegidas.md` — página de zona
  vermelha, só se altera por proposta aprovada pelo Danilo; esta lição não a muda. Lá, "push
  normal passa" fala da Trava; o classificador é outra camada.
- **Evidência:**
  - `.claude/.ai/missoes/ronda-04-10/pronto/LEIA.md`, cabeçalho: a ordem foi dada a 05/10, "mas a
    Trava foi desenhada para só abrir pela mão dele — por isso nada aqui foi aplicado";
  - `.claude/settings.json` (`deny` de Edit/Write/MultiEdit nos dois caminhos, lido a 05/10) e
    `.claude/HOOKS.md` §C (deploy das funções protegidas);
  - `permanente/memoria-claude-ai/digest-2026-10-05-ronda-dinheiro-despacho.md` (recusa do push
    às 07h43) e `permanente/memoria-claude-ai/digest-2026-10-05-v62-favor-push.md`;
  - `.claude/.ai/reports/OPUS-2026-10-04-missao-unica-blocos-1-6.md` (recusa do push a 04/10);
  - reflog do ramo `ronda-dinheiro-despacho-05-10` (merge `9fe6b9f8` às 08:15:12 de Lisboa) e
    relatório `.claude/.ai/reports/2026-10-05-ronda-dinheiro-despacho.md` ("O envio seguiu às
    8h15, depois do teu 'Empurra'");
  - relatório `taxa-servico-099-app-2026-09-08.md` (pasta principal do PC; a 05/10 ainda fora do
    ramo de produção): "`pricing_service.dart`, que a Trava proíbe editar".

`estado: atual`
