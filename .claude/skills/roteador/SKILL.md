---
name: roteador
description: >
  Encaminha um pedido falado do Danilo para o projeto certo, com todas as ferramentas
  disponíveis. Usa esta skill sempre que o pedido NÃO disser claramente em que pasta ou
  projeto mexer — por exemplo "vê o que falta no site do Happy", "quantas encomendas
  entraram esta semana", "arranja aquilo do clube", "o que é que o Córtex diz sobre o loop".
  Também quando a sessão está aberta na raiz do QG. NÃO usar quando o pedido já nomeia
  ficheiro ou pasta (aí vai-se direto ao trabalho).
metadata:
  versao: 1.0
  criada: 2026-08-19
---

# ROTEADOR

O Danilo fala por voz. As frases chegam partidas, com nomes próprios dele e sem caminhos.
O teu trabalho é perceber **o que ele quer** e **onde isso vive**, e começar — não devolver
perguntas.

## 1. Ler o pedido pela intenção

Voz-para-texto parte frases, troca palavras e não põe pontuação. Interpreta pela intenção,
não à letra. "vê o que ta faltando no site do happy" = "qual é o estado pendente do site do Jai".

## 2. Descobrir o projeto

**Lê sempre `C:\Users\danil\Desktop\QG\MAPA.md`.** Tem os apelidos que ele usa.

Atalhos mentais:

| Ele diz | É |
|---|---|
| "o app", "o Bora", "o delivery", "a aplicação" | `app-bora` |
| "o site do clube", "o Guarda", "o Guarda FC" | `site-guarda-fc` |
| "o site do Jai", "o site do Happy" | `site-jai` |
| "o filme", "o episódio", "o Studio" | `filme-studio` |
| "o Hermes", "a ponte", "o carteiro", "o juiz" | `orquestracao` |
| "as notas", "o vault", "o Obsidian" | `vault-obsidian` |
| "o parceiro", "a joalharia", "o kebab" | `loja-ouro-prata`, `mr-kebab` |

- **Nunca adivinhes um caminho.** Se não está no mapa, procura antes de inventar.
- **Ambíguo entre dois?** UMA pergunta curta, com as duas opções. Só uma.
- Perguntas sobre dados de negócio (encomendas, estafetas, clientes, produtos) não são
  de um projeto: vão direto ao **MCP do Supabase**.

## 3. Puxar contexto antes de agir

Antes de trabalho não-trivial:
- `cortex_buscar` / `cortex_ler` — já se decidiu isto antes? Já falhou alguma abordagem?
- **Verifica por MCP em vez de deduzir.** Ler a base de dados vale mais do que ler o código
  e supor.

## 4. Escolher o motor

O **mais barato que aguente com segurança**. Sobe para Opus ou acima sempre que toque em
dinheiro real, pagamentos, preços, comissões, carteira, dispatch ou zona protegida.

## 5. Juntar as ferramentas certas

**Estar num projeto nunca impede de usar uma ferramenta de outro.** É esta a dor que o
roteador existe para resolver.

| Tipo de trabalho | O que chamar |
|---|---|
| Decidir o que fazer, prioridades | `ceo-ai` |
| Funcionalidade nova | `spec-driven-development` → `planning-and-task-breakdown` → `incremental-implementation` → `test-driven-development` → `code-review-and-quality` → `shipping-and-launch` |
| Design de interface | `/impeccable critique`, `polish`, `adapt`, `typeset`, `delight` |
| Verificar trabalho feito | juiz (`orquestracao\hermes-bridge\juiz-go.ps1`), bot `fiscal` do Hermes |
| Segunda opinião numa decisão | `buzz`, Conselho (MCP `go_conselho`) |
| Dados, KPIs, contagens | MCP Supabase |
| Histórico e decisões | MCP Córtex |
| Pesquisa na internet | `agent-reach` |
| Campanha, marca, criativos | `diretor-criativo` |
| Limpar o PC | agente `limpeza-pc` + regras dos 3 baldes |

## 6. Anunciar e começar

**UMA linha** a dizer o que decidiste, e começa. Sem pedir aprovação.

> Exemplo: "Site do Jai (`site-jai`), estado pendente — vou ler os `MARCOS_*.md` e correr
> o detetor. Motor: o normal chega."

## 7. A barreira não tem exceções

Dinheiro real ou zona protegida → prepara tudo, **não aplica**, e escreve em português:

> ⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.**

Só avança quando ele disser "vai".

## 8. Prova material

Nada é dado por bom sem saída literal. Um `200` não prova que o trabalho por dentro correu.
Se falhou, diz-se que falhou, com o erro real.
