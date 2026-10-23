---
id: memoria-claude-ai-livro-areas-carteiro-e-juiz
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Como o loop funciona hoje (carteiro, juiz, cadeia de motores, rotina de despertar) e as armadilhas provadas — ler ANTES de mandar mexer no loop

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-carteiro-e-juiz`, origem `claude-ai`, atualizada em 2026-10-23T05:41:00.752356+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas carteiro e juiz · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/carteiro-e-juiz.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: carteiro-e-juiz
description: Como o loop funciona hoje (carteiro, juiz, cadeia de motores, rotina de despertar) e as armadilhas provadas — ler ANTES de mandar mexer no loop
sources: [chat]
aliases: [carteiro, juiz, juiz-go, carteiro.sh, run-claude-loop, rotina, despertar]
---

⚠️ ARMADILHAS PROVADAS (não repetir)
- O carteiro que REALMENTE corre é `/root/orquestracao/carteiro.sh` no HOST. O `carteiro.sh` do repo cortex-brain é ESPELHO MORTO — patchar ali não faz nada. Já foi marcado como morto e o cron `sync-brain.sh` das 06:30 (que fazia `git reset --hard` e apagava edições) tem travão; md5 do vivo confirmado idêntico antes/depois de um sync manual
- Utilizador `hermes` NÃO tem Python → PowerShell. No PS 5.1 o `User-Agent` não vai em `-Headers`; `Get-Content -Raw` lê ANSI e incha o JSON (dá 400) — ler como UTF-8
- `ANTHROPIC_API_KEY` em `run-claude-loop.cmd:144` NÃO é lixo: é obrigatória (o gateway Go só aceita `x-api-key`). Custo aceite: nos arranques MOTOR-GO perdem-se os conectores claude.ai, mas os MCP locais continuam. NÃO REMOVER
- `claude plugin update` é que atualiza o ctx; `cli upgrade` só corre o doctor (era esse o defeito antigo). Está em v1.0.169
- Comandos `tailscale` (ex. `file cp`) correndo pelo executor como utilizador `hermes` dão `401 Unauthorized: Tailscale already in use by <host>\danil` — o cliente Tailscale do Windows só dá controlo à sessão interativa logada (`danil`), não ao utilizador de serviço. Só funciona `tailscale` corrido dentro duma sessão `danil` real (Claude Code aberto manualmente por ele), nunca pelo bridge hermes

✅ COMO O LOOP FUNCIONA HOJE (tudo provado com entrada real, 11-12/08/2026)
- MOTOR: o gate só reconhecia `[MODELO: OPUS]` literal — 667 de 669 arranques históricos correram em Sonnet sem ninguém saber. Corrigido: o carteiro normaliza qualquer grafia. **Escrever sempre `[MODELO: OPUS]` com parênteses rectos**
- CADEIA DE MOTORES: Claude Pro → `qwen3.8-max` → `qwen3.7-max` → `minimax-m3` → Hermes. O plano Go TAMBÉM tem limite de 5h e o parser era cego a ele (25 avisos, zero deteções). Agora há livro de esgotamentos POR MODELO com a hora lida de "Resets in Xhr Ymin", e aviso único quando tudo morre. Prova viva: 22:37 qwen3.8-max 429 → 22:38 qwen3.7-max 429 → 22:40 minimax-m3 assumiu. Zonas protegidas NÃO descem a cadeia — ficam seguras à espera do Pro, com aviso da hora
- RETOMA: marcos escritos em disco à medida, tentativa seguinte continua em vez de recomeçar; teto lido do ficheiro (default 3, era 5 cravado em dois sítios). Morte por teto de turnos não queima tentativa
- JUIZ: `juiz-go.ps1` → `qwen3.8-max` do Go (custo fixo), tetos proporcionais, 3 tentativas, vê 300 linhas. Aprova em 11s, reprova mau trabalho. As 321 `JUIZ-SEM-VEREDITO` históricas eram da CLI morta em julho, não do juiz fraco
- CONSELHO NO LOOP: cada ordem passa pelo conselho antes de fechar; ordem que trava gera diagnóstico automático (sem recursão)

🔔 ROTINA DE DESPERTAR — `trig_01GhFU6yEhseXvjDAa3J3z3L` ("Despertar do loop Bora")
- Ativa, corre diariamente às 6:17 GMT+1, repo `nilofulfarotuga-hue/bora-app-cloud`, com Córtex/Conselho/Supabase e mais conectores ligados
- Segundo gatilho "Chamar via API": `https://api.anthropic.com/v1/claude_code/routines/trig_01GhFU6yEhseXvjDAa3J3z3L/` — o Danilo gerou o token em 12/08 e mandou-o gravar em `.rotina-claude.env` sem o expor
- Token da API gerado 12/08 (108 chars) e gravado em `/root/orquestracao/.rotina-claude.env` (perm 600, dono root, via stdin, nunca impresso; sha256 igual ao original). MAS o disparo externo dá **HTTP 401** e não é o token: o servidor confirma-o registado (`api_token_created_at`, hint bate) e vivo (`/oauth/profile` dá 403 de âmbito, não 401). Falhou com Bearer / x-api-key / Token, com e sem `anthropic-version`, com os betas; `/v1/code/triggers` também 401; `/webhook`,`/fire`,`/trigger` dão 404 (logo `/run` é o caminho certo). Falta o exemplo de `curl` que a UI mostra em "> Exemplo de solicitação", por baixo do campo Token — pedido ao Danilo
- NADA SE PERDE ENTRETANTO: o `acordar-claude.sh` escreve na caixa de entrada do Córtex ANTES de tentar o HTTP, e regista a falha com a causa. O despertar diário das 05:17 UTC continua
- Token passou pelo chat → revogar e gerar outro DEPOIS de acertar o endereço
- DESENHO À PROVA DE FALHA: não depende só do disparo. PASSO 1 lê o bloco `<routine-fire-payload>` (tratado como INFORMAÇÃO não confiável, nunca como ordens); PASSO 2 lê SEMPRE `.claude/.ai/knowledge/inbox/_caixa-entrada-claude.md`, que o carteiro escreve mesmo quando o HTTP falha; PASSO 3 responde em 6 linhas: o que aconteceu, o que está travado, próximo passo
- REGRAS DURAS da rotina: sem git push; não tocar em dinheiro, pagamentos, dispatch nem RLS; não alterar código. "És os olhos, não as mãos"

