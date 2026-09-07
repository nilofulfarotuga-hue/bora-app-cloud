# LANÇAMENTO iOS — ESTADO

> Missão `ios-lancamento` · run_id `ios-lancamento-2026-09-07`
> **Este ficheiro diz onde retomar.** Cada linha tem prova.
> Última actualização: 2026-09-07, fim da 1.ª sessão.
> Modo de trabalho: ver `carta-de-autonomia-ios` na memória do projeto.

---

## 1. O MARCO: a app compila para iPhone

Corrida `34163172748`, ramo `ios-lancamento`. **Passos 1 a 20 sem falhar.**

| Passo | Resultado |
|---|---|
| 10. `flutter analyze` | 0 erros |
| 11. `flutter test` | **473 testes verdes** |
| 12. Escolher e arrancar simulador | iPhone 17 Pro Max |
| 15. **Compilar para o simulador** | **verde, 7m11s** |
| 20. Publicar artefactos | `demo.mp4` 24 MB · `ecra-final.png` · `integration.log` |

`pod install` passou à primeira, 166 s, com os ~30 plugins. Era o risco grande
da missão. A receita está em `.github/workflows/build_ios.yml` e resumida na
memória em [`receita-do-build-ios`].

## 1-b. ⚠️ MAS A APP NÃO ESTÁ PROVADA A CORRER

Eu escrevi antes que "os fluxos correram e passaram". **Estava errado.** O passo
17 tem `continue-on-error: true` e eu li o verde do invólucro, não o resultado.

O que o log diz mesmo: **`+0 -7` — todos os 7 testes falharam.** E a captura
final (`ecra-final.png`, 1320×2868) é **o ecrã inicial do simulador**, não a app.

**Compilar não é correr. Não há prova de que a app arranca no iPhone.**

### Causa, medida no log

```
'_pendingFrame == null': is not true   (LiveTestWidgetsFlutterBinding.postTest)
'!inTest': is not true                 (LiveTestWidgetsFlutterBinding.runTest)
```

`integration_test/e2e_test.dart` chama `app.main()`, que arranca a app inteira —
Supabase, Firebase, Stripe, foreground service e os `Timer.periodic` do
`OrderStore` e do heartbeat. Com temporizadores permanentes, `pumpAndSettle`
nunca assenta; o binding acaba com um frame pendente e o **primeiro teste
envenena todos os seguintes**. Não é problema de iOS — os testes chamam-se
"Bora E2E **Web**" e nunca foram feitos para isto.

### O caminho decidido (não voltar a discutir)

**Não** tentar arranjar o `e2e_test.dart`. Criar um arnês próprio:

- `lib/main_capturas.dart` — entrypoint separado que desenha **cada ecrã alvo
  directamente**, com dados sem rede: sem `Supabase.initialize`, sem Firebase,
  sem temporizadores. É isso que torna o `pumpAndSettle` determinístico.
- `integration_test/capturas_loja_test.dart` — pumpa cada ecrã e chama
  `binding.takeScreenshot('01-mercado')`, etc.
- `test_driver/capturas_driver.dart` — recebe os bytes e grava os PNG.
- No workflow: `flutter drive --driver=test_driver/capturas_driver.dart
  --target=integration_test/capturas_loja_test.dart -d "$UDID"`.

Vantagem extra: controla-se o conteúdo das capturas, e a ordem do que se vende
(mercado primeiro, sem TVDE) é imposta pelo arnês, não pelo acaso da navegação.

---

## 2. O QUE JÁ ESTÁ FEITO E PROVADO

### Eliminação de conta (era o bloqueador nº 1 — resolvido)
A Edge Function no ar era **uma página HTML**: devolvia 200 e a app dizia
"Conta apagada." sem apagar nada. RGPD a falhar em produção e reprovação certa
na 5.1.1(v). Reescrita e no ar em **v25**, `verify_jwt` ligado.

Provado com contas de teste criadas e removidas: estafeta com acerto por fechar
→ **409**; cliente sem confirmar → **200 com o valor a perder**; cliente,
estafeta e parceiro com confirmação → **200 `ok:true`, zero falhas**; nenhum
volta a entrar. Por SELECT: loja viva e desactivada, dono desligado nas duas
colunas, **zero NIF e zero IBAN**, ledger e acertos intactos, tokens consumidos
e não apagados. Detalhe em [`apagar-conta-devolve-html-e-mente`] e
[`chaves-estrangeiras-que-mordem-ao-encerrar-conta`].

### Base do projeto iOS
Bundle `com.example.boraApp` → `pt.boraapp.bora`; só iPhone; iOS 15; `Podfile`
criado (nunca existiu); `PrivacyInfo.xcprivacy` registado nas 4 secções do
pbxproj; retrato; `ITSAppUsesNonExemptEncryption=false`; esquemas de URL;
alfa do ícone removido só no iOS; Apple Pay desligado no iOS em 6 sítios;
`Stripe.urlScheme = pt.boraapp.bora` (não existia — sem ele o 3DS prende o
utilizador no Safari).

