---
titulo: Conformidade Google Play — 3 pendências com prazo real
data: 2026-07-17
autor: executor autónomo (loop noturno)
tipo: diagnóstico + recomendação (NÃO aplicado nada de código)
---

# Conformidade Google Play — o que investiguei e o que falta fazer

Este ficheiro responde às 3 pendências levantadas em 15/07. Não mexi em nenhum
ficheiro de build, workflow ou versão — só investiguei e deixei escrito o que
fazer. Nada aqui foi aplicado.

---

## 1. Target API Level (prazo: 31 de agosto de 2026)

### O que descobri, com prova

- O CI (`build_android.yml`, linha 42-46) fixa a versão do Flutter em **3.41.2**
  (comentário no próprio ficheiro explica que é de propósito, por causa de um
  bug de login numa versão mais recente — não mexer nisto sem re-testar login).
- O `android/app/build.gradle.kts` (linha 53) tem:
  ```
  targetSdk = flutter.targetSdkVersion
  ```
  Ou seja, **não há um número fixo no projeto** — o targetSdk vem do que o
  Flutter usado no build decidir.
- Fui direto à instalação local do Flutter 3.41.2 (a mesma versão que o CI usa)
  e confirmei no código-fonte do plugin Gradle do Flutter
  (`packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt`):
  ```
  val compileSdkVersion: Int = 36
  val targetSdkVersion: Int = 36
  ```
  **O Flutter 3.41.2 gera targetSdk = 36 (Android 16) por defeito.**
- Confirmei a regra atual da Google Play (pesquisa web, 2026-07-17): a partir
  de **31 de agosto de 2026**, apps novos e atualizações têm de targetar
  **API 36 (Android 16)** ou superior. Apps já existentes só precisam de
  API 35 para continuarem visíveis a novos utilizadores em Android mais
  recente que o target. Há possibilidade de pedir extensão até 1 de novembro
  de 2026 se for preciso mais tempo.

### Conclusão

**A Bora já cumpre o requisito de 31/08/2026, sem precisar de mudar nada.**
O build atual (Flutter 3.41.2) já produz targetSdk=36, que é o mínimo exigido
a partir dessa data. Não há ação obrigatória.

### Risco a ter em conta (recomendação, não é para aplicar agora)

O targetSdk está a cumprir a regra **por acidente/herança**, não porque
alguém decidiu explicitamente "36". Se um dia o Flutter no CI for atualizado
(ou rebaixado, por outro motivo qualquer), o targetSdk muda **silenciosamente**
sem ninguém perceber, e pode deixar de cumprir a regra sem aviso.

- **Opção A (mais segura):** fixar explicitamente `targetSdk = 36` no
  `build.gradle.kts`, independente da versão do Flutter. Risco: nenhum — é
  só tornar explícito o que já está a acontecer.
- **Opção B (não fazer nada):** manter como está e confiar que ninguém troca
  a versão do Flutter no CI sem verificar o targetSdk resultante.

Não apliquei nenhuma das duas — é decisão do Danilo, e como envolve tocar o
`build.gradle.kts` que alimenta o build de produção, fica marcado como
recomendação escrita, não ação.

---

## 2. Registo de Developer (verificação de identidade)

### O que sei da conta

Segundo memória confirmada em sessões anteriores: a conta dona do Play
Console do `pt.boraapp.bora` é **boraappbora@gmail.com** (developer ID
`5372142912736686834`, "Bora App Guarda") — **não** é a conta pessoal
`nilofulfarotuga@gmail.com`.

### O que descobri sobre a exigência nova (pesquisa web, 2026-07-17)

A Google lançou, e está a expandir desde março de 2026, um programa de
**"Android developer verification"** — obrigatório para publicar/atualizar
apps no Play Console. Resumo:

- **Contas pessoais:** têm de confirmar nome legal, morada legal, email e
  telefone; em alguns casos pede documento de identidade oficial + selfie.
  A Google diz que demora de poucas horas a 2 dias úteis.
- **Contas de organização:** exigem também um **número D-U-N-S** (Dun &
  Bradstreet, 9 dígitos) — pedir este número pode demorar ~28 dias, por isso
  convém tratar disto com antecedência se a conta for de empresa.
- Taxa de registo mantém-se em $25 (pagamento único, já deve ter sido pago
  quando a conta foi criada).
- A Google diz que **98% das contas já existentes e já verificadas foram
  auto-registadas** quando o programa abriu a todos os developers em março
  de 2026 — ou seja, se a conta `boraappbora@gmail.com` já estava verificada
  (com identidade confirmada) antes disso, é provável que já esteja OK
  automaticamente.

### O que NÃO consigo confirmar daqui

Não encontrei, nem no Cérebro nem no repositório, nenhuma nota anterior sobre
se esta verificação de identidade específica (documento/selfie ou D-U-N-S) já
foi feita na conta `boraappbora@gmail.com`. **Isto só é visível fazendo login
no Play Console com essa conta** — não há endpoint de API para consultar o
estado de verificação de identidade.

