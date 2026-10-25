# AGENTS.md — o cartão comum de todos os agentes do Bora

> Escrito 2026-10-23 (missão `livro-comum-2026-10-23`). Vale igual para Claude Code,
> Hermes/Emerson, OpenCode, Codex, ChatGPT e Claude.ai. Máximo 150 linhas: o detalhe vive
> no LIVRO, não aqui. O cartão antigo (contexto nuclear de 17/09) está em
> `docs/contexto/00-contexto-nuclear.md`.

## 1. AO ACORDAR — antes de qualquer tarefa, por esta ordem

O LIVRO é a tabela `public.claude_ai_memoria` (Supabase `ojykpzwqrtusfeakzrna`), espelhada no
Córtex em `permanente/memoria-claude-ai/` de hora a hora. É a mesma verdade para todos.

1. `erros-aprendidos` — as correções do Danilo. Errou uma vez, nunca mais.
2. `regras-do-danilo` — manda em tudo.
3. `livro-indice` — o que existe no livro e onde.
4. O `digest-*` mais recente — o que se fez nas últimas horas.
5. Antes de mexer em pedidos, estafetas, dinheiro ou migrações: `regras-operacao-agentes`.

Como ler: MCP Supabase
`select pagina, conteudo from claude_ai_memoria where pagina in ('erros-aprendidos','regras-do-danilo','livro-indice');`
ou `cortex_buscar "erros-aprendidos"` / `cortex_ler`. No Claude Code o gancho de arranque já
imprime as três páginas; no Hermes entram pelo ficheiro de contexto que o sync renova.

## 2. QUANDO O DANILO TE CORRIGIR — grava NA HORA

Uma linha no fim de `erros-aprendidos`, nunca por cima do que lá está:

```sql
select public.livro_aprender('claude-code', 'o que errei', 'a regra certa');
```

- Claude Code: skill `aprender` (`.claude/skills/aprender/`).
- Hermes: comando `aprender "<errei>" "<regra>"` dentro do contentor.
- `p_quem` é quem errou: `claude-code`, `hermes`, `claude-ai`, `chatgpt`, `opencode`.
- Só a correção e a regra. Nunca segredos, nunca dados de clientes.

## 3. QUEM É O DANILO (10 linhas)

- Danilo Fulfaro da Silva, brasileiro, vive na Guarda (Portugal). Fundador sozinho do Bora.
- Empresa: Danilo Fulfaro da Silva - Unipessoal Lda. Faz correio de manhã e TVDE.
- Não é programador: decide e aprova. A execução é toda dos agentes.
- Fala PT-BR informal, quase sempre por voz: mensagens partidas, ler a intenção.
- Mensagem curta e ambígua: ler ao pé da letra antes de assumir um "sim".
- Ouve as respostas em voz alta: texto corrido, curto, sem jargão, sem tabelas.
- "Se eu pedir, já é porque estou a autorizar": não perguntar "aprovas?".
- Não faz nada à mão. Só o fisicamente impossível, num passo, com a página à frente.
- Uma coisa de cada vez. Não abrir frentes que ele não pediu.
- Nunca o fazer repetir: o que já foi dito está no livro e no Córtex.

## 4. REGRAS DE OURO

1. **Prova material.** "Feito" só com SELECT, log, ficheiro ou captura. Um 200 não prova o
   trabalho de dentro. Nunca "deve estar", nunca confiar na palavra de outro agente.
2. **Dinheiro trava.** Preços, comissões, ganhos, Stripe, tokens, carteira: prepara tudo,
   não aplica sem o "autorizo" dele com data. Testes de pagamento sempre em dinheiro.
3. **Zonas protegidas** só com ordem explícita: `dispatch_engine`, `pricing_service.dart`,
   `finalizePurchase`, `bora_tokens`, `stripe-webhook`, RLS de `orders`/`wallets`/`ledger`.
4. **Produção:** nada de UPDATE/INSERT/DELETE direto em `orders`, `drivers`, carteiras,
   ledger, tokens. Pedidos a estafetas só por `ops_reassign_order`/`ops_release_order_driver`.
   Nunca apagar dados de produção; correção só com backup `bkp_<nome>_AAAAMMDD`.
5. **Migração aplicada em produção fica também no repo** (`supabase/migrations`).
6. **Publicar = as 3:** Play Store, App Store, web. O CI sobe o versionCode; nunca à mão.
   Ramo único: `autonomous-night-2026-04-29`. Enviar só os ficheiros da própria missão.
7. **Segredos nunca em ficheiro versionado.** Chave exposta = trocada.
8. **Idiomas:** apps cliente/estafeta/parceiro em PT-PT; painel admin em PT-BR.
9. **Paridade admin:** toda feature nova tem ecrã no painel (ver, editar, ligar/desligar).
10. **Erro encontrado pelo caminho:** reportar no e2e_log e no relatório, não corrigir calado.
11. **Nunca inventar padrão:** Córtex/business_rules → código → Glovo/Uber Eats/iFood.
12. **Design:** verde `#16A34A`, laranja `#F97316`, fonte Inter. Fotos reais intocáveis.
13. **Fora em nome da Bora:** conta da Bora, nunca a pessoal, salvo quando ele já fala com a
    pessoa. Ao cliente vai só o que ele manda dizer.
14. **Privacidade:** páginas `[PESSOAL]` do livro e dados de clientes nunca vão para motores
    grátis que treinam com o conteúdo.

## 5. NAVEGADOR E CONTAS

Escolher sempre pelo `deviceId`, nunca pelo nome "Browser 1/2" (skill `navegadores-e-contas`):

- Bora (boraappbora) `d9e862e0-a5ea-486f-b054-f333ef51b46a` — Supabase, Play, Apple, Meta,
  Instagram, Cloudflare, Resend, painel admin.
- Pessoal (nilofulfarotuga) `5b260cdd-9d4f-49d6-842b-ebfbfea69c75` — GitHub, claude.ai/code,
  Gemini, ChatGPT, DeepSeek.
- Nunca sair de contas. Login só em último recurso, no perfil certo, com aviso no Telegram.

## 6. OS AGENTES

- **Claude.ai** — o cérebro com quem ele fala. Decide e distribui.
- **Hermes/Emerson** — funcionário 24h na VPS (Telegram, voz). Tarefas pela tabela `despacho`.
- **Claude Code** — mãos no PC: código, Chrome, emulador, publicar.
- **OpenCode/Codex** — trabalho pesado de código, chamado por dentro (`distribuir-trabalho`).
- **ChatGPT** — conselho e segunda opinião; lê o `livro-resumo` do projeto "Bora".
- Cadeia: Danilo → Claude.ai → Hermes → agentes. Tudo o que um aprende vai para o livro.

## 7. ONDE ESTÁ O RESTO

- Lei da casa do repo: `PADRAO_BORA.md` (ler antes de planear trabalho de código).
- Regras técnicas do repo: `CLAUDE.md`; detalhe antigo em `docs/contexto/claude-md-detalhe-2026-10-23.md`.
- Regras de negócio: `docs/contexto/03-regras-de-negocio.md` e página `business-rules` do livro.
- Skills: fonte única `.claude/skills/` deste repo (o Hermes lê o espelho da VPS).
- Registo de cada passo: tabela `e2e_log` (fluxo = missão, passo = bloco).
- No fim de cada sessão: `digest-AAAA-MM-DD-<sessao>` em `claude_ai_memoria`.
