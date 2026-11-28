⚠️ MODO PROTECÇÃO TOTAL ⚠️

# Missão varrer-pendentes-2026-11-28 — terminar tudo o que ficou por juntar

MOTOR: Opus 5.5 · PORTA: uma só — esta sessão na nuvem (claude.ai/code, repo
nilofulfarotuga-hue/bora-app-cloud). O PC do Danilo fica de fora: está sem RAM
e já tem a missão da limpeza a correr.

Entra pelo orquestrador CEO-AI (`.claude/skills/ceo-ai/`) e segue
`protocolo-missao-bora` e `modo-automatico`. Lê antes: `AGENTS.md`, `CLAUDE.md`,
`PADRAO_BORA.md`, e no livro (claude_ai_memoria) `erros-aprendidos` e
`regras-do-danilo`.

## Porquê

Ordem do Danilo (28/11/2026 14:14): "retomar todas as missões que tá por
terminar, tem que terminar tudo". A Claude.ai encontrou 15 pedidos de revisão
abertos (#5 a #44) e mais ~23 ramos `ai/` com código que nunca foi juntado ao
`autonomous-night-2026-04-29`. Em vários a parte do servidor JÁ está aplicada
em produção mas a app nunca recebeu o código — a funcionalidade está a meio.

Aplicado em produção (confirmado por SELECT em schema_migrations), app por
juntar: #33 busca_leve (tabelas, pesquisa, 3 letras), #37 selos_novo e
novidades_farmacia, #38 redes_comunidade_24h, #39 farmacia_peca_aqui,
#44 jai_robo_portas, #20 editar_perfil_cliente e robos_livro_publico.
NÃO aplicado: #32 quando_chamar_estafeta, #34 receita_cartao_mbway,
#35 lupa_sugestoes e pesquisa_dono, #33/#35 vigia_servidor_portugues,
#41 painel_aprovacoes_excecao_e_pedir_docs, #20 conteudo_ia_fila.

## O que mexe

Só código que já existe nesses ramos/pedidos, portado para a linha principal
de hoje. Nada de funcionalidades novas. Lista completa:

Pedidos abertos: #5 docs paridade · #6 modo automático seguro · #7 M8 (6
missões de 08/11) · #20 manhã 15/11 (MB WAY sem cobrança a dobrar, nome pelo
suporte, robôs) · #21 artes farmácias v2 · #32 quando chamar o estafeta ·
#33 busca leve · #34 receita cartão e MB Way · #35 lupa sugestões · #37 selo
"Novo" · #38 comunidade 24h · #39 farmácia peça aqui · #41 botões do painel de
aprovações · #43 Hermes diretor parte 2 · #44 robô do Jai.

Ramos sem pedido: m1-dinheiro-favores, m2-estafeta-conta-fila,
m3-dipsy-acesso-total, m6-crescimento, m7-stripe-parceiros-radar-leis,
m10-publicar, m10-radar (todos 2026-11-08), 11-amigo-casa,
11-meta-grupos-casa-amigo, 15-devocional-en-es, 15-devocional-lucia,
15-produtos-celeste-tonico, 15-reservas, 16-a3-cor-viva, 16-dinheiro-dividido,
17-loja-casa-cozinha, 17-painel-telefone-topo, 18-loja-acessorios-telemovel,
22-licoes-amigo-ar, 22-licoes-suporte-ar, 23-radar-fila (prefixo
`ai/2026-11-`). Os ramos 15-checkup, 17-impressao-foto e 26-voz-central-sipuri
já tiveram pedido juntado: confirma só se ficou algo de fora.

NÃO mexer: os pedidos #55 (home categorias) e #56 (telefone e morada) e o ramo
da limpeza (ai/2026-11-28-limpeza-planos*): são da Claude.ai e do PC.

## Blocos

