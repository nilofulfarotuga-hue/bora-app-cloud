# ORDEM EM FILA — `iphone-automatico-2026-09-22`

> Chegada a 2026-09-22, **a meio** da missão `pagamento-cartao-2026-09-22`.
> A própria ordem diz: "só colar isto depois de a missão `pagamento-cartao-2026-09-22`
> ter fechado. Uma ordem de cada vez" e "ABRE UMA SESSÃO NOVA no Claude Code".
> Por isso **não foi arrancada** — fica aqui para não se perder.

**Motor:** OPUS. **Porta:** Claude Code com o Chrome ligado. **run_id:** `iphone-automatico-2026-09-22`.

## O que pede, em resumo

Hoje o Android é automático (push → `build_android.yml` → versionCode sozinho → Play Internal
Testing) e o iPhone não: o `build_ios.yml` já assina e envia (`xcrun altool --upload-app`, segredos
`ASC_KEY_ID`/`ASC_ISSUER_ID`/`ASC_KEY_P8_B64`) mas só corre à mão (`workflow_dispatch` com
`inputs.enviar=true`) e pára no envio.

- **Passo 0** — ler `build_ios.yml` e `build_android.yml` lado a lado; escrever no `e2e_log` o que
  dispara cada um, como numeram a build, o que fazem no fim, e confirmar que os segredos ASC existem
  e estão válidos **antes** de mexer no gatilho.
- **Passo 1** — iOS a construir-se a cada push na branch (mesmos `paths-ignore` do Android),
  `concurrency` com `cancel-in-progress`, porta de qualidade antes de enviar (analyze + testes +
  autoteste dos 3 perfis, regra de 10/09), número da build do `github.run_number`, falha clara se
  faltar segredo de assinatura.
- **Passo 2** — TestFlight interno automático: grupo interno com `boraappbora@gmail.com`, atribuição
  pela API do ASC depois de processar, respostas de conformidade de exportação preenchidas de
  antemão, aviso no Telegram quando ficar disponível.
- **Passo 3** — ida ao público num disparo só (`workflow_dispatch` com `publicar=true` ou tag),
  notas PT-PT dos commits, como pedir revisão acelerada escrito no `ios/LANCAMENTO-IOS-ESTADO.md`,
  e **investigar e reportar** (não ligar) o lançamento faseado.
- **Passo 4** — paridade nos três lados num só push: Play Internal, TestFlight interno, site.
- **Passo 5** — painel admin: propor (não construir) um ecrã com a versão no ar em cada loja.
- **Passo 6** — provas: push real de ponta a ponta + relatório pelo Telegram.

Conta Apple: `boraappbora@gmail.com`. O Danilo não clica em painéis — o executor faz tudo pelo
navegador e só lhe deixa a página aberta se sobrar um código SMS.