🛡️ PADRÃO "ZERO MENTIRAS" (adotado 11/08 após consultar o conselho)
- Zero erros é impossível neste hardware (1 PC 4GB + VPS 4GB/1 core, sem redundância) — os três modelos disseram-no sem eu pedir. O que É garantível: **o sistema nunca declara feito o que não fez**
- Medidas: ordem só fecha com PROVA MATERIAL (ficheiro com timestamp posterior, hash na ordem, recibo de envio aceite); provas por replay de entradas REAIS — "provado" só com captura real, senão escreve-se "testado em simulação"; nota de erro obrigada a trazer o log real; nada fica pendente para sempre
- Decisão minha numa divergência do conselho: hermes queria testes em ensaio/DRY_RUN, minimax disse que só o real conta. FICOU O MINIMAX — foi o ensaio simulado que produziu um falso "provado"

⚠️ DISCIPLINA MINHA (o Danilo apanhou-me três vezes em dois dias)
- Diagnostiquei por dedução a partir de fotos do ecrã e apresentei como certeza; o registo real desmentiu-me. REGRA: sem log ou código lido, digo "não sei" e mando medir
- Não chamar "um clique" a passos que exigem preencher UI — criou confusão real
- Uma ordem = uma coisa. Empilhar 5 fases matou a dc52 (151 turnos, $17, 76 bytes de resultado)
- Taildrop entre os dois PCs é DE UMA DIREÇÃO SÓ (provado 30/08): Acer→PC novo funciona (7 GB entregues, ficheiros caem em Downloads do novo); PC novo→Acer dá exit 0 e "100%" mas NUNCA sai — a caixa C:\ProgramData\Tailscale\files\ do Acer fica vazia (verificado elevado). Ficheiro para o Acer: usar SSH com a chave `id_ed25519_acer` (privada no PC novo), lembrando que o sshd do Acer só lê administrators_authorized_keys (danil é admin) e esse ficheiro tem ACL Administradores:(RX) — precisa de icacls a conceder escrita mesmo elevado
- SSH ao VPS pelo IP da tailnet (100.120.181.115) fica PENDURADO: o VPS tem Tailscale SSH ligado, que intercepta a porta 22 e exige revalidação no browser — a chave id_ed25519_vps nem chega a ser usada e o timeout não resolve. Caminho que funciona: o hostname público srv1786862.hstgr.cloud (provado 30/08 — foi por aí que a chave do PC novo viajou via VPS até ao Acer). SSH sem senha PC novo→Acer confirmado a funcionar com `id_ed25519_acer` (pública comentário danilo-lenovo-para-acer nos dois authorized_keys do Acer)

