# Teste Aberto (Open Testing) — Bora App `pt.boraapp.bora`

> Objetivo: **um link único** que a família (Brasil) e qualquer pessoa possa abrir, aceitar
> participar e instalar — **sem** cadastrar o email de cada testador.
> Isso é o **Teste Aberto (Open Testing)** do Google Play.

**Data do diagnóstico:** 2026-07-06 · Conta Play Console: BoraApp (dev ID `5372142912736686834`)
· Service account usado: `codemagic-google-play@boraapp-d2bea.iam.gserviceaccount.com`

---

## 🔗 O LINK (para mandar à família)

```
https://play.google.com/apps/testing/pt.boraapp.bora
```

⚠️ **Este link só fica ATIVO depois de concluíres o passo-a-passo abaixo** (ativar o Teste Aberto
no Console + revisão do Google). Enquanto o Teste Aberto não estiver publicado e aprovado, o link
dá "página não encontrada". Depois de aprovado: qualquer pessoa abre → "Tornar-me testador" →
instala pela Play Store normal. **Não é preciso adicionar emails.**

---

## 📊 Estado atual (lido via Play Developer API, 2026-07-06)

| Track | = no Console | Release atual | Ação |
|---|---|---|---|
| `production` | Produção | *(vazia)* | — |
| `beta` | **Teste Aberto** | **VAZIA — é o que falta ativar** | ⬅️ este documento |
| `alpha` | **Teste Fechado** | `309 (1.0.1)` | 🚫 **NÃO TOCAR** (histórico de testadores) |
| `internal` | Teste Interno | `1.0.1 (367)` | — |

**AABs já enviados (prontos a usar):** `309, 363, 364, 365, 366, 367`. O mais recente é o **367**.
Recomendado para o Teste Aberto: **367** (ou 366 — são builds consecutivos do CI, praticamente iguais).

---

## ❓ Porque é que isto não foi feito automaticamente por API

Tentei publicar via Play Developer API (com a credencial do service account do Codemagic, sem pedir
login). **A API e a credencial funcionam** — prova: consigo ler todas as tracks e consigo escrever
na track `alpha` (devolveu `200 OK` num teste de controlo, que **não** cheguei a publicar).

Mas **toda** tentativa de pôr um build na track `beta` (Teste Aberto) devolve:

```
400 FAILED_PRECONDITION — "Precondition check failed."
```

Isto acontece com **qualquer** build (365/366/367), em `draft` ou `completed`. Ou seja: o problema
**não** é o build nem a credencial — é que **o Teste Aberto nunca foi ativado neste app**. O Teste
Aberto tem requisitos de primeira-ativação (selecionar **países/regiões** e completar as declarações
de **"Conteúdo da app"**) que o Teste Interno e o Teste Fechado não exigem. **Esses passos só
existem na interface do Play Console** — a API não tem endpoint para os fazer.

> ✅ **Boa notícia:** depois de fazeres a ativação **uma vez** (passos abaixo), os **próximos**
> builds podem ir para o Teste Aberto automaticamente pelo CI/API — nunca mais é preciso repetir isto.

---

## ✅ Passo-a-passo EXATO no Play Console (uma vez só)

Abre o Play Console → escolhe a conta **BoraApp** → escolhe a app **Bora**.
(Os nomes dos menus podem variar ligeiramente; indico também a função.)

### A. Completar "Conteúdo da app" (Política) — o que costuma faltar
Menu esquerdo → **Política** (ou *Policy and programs*) → **Conteúdo da app** (*App content*).
Completa **tudo o que estiver com ⚠️/"Ação necessária"**, tipicamente:
- **Política de privacidade** (URL)
- **Acesso à app** (se precisa de login para tudo → indicar credenciais de teste)
- **Anúncios** (tem/não tem)
- **Classificação de conteúdo** (questionário IARC)
- **Público-alvo e conteúdo** (faixas etárias)
- **Segurança dos dados** (*Data safety* — que dados recolhe/partilha)
- Declarações extra se aplicável (apps financeiras, saúde, etc.)

> O Teste Aberto é público, por isso o Google **exige** estas declarações completas — é a causa
> mais provável do `FAILED_PRECONDITION`. O Teste Interno não as exige, por isso o interno já funciona.

### B. Ativar o Teste Aberto + escolher países
Menu → **Testar e publicar** → **Testes** → **Teste aberto** (*Open testing*).
1. Separador **Países / regiões** → **Adicionar países / regiões** → seleciona **Brasil** e **Portugal**
   (adiciona os que quiseres; para "qualquer pessoa no mundo" seleciona todos) → **Guardar**.
2. Separador **Testadores** → confirma que o modo é **Teste aberto** ("qualquer pessoa pode aderir").
   É aqui que aparece a **URL de adesão** (o link acima).

### C. Criar a release com o build 367
Ainda em **Teste aberto** → botão **Criar nova versão** (*Create new release*).
1. **App bundles** → **Adicionar da biblioteca** → escolhe o **versionCode 367** (`1.0.1`).
   *(Não faças upload novo — já está na biblioteca. Não mexas no versionCode, é do CI.)*
2. **Nome da versão:** `1.0.1 (367) — Teste Aberto`
3. **Notas da versão** (idioma `pt-PT`):
   `Teste aberto do Bora App. Obrigado por ajudar a testar! Instala pelo link, cria conta e experimenta os pedidos.`
4. **Seguinte** → **Guardar** → **Rever versão** → **Iniciar lançamento para Teste aberto** (100%).

### D. Aguardar revisão do Google
A **primeira** publicação em Teste Aberto passa por revisão do Google (de algumas horas a ~1–2 dias).
Enquanto estiver "Em revisão", o link ainda não instala. Quando ficar "Disponível", o link fica vivo.

---

## 👨‍👩‍👧 Como convidar a família (depois de "Disponível")

Manda **só isto** por WhatsApp:

> Instala o Bora App:
> 1. Abre este link no telemóvel Android: **https://play.google.com/apps/testing/pt.boraapp.bora**
> 2. Toca em **"Tornar-me testador" / "Become a tester"**
> 3. Toca em **"Descarregar na Google Play"** e instala normalmente.

Não é preciso mandar-me o teu email nem cadastrar ninguém. Qualquer pessoa com o link consegue.

---

## 🚫 O que NÃO mexer
- **Teste Fechado (`alpha`, build 309):** deixar como está — preserva o histórico de testadores.
- **versionCode:** é auto-incrementado pelo CI (GitHub Actions). Nunca editar à mão.
- O bloco `google_play` do `codemagic.yaml` está **desativado** de propósito (publicação é pelo
  GitHub Actions, track `internal`). Não reativar sem querer duplo-publish.

---

## 🤖 Nota técnica (para quando o Teste Aberto já estiver ativo)
Depois do passo B/C feito uma vez, promover futuros builds ao Teste Aberto é 100% automatizável
via Play Developer API (`edits.tracks.update` na track `beta`, `status: completed`) com a mesma
credencial do service account. Só a **primeira ativação** (países + Conteúdo da app) é manual.
