---
titulo: Fix — campo Categoria em falta no form de produto do parceiro (Bug 1)
data: 2026-07-17
estado: aplicado
---

# Contexto

Ordem anterior (`ordem-20260717181727-94b1`) esgotou 3 tentativas com
saída vazia por juntar demais numa tarefa só (Bug 1 + Bug 2 + botão admin)
para o orçamento de 900s do executor. Esta ordem reduziu ao mínimo: **só
o Bug 1**, sozinho.

Bug confirmado por prova: produtos criados por parceiros ficavam sempre
com `products.category = NULL` (SQL), e `add_product_screen.dart` não
tinha nenhuma ocorrência de "categor" (grep).

Ao investigar encontrei os 4 ficheiros-alvo **já modificados no working
tree** (não commitados) com exatamente a implementação pedida — resultado
de uma execução concorrente anterior no mesmo diretório partilhado do
loop autónomo. Verifiquei o diff linha a linha contra a spec, confirmei
que o model `PartnerProduct` já tinha `category`/`copyWith` prontos, corri
`flutter analyze` sobre os 5 ficheiros envolvidos e só deu 1 aviso `info`
pré-existente (deprecated `value:` do `DropdownButtonFormField`, padrão
usado em 44 outros pontos do código — não é regressão introduzida aqui,
não mexi por ser fora do escopo).

# O que foi feito

1. **`lib/screens/add_product_screen.dart`** — campo "Categoria" logo
   após o Preço: dropdown com as categorias distintas já usadas pela loja
   (`productsForRestaurant`) + opção "+ Criar nova categoria" (abre campo
   livre); se a loja não tiver nenhuma categoria ainda, mostra o campo
   livre direto. Obrigatório (bloqueia submit com snackbar se vazio),
   trim aplicado, texto em PT-PT.
2. **`lib/stores/partner_product_store.dart`** — `addProduct()` (`required
   String category`) e `updateProduct()` (`String? category`) passam o
   valor ao `RestaurantStore`.
3. **`lib/stores/restaurant_store.dart`** — `addPartnerProduct()` e
   `updatePartnerProduct()` aceitam `category` e agora incluem
   `'category': product.category` no insert/update para `products` (era
   o que faltava — causa raiz do bug).
4. **`lib/screens/partner_products_screen.dart`** — lista de produtos do
   parceiro mostra "Categoria: X" (ou "Sem categoria" em itálico para
   produtos antigos) + botão de edição rápida para corrigir produtos
   criados antes deste fix.

Não toquei em `restaurant_options_screen.dart`, `register_partner_screen.dart`
nem `admin_partner_detail_screen.dart`, nem em pricing/dispatch/tokens/Stripe/RLS,
conforme pedido.

# Validação

- `flutter analyze` sobre os 5 ficheiros envolvidos: **0 erros**, 1 info
  pré-existente (ver acima).
- Commit isolado só destes 4 ficheiros (não arrastei os outros ficheiros
  já modificados no working tree por outras tarefas concorrentes —
  `git add` explícito por nome, não `-A`).

# Commit

```
71bdbc6 fix(parceiro): campo Categoria em falta no form de produto (Bug 1)
```

(rebased sobre `72d90f6` por divergência concorrente no push — sem
`--force`, `pull --rebase --autostash`). Push confirmado em
`autonomous-night-2026-04-29` → `72d90f6..71bdbc6`.

# Pendente (fora do escopo desta ordem, para ordem separada)

- Bug 2 (cartões)
- Botão/paridade no admin para categoria de produto do parceiro
