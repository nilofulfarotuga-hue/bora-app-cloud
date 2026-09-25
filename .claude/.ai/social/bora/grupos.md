# Grupos de Facebook da Guarda e região — folha de trabalho
> Escrito 2026-09-02, missão `tudo-02-09`, bloco B5.
> Destino final na VPS: `/opt/data/social/grupos.md`.
> **Isto NÃO é API.** É trabalho com o perfil pessoal do Danilo, à mão do agente
> de clique, com um tecto de **5 grupos por dia**.

---

## ⚠️ Estado honesto desta folha

**Os números de membros estão por preencher, e isso é de propósito.**
O Facebook não tem sessão iniciada neste Chrome. Sem sessão não se vê o número
de membros nem a regra de publicação de um grupo — só o nome. Inventar esses
números seria pior do que não os ter, porque a decisão de onde publicar seria
tomada em cima de dados falsos.

Assim que o Danilo iniciar sessão, a folha preenche-se sozinha pelo método
abaixo, e só depois é que se entra em algum grupo.

---

## Método de recolha (para correr assim que houver sessão)

1. Abrir `https://www.facebook.com/search/groups/?q=<termo>` para cada termo da
   lista de pesquisa.
2. Por cada resultado, registar: **nome**, **link**, **nº de membros**,
   **público ou privado**, e **se aceita publicações de terceiros** (vê-se nas
   regras do grupo ou no aviso de moderação).
3. Ordenar por número de membros, do maior para o menor.
4. Entrar no máximo em **5 por dia**, começando pelos maiores que aceitem
   publicações.

### Termos de pesquisa
| # | Termo | Porquê |
|---|---|---|
| 1 | `compra e venda Guarda` | o maior tipo de grupo local, e o mais tolerante a anúncios |
| 2 | `Guarda Portugal` | grupos gerais da cidade |
| 3 | `brasileiros na Guarda` | comunidade grande, e o Bora fala PT-BR e PT-PT |
| 4 | `empregos Guarda` | público que procura trabalho — serve para estafetas |
| 5 | `mães da Guarda` | quem usa entregas ao domicílio com mais frequência |
| 6 | `IPG Instituto Politécnico da Guarda` | estudantes, o público mais fácil de trazer para uma app |
| 7 | `Guarda classificados` | variante do 1 |
| 8 | `Covilhã compra e venda` | região, para a segunda vaga |
| 9 | `Seia Gouveia Manteigas` | região, para a segunda vaga |

---

## Tabela a preencher

| Grupo | Link | Membros | Público/Privado | Aceita publicações? | Entrado em | Notas |
|---|---|---|---|---|---|---|
| _(por preencher — precisa de sessão)_ | | | | | | |

---

## Regras desta operação

- **Máximo 5 grupos por dia.** Entrar em muitos de uma vez num perfil pessoal é
  a receita conhecida para o Facebook marcar a conta.
- **Não se publica nada nos grupos nesta ordem.** A ordem diz explicitamente que
  publicar fica para a ordem seguinte, e só depois de o Danilo aprovar os 3
  textos.
- **Nada de extensões de automação.** A "Pulso Social" e parecidas estão fora:
  automatizar o Facebook com extensão é o caminho mais rápido para perder a
  conta pessoal do Danilo. Da ideia dela só se aproveita uma coisa, que é boa:
  **3 imagens + 3 textos, um par por grupo**, para não aparecer a mesma
  publicação repetida em grupos que partilham membros.
- Quando chegar a hora de publicar, um par diferente por grupo, e nunca dois
  grupos no mesmo minuto.

---

## O que já está pronto para quando chegar essa hora

- 7 temas × 3 textos em PT-PT, todos com o código BEMVINDO e o link da Play
  Store: `.claude/.ai/social/bora/textos-pt-pt.md`
- Capa e foto de perfil montadas só com material real:
  `.claude/.ai/social/bora/capa-facebook-1920x1080.jpg` e `perfil-1024x1024.jpg`