### Passos para o Danilo (simples, numerados)

1. Entrar no browser com o perfil/conta **boraappbora@gmail.com** (é a conta
   dona, não a pessoal — ver nota da sessão de 2026-07-06 onde a conta errada
   mostrou um ecrã enganador de "novo registo").
2. Ir a `play.google.com/console` → menu de definições/conta → procurar por
   algo como "Verificação de developer" ou "Identity verification" /
   "Developer account status".
3. Se aparecer um aviso a pedir para submeter documento de identidade ou
   selfie: fazer isso o quanto antes (não é decisão técnica, é só burocracia
   da conta) — não há problema em fazer sozinho, não mexe em código nem em
   dinheiro.
4. Se a conta for tratada pela Google como "organização" em vez de "pessoa
   individual", vai pedir um D-U-N-S — nesse caso, começar o pedido do D-U-N-S
   já (demora semanas), mesmo antes de a Google obrigar.
5. Se não aparecer nenhum aviso e o estado disser "Verificado" ou
   "Verification complete" — não é preciso fazer mais nada, a conta já está
   coberta pelos 98% auto-registados.

---

## 3. Data Safety / Localização

### O que o AndroidManifest.xml pede, de facto (confirmado por leitura direta)

```
ACCESS_FINE_LOCATION        — localização precisa (GPS)
ACCESS_COARSE_LOCATION       — localização aproximada
ACCESS_BACKGROUND_LOCATION   — localização em segundo plano (app minimizada)
FOREGROUND_SERVICE_LOCATION  — serviço em primeiro plano para tracking de GPS
```

O comentário no próprio manifesto (linha 4) confirma a intenção: "lets GPS
stream survive when the app is minimised" — usado para o motorista/estafeta
TVDE e delivery continuarem a partilhar localização com o cliente e o
dispatch mesmo com a app em segundo plano.

### O que NÃO consigo confirmar daqui

Não tenho acesso ao Play Console (não há login/browser neste ambiente
headless), por isso **não sei o que está atualmente escrito na secção
"Data Safety" / "Segurança dos dados"** do Console. Só o Danilo, com login,
consegue ver e comparar com o texto abaixo.

### Texto pronto a copiar para a secção Data Safety (localização)

Google Play separa "Localização aproximada" de "Localização precisa", e
pergunta se é recolhida, se é partilhada, e se é opcional. Como a Bora usa
ambas E usa em segundo plano, a declaração correta é:

> **Tipo de dado:** Localização (aproximada e precisa)
>
> **É recolhida?** Sim
> **É partilhada com terceiros?** Não (fica interna à plataforma Bora —
> visível apenas ao cliente que acompanha a entrega/corrida em curso e ao
> motor de despacho, para efeitos operacionais)
> **É opcional ou obrigatória?** Obrigatória para quem usa o papel de
> estafeta/motorista (sem localização não é possível receber/entregar
> pedidos nem cumprir corridas TVDE). Para o cliente é usada apenas para
> definir o endereço de entrega/recolha.
> **Finalidade declarada:** "Funcionalidade da app" (App functionality) —
> localização usada para: (1) encontrar o estafeta/motorista mais próximo do
> pedido/corrida, (2) mostrar ao cliente em tempo real onde está a
> entrega/motorista, (3) confirmar chegada ao ponto de recolha/entrega,
> (4) TVDE — seguir o trajeto da corrida contratada.
>
> **Porque é recolhida em segundo plano (background):** para que o
> estafeta/motorista continue a partilhar a localização com o cliente e o
> sistema de despacho mesmo quando a app está minimizada durante uma
> entrega ou corrida em curso — sem isto, o GPS para assim que o ecrã é
> bloqueado e o cliente perde o acompanhamento em tempo real.
>
> **Pode ser apagada?** Sim, dados de localização histórica associados a
> pedidos/corridas seguem a política de retenção geral da conta; o
> utilizador pode pedir eliminação de conta (GDPR).

---

## Resumo executivo

| Pendência | Estado | Ação necessária |
|---|---|---|
| Target API Level (31/08/2026) | ✅ Já cumpre (targetSdk=36 via Flutter 3.41.2) | Nenhuma obrigatória. Recomendo fixar explicitamente no futuro (não aplicado) |
| Registo/verificação de developer | ⚠️ Estado desconhecido — só visível com login | Danilo verificar no Console com a conta `boraappbora@gmail.com` (5 passos acima) |
| Data Safety / Localização | ⚠️ Permissões confirmadas no código; declaração no Console não verificável daqui | Danilo comparar o texto pronto acima com o que está declarado no Console |

Nenhum ficheiro de build, workflow, gradle ou versão foi alterado nesta
tarefa — só diagnóstico e recomendação escrita, como pedido.