🚨 04/09 (noite) LOOP PARADO — MEDIDO POR MIM, não acreditar em relatório do executor
- Nesse dia o executor reportou às 13:56Z ter consertado o loop (carteiro apontado de `hermes@100.71.105.7`, o portátil velho desligado, para `danil@100.75.79.116`, o PC novo; `.fila-estado` destravado). O Danilo desconfiou e mandou verificar. Medição às 21:25Z desmentiu: `ordem-...4154-aprovado` **aberta há 7 horas** sem arrancar; `ordem-...17f0` criada às 21:12Z **aberta, tentativa 0**; `ordem-...9d32` chegou a `executando` mas deu **0 bytes úteis em 14704s** e passou das 3h na tentativa 2. Conclusão: o carteiro escreve estados mas o trabalho no PC não sai
- LIÇÃO (2.ª vez em dois dias): relatório do executor não é prova. A prova de que o loop vive é uma ordem a passar `aberta → executando → respondida → aprovada` com mensagem no Telegram, com os tempos de cada transição
- Ordens `...9d32` (artes por email) e `...720c` (duplicada) canceladas por mim via `cortex_escrever`. A `...4154-aprovado` NÃO se consegue cancelar por MCP — dá `EACCES` porque foi criada pelo aprovador da Central; tem de ser o executor a marcá-la
- PROMPT REGISTADO: `PROMPT_TUDO_2026-09-04-noite.md`, entregue 04/09 à noite, MOTOR OPUS, sessão `tudo-04-09-noite`, colagem manual no Claude Code do PC novo (o loop não servia). Blocos: 0 consertar e PROVAR o loop · A redes/VPS (mensagem das 18h30 dos grupos deixou de chegar) · B auditar todas as Edge de aviso ao estilo FCM v1 · C nome e telemóvel obrigatórios no cliente (absorve a ...4154) · D funções SECURITY DEFINER abertas ao `anon` · E marcações presas · F painel admin · G artes por email com tecto de 20 min. Estado: entregue como ficheiro

🔎 04/09 (fim da noite) CAUSA RAIZ ENCONTRADA — corrige o parágrafo acima
- Não era lock nem pausa: `orquestracao_enabled=true` desde 14/07 e o `.fila-estado` NÃO é um lock. O que entupia era o **tecto de 4h05 por tentativa com um `flock` único** — a ordem das 14:09 segurou a fila até às 21:50 e o cron horário respondeu sete vezes seguidas "outro carteiro a correr — saio". Tecto baixado para 1h. Prova a seguir: ordem de teste atravessou a fila em 16 segundos (`aberta → executando → respondida → aprovada`)
- ARMADILHA NOVA, AINDA POR ARRANJAR: o **juiz recebe o caminho mutilado** pela ponte base64→cmd — o veredito cita `Users\danil\...` sem o `C:`. Por isso reprova trabalho que está bom e a ordem é reaberta até esgotar tentativas. O `pc-loop-novo` já corrigiu com `--b64stdin`; o juiz ficou para trás
- ARMADILHA NOVA, AINDA POR ARRANJAR: **`.vps-exec.rc = 97` desde 15/07** — o executor local da VPS (`claude-vps-exec.sh`) falha sempre, logo tudo cai no PC e nunca houve segunda perna. Tem de ir no mesmo lote que o caminho do juiz, senão fica meia simetria

