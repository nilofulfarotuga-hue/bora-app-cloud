# Relatório — Testadores do Teste Interno — 30/07/2026

Play Console → Testar e lançar → Testar → **Testes internos** → separador **Testadores**
(`.../app/4974665836977103534/tracks/internal-testing?tab=testers`)

## 1. Listas de testadores encontradas — DUAS

| Lista | Utilizadores | Selecionada para o Teste Interno |
|---|---|---|
| `testadores bora` | 6 | ✅ sim |
| `Danilo - teste interno` | 1 | ✅ sim (**criada agora**) |

Conteúdo de **`testadores bora`** (os 6, lidos um a um):
`eulineyafonsofernandes@gmail.com` · `fulfarodanilo@gmail.com` ·
`leticia.cosmo0397@gmail.com` · `nilofulfaro@gmail.com` ·
`nilofulfarotuga@gmail.com` · `valdemirvasconcelos28@gmail.com`

## 2. `boraappbora@gmail.com` — NÃO estava; foi ADICIONADO agora

Não constava de nenhuma das listas. Como é a conta do Play Console (dona da app),
não entra automaticamente como testador — por isso o telemóvel nunca via update.

Feito: criada a lista **`Danilo - teste interno`** com `boraappbora@gmail.com`,
associada à faixa e **guardada**. Prova: ao recarregar a página, as duas listas
aparecem com a checkbox ✅ e o botão **Guardar está desativado** (= sem alterações
pendentes, estado persistido).

Nada foi removido — `testadores bora` continua intacta e selecionada.

## 3. Link de adesão (opt-in) do Teste Interno

```
https://play.google.com/apps/internaltest/4701744587266345232
```

Abrir esse link no telemóvel com sessão iniciada em `boraappbora@gmail.com`
→ **"Tornar-me testador"** → depois **"Transferir na Google Play"**.

## 4. Estado da faixa (Play Developer API, mesma hora)

| Track | versionCode |
|---|---|
| production | 501 (rejeitado) |
| alpha | **504** |
| **internal** | **504** ← já lá está, faixa **Ativa** |
| beta | 382 |

O arranjo `tracks: alpha,internal` no CI (commit `f68ca4c`) confirmou-se: o build
novo (504) entrou sozinho nas duas faixas.

## Notas de execução
- A extensão do Chrome recuperou o acesso a `play.google.com` a meio da sessão —
  daí ter sido possível fazer o que na tarefa anterior estava bloqueado.
- **Armadilha:** `get_page_text` / `innerText` **não veem** a tabela de listas
  (a Play Console é AngularDart compilado, `main.dart.js`). Levou-me a concluir
  "zero listas" — errado. **Só o screenshot mostra a verdade** nesta página.
- Não toquei em Produção, no lançamento pendente de vídeo, em preços, IAP,
  contas de programador nem dados bancários.