B0 · Inventário. Para cada pedido/ramo: o que faz, se já entrou por outro
caminho (compara o conteúdo dos ficheiros com a linha principal, não o
histórico), se o servidor dele está aplicado (SELECT em
supabase_migrations.schema_migrations por nome), se toca zona vermelha.
Escreve a tabela em `docs/missoes/varrer-pendentes-2026-11-28-inventario.md`
e no e2e_log (fluxo `varrer-pendentes-2026-11-28`, passo `B0`).

B1 · Decidir cada um, pela regra:
- já está tudo na linha principal ou foi substituído por coisa mais nova →
  fechar o pedido com um comentário curto a dizer onde está; apagar nada.
- só documentos, relatórios ou scripts da VPS (#5, #38, #43, #44, devocionais,
  lições, radar) → juntar num pedido só de documentos (`[skip ci]` só se
  nenhum ficheiro de `lib/`, `test/` ou `supabase/` viajar).
- código da app que falta e cujo servidor já está em produção (#33, #37, #39,
  e o que mais aparecer) → portar primeiro, é o mais urgente (a funcionalidade
  está a meio).
- código da app com servidor por aplicar e fora da zona vermelha (#35, #41,
  #32 se não tocar no dispatch) → portar com a migração no repo; aplicar a
  migração por MCP e provar por SELECT.
- ZONA VERMELHA (dinheiro, Stripe, MB WAY, tokens, carteira, finalizePurchase,
  dispatch_engine, pricing_service.dart, RLS de orders/wallets/ledger): #20
  (MB WAY), #34 (receita cartão e MB Way), m1-dinheiro-favores,
  m7-stripe-parceiros, 16-dinheiro-dividido, e #32 se tocar no dispatch →
  NÃO aplicar. Prepara o pedido de revisão pronto e escreve no relatório:
  "⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu
  aplico." Só com o "autorizo" do Danilo.
- se o Danilo já desistiu da ideia (procura no livro, no Córtex e no
  e2e_log) → fechar com o motivo.

B2 · Portar. Ramo novo `ai/2026-11-28-pendentes-app` a partir da linha
principal de HOJE. Traz o código de cada pedido escolhido em B1, resolve os
conflitos a favor do que está hoje na linha principal (nunca partir o que
funciona; o código de hoje tem 10 dias de correções). Um commit por pedido
portado, com o número do pedido na mensagem.

B3 · Provas. `flutter analyze` 0 erros, `flutter test` verde,
`python .claude/juiz/anti_trapaca.py` limpo. Teste vermelho = encontrar a
causa e corrigir, nunca saltar nem enfraquecer o teste. Paridade admin: cada
funcionalidade portada tem o seu ecrã no painel (PT-BR).

B4 · Publicar. Pedido de revisão do ramo B2 → testes verdes →
`node .claude/tools/publicar/publicar-pedido.mjs <número> --repo nilofulfarotuga-hue/bora-app-cloud`
→ conferir Android, iPhone e web. Fechar os pedidos antigos que ficaram dentro
deste, com o número do novo.

B5 · Fecho. Relatório curto em português simples (fiz isto, falta isto),
`digest-2026-11-28-varrer-pendentes` em claude_ai_memoria, e2e_log passo
`B5-fecho`.

## Regras

- Tarefa autorizada pelo Danilo: executar ponta a ponta, sem perguntar.
  Única travagem: dinheiro (acima).
- Erro encontrado pelo caminho fora desta lista: REPORTAR no e2e_log e no
  relatório, não corrigir calado.
- Não apagar dados de produção nem ramos. Não fazer UPDATE/INSERT/DELETE
  direto em orders, drivers, carteiras, ledger, tokens.
- `git add` por caminho. Nunca mexer no versionCode nem no pubspec version.
- Classificador ou tranca negou uma ação: registar em `docs/TRANCAS.md`,
  saltar e continuar.
- Commits terminam com:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

No fim: /ctx doctor e /ctx stats (se existirem nesta sessão).