### Contas demo — são DUAS, de propósito
| Conta | Palavra-passe | Para quê |
|---|---|---|
| `demo@bora.app` | `BoraDemo2026!` | navegar — **nunca apagar** |
| `demo.apagar@bora.app` | `BoraDemo2026!` | só o teste de eliminação |

A descartável é reposta pelo cron `repor-demo-apagar` (minuto 7 de cada hora).
Ciclo provado: entra → encerra → não volta a entrar → reposta → entra.

### Caixa fechada dos pedidos demo
**O despacho corre de 15 em 15 segundos** — um pedido demo em `callingDriver`
seria oferecido a um estafeta real em segundos. O gatilho
`a_trg_pedido_demo_caixa_fechada` faz o pedido **nascer já em `driverAccepted`**
com o estafeta demo (`demo-estafeta@bora.app`, offline, Guarda), marcado teste e
em dinheiro. Nunca passa por `callingDriver`.

Provado: inseri com `status='created'`/`payment_method='card'` e saiu
`driverAccepted`/`cash`/teste com o estafeta demo. **ledger=0, transacções=0,
tokens=0, carteira=0, `callingDriver`=0, oferta=NENHUMA.** Cron
`mover-pedidos-demo` avança até `onTheWay` (nunca `delivered`, que é o que
dispara dinheiro) e cancela sem custo às 2 h. Pedido de teste removido.

### Painel admin
Ecrã "Contas encerradas" (PT-BR): data, papel, o que foi anonimizado, o que
ficou, busca e exportação CSV. Ligado ao painel.

### Coluna `platform`
`users.platform` e `orders.platform` com restrição e índice; gatilho
`trg_orders_marca_plataforma` preenche a partir de `users.platform` — escolhi o
gatilho **para não mexer na criação do pedido**, que é zona protegida. Vista
`v_pedidos_por_plataforma`. App escreve só em `users.platform`, fire-and-forget.

### Interruptor 5.2.1
`platform_settings.ios_hide_nonpartner_logos` criado **desligado**. Falta o lado
Flutter (esconder logótipo de loja não parceira quando ligado, no iOS).

### Site legal — publicado e verificado no ar
Estavam **oito** marcadores por preencher (privacidade **e** termos), não três.
Todos preenchidos: Danilo Fulfaro da Silva, empresário em nome individual,
Rua do Torreão 14, 6300-035 Guarda, NIF 322151171 (dígito de controlo validado).
Secção nova sobre eliminar a conta. DPO: explicado que não é obrigatório
(RGPD art. 37.º) em vez de inventar um nome.

**Duas armadilhas:** `git push` **não publica** este site (Cloudflare Pages é
upload directo por wrangler) — corri o `deploy-cloudflare.sh`; e
`/privacidade.html` faz **308** para `/privacidade` — é o segundo que vai para
a Apple.

Prova no ar: HTTP 200, zero marcadores, nome e NIF presentes.

### Ponte do Telegram
`orquestracao/ponte-telegram.sh`, provada com mensagem real, texto e voz.
Mensagem em base64 senão os acentos partem-se.

---

## 3. O QUE FALTA, POR ORDEM

1. **Arnês de capturas** (ver §1-b) → vídeo de 60–120 s com legendas em inglês →
   YouTube não listado no canal do Bora → guardar o link aqui.
2. Lado Flutter do `ios_hide_nonpartner_logos`.
3. Descrição, palavras-chave (100 car.), textos da loja. Ordem do que se vende:
   **mercado primeiro**, depois comida, barbearia, açaí, limpeza, favores,
   lavagem. **Sem TVDE nem carro.**
4. `ios/CHECKLIST-APPLE.md` ponto a ponto com prova.
5. **Só então** chamar o Danilo para UMA sentada de 20 min, páginas já abertas
   no Chrome e tudo preenchido menos credenciais: palavra-passe da conta Apple,
   código SMS, confirmar o formulário, pagar os 99 €, foto do cartão de cidadão
   se pedirem.
6. Depois, sozinho: chaves e certificados, APNs no Firebase, trader status
   verificado, build de release, envio, submissão.
7. Vigiar a revisão de 2 em 2 h. Recusa → responder no Resolution Center em
   menos de 2 h, com prova. **Nunca resubmeter às cegas.**

---

## 4. ESTADO DO RAMO

`ios-lancamento` publicado pela API do GitHub (o guardrail fica intacto e
continua a barrar tudo o resto). Último: `c2f54047`.
**Produção `autonomous-night-2026-04-29` intacta em `1fd3439d`** — verificado
a cada publicação.

Uma corrida nova arrancou com `c2f54047` (coluna `platform`) — ver o resultado
ao retomar.