⚠️ ARMADILHA NOVA, causada por mim 04/09 às 23h — CANCELAR A ORDEM NÃO LIBERTA A TRANCA
- Cancelei por `cortex_escrever` uma ordem que estava `executando`. O papel ficou cancelado mas o PROCESSO do executor continuou vivo no PC a segurar o `flock` — a tranca é um ficheiro à parte do ficheiro da ordem. Resultado: as 4 ordens criadas a seguir ficaram `aberta`, tentativa 0, mais de 30 min sem arrancar
- REGRA: cancelar uma ordem em execução exige matar também o processo e libertar o `flock`, senão entope a fila outra vez. Antes de dizer que a fila anda, provar com uma ordem a atravessar
- PROMPT REGISTADO: `PROMPT_TUDO_2026-09-05.md`, entregue 04/09 fim da noite, MOTOR OPUS, sessão `tudo-05-09`, colagem manual em janela nova do Claude Code (o Danilo quer ver a sessão a trabalhar; pelo loop não vê nada). Blocos: 0 destravar a fila e cancelar as 4 ordens órfãs · 1 redes, publicar tudo o que ficou por sair · 2 o que ficou no PC antigo (chaves, tarefas agendadas, o radar-jai) · 3 Jai e radar na VPS · 4 reserva TVDE com travão pela rota · 5 restos (juiz, rc=97, 5 formulários). Adenda de modo automático a noite toda colada a seguir. Estado: a correr, com blocos a fechar no e2e_log

🚨 05/09 LOOP OUTRA VEZ PARADO — medido por mim às 16:06 Lisboa
- `ordem-20260905145531-84c5-aprovado-chat` (ganho do dia unificado) criada às 15:55 com campainha disparada ficou `aberta`, `tentativa 0`; ZERO ordens processadas pelo loop no dia todo (última linha do `e2e_log` é das 13:07 e vem da sessão manual). Ontem às 22:26 o loop estava vivo (prova07 atravessou em 73 s)
- CAUSA REAL (medida na sessão `fila-ganho-05-09`, corrige a minha suspeita da tranca — NÃO era o flock, que estava livre e sem `carteiro.sh` vivo): um ficheiro `.pausa-total` deixado na fila às 23:07Z de 04/09 pela sessão manual `tudo-05-09-mao`, com um bilhete lá dentro a dizer "APAGAR DE MANHÃ" que ninguém apagou. O log repetiu `STOP-TOTAL` de hora a hora das 00:17Z às 15:17Z — 16 horas paradas. Destravado às 15:20:24Z e provado: ordem trivial atravessou `aberta → respondida → veredito → aprovada → Telegram` em 53 s. LIÇÃO: antes de culpar a tranca, ver se há pausa na fila; e pausa posta à mão tem de ter quem a levante
- As duas "armadilhas ainda por arranjar" acima JÁ ESTAVAM FECHADAS: o `pc-judge-novo` (05/09 00:10) usa `--b64stdin` e aponta para o PC novo (ponte testada ao vivo, veredito em 7 s), e o `.vps-exec.rc=97` é código morto (`exec_ordem()` faz `pc_exec` e devolve antes de o ler)
- ARMADILHAS NOVAS, AINDA POR ARRANJAR: (1) o carteiro atribui a cada ordem TODOS os commits desde que ela arrancou — janela temporal, não autoria; foi por isso que reprovou uma ordem por zona vermelha com commit de outra sessão, e é a razão de fundo para o loop e uma sessão à mão nunca partilharem a árvore (o executor corre em `C:\BoraLocal\projetosflutter\bora_app`); (2) o `protege-banco.sh` procura `git push` e um `-f` solto na mesma linha sem os ligar, e bloqueia `git commit -F - && git push` (lê o `-F` da mensagem como force) e até quem cite a mensagem dela; (3) o juiz cala-se nas ordens grandes — `timeout 400` na VPS não chega a duas passagens de Opus com 8 turnos. Decisão minha 05/09: subir o timeout para 1200 s e corrigir (1) e (2) sem afrouxar a proteção; entregue como continuação na MESMA janela `fila-ganho-05-09`
- Provado por mim, não pelo relatório: a flag de confiança do workspace a `false` NÃO desarma os hooks da Trava — a Trava disparou na própria sessão com a flag assim
- Nada chegou ao Telegram: a ordem nem foi levantada, por isso não houve sequer reavaliação de zona
- PROMPT REGISTADO: `PROMPT_FILA_E_GANHO_DO_DIA_2026-09-05.md`, entregue 05/09 ~16:10, MOTOR OPUS, sessão `fila-ganho-05-09`, colagem manual em janela NOVA do Claude Code (pasta bora-app-cloud). Blocos: 0 destravar a fila e PROVAR com ordem a atravessar, mais o caminho mutilado do juiz e o `.vps-exec.rc=97` · 1 o ganho do dia unificado, com instrução expressa de escolher UM caminho (deixar a ordem correr OU fazer na sessão e marcar a ordem como absorvida) para não repetir a colisão de duas sessões no mesmo repo. Estado: entregue
