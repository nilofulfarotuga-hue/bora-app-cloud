# Relatório — missão `sistema-sem-travas-2026-10-15`

> Claude Code (Opus 5.5) no PC do Danilo, 15/10/2026, worktree `C:\BoraLocal\wt-sem-travas-15-10`.
> Registo detalhado (hora, ação, resultado) no `e2e_log`, `run_id = sistema-sem-travas-2026-10-15`.
> Memória do PC no arranque: 869 MB disponíveis (portão leve de 400 MB; só ficheiros e banco).
> Testes Flutter locais corridos com 1,1–1,4 GB disponíveis (portão de 800 MB respeitado).

## Para o Danilo (para ouvir)

**Fiz isto.**
Tirei a chave secreta do servidor dos três scripts antigos onde estava escrita, e a chave antiga da
app de mais quatro. A app passou a usar a chave pública nova da Supabase nas três lojas: a web está
no ar com ela, o Android passou o teste automático dos três perfis com ela e foi para a Play Store
(versões 671 e 672), e o iPhone foi enviado assinado para a Apple nas duas vezes. Gravei o teu Protocolo nos três sítios.
O conserto do "pedir corrida nunca trava", que estava esquecido só neste PC desde as 7 da manhã,
foi para as três lojas, e a parte do banco (o alarme quando um cliente não consegue pedir e o ecrã
"Saúde da Web" no painel) ficou ligada.
Medi a memória do PC: parei 36 programas de imagens que ninguém usava, desliguei os dois relógios do
BoraStudio que corriam de 15 em 15 minutos e baixei o emulador de 4 para 2 GB.
Fiz o inventário das trancas, com as paragens desta semana uma a uma, e escrevi linha a linha como
as corrigir.
Fiz a pesquisa única: na lupa, escrever "táxi", "limpeza" ou "barbearia" leva logo ao sítio certo, e
as barbearias e salões aparecem. O Bora Motorista só aparece a quem tem acesso.
Fiz a Receita do Dia: 14 receitas portuguesas, o cartão na página inicial, o ecrã com ingredientes e
modo de fazer, o botão "Pôr no carrinho" que escolhe o supermercado não-parceiro mais barato e mostra
a lista ao cliente antes de encher o carrinho, o aviso das 10h só para quem o pedir, e o ecrã no painel
para criares, agendares, desligares e mudares a hora. Uma revisão independente apanhou produtos
errados no carrinho (o "papo-seco" dava comida de gato); afinei os termos até as 14 receitas darem os
produtos certos nos quatro supermercados.

**Falta isto, e porquê.**
Não fechei o repositório: fechado, as compilações do iPhone e do Android deixam de ser grátis —
cerca de 300 dólares por mês, ou param ao fim de um dia. Isso é decisão tua (mandei-te no Telegram).
Não criei a chave secreta nova: pô-la no cofre como a ordem dizia partiria 58 funções do banco,
incluindo os reembolsos, e a chave roubada continuaria a funcionar na mesma. O caminho certo está em
`docs/SEGURANCA-CHAVES.md`; o clique que mata a chave roubada é desligar as chaves antigas, e isso só
quando quase toda a gente tiver a app nova.
As trancas protegem-se a si próprias, por isso não as consegui mudar: as correções estão em
`docs/TRANCAS.md`, para aplicar numa sessão com as trancas desligadas quando disseres.
Não fiz o reembolso ao meio de pagamento original (é Stripe, fora desta autorização), o login com
Google e Apple (precisa de chaves secretas da Google e da Apple, que são passo teu), o Leite Ninho da
Goola nem o carro ao vivo (as duas ordens de 14/10 não estão em lado nenhum: PC, Drive, memória),
nem a prova no emulador (com 1,4 GB livres a regra nova dos 3 GB não deixa abrir). As oito sessões
do Claude abertas pelo telemóvel desde 11/10 continuam abertas — não consigo saber daqui se ainda
as usas; arquivá-las em claude.ai/code liberta uns 7 GB.

**Erros que encontrei pelo caminho.**
O painel "KPIs de pesquisa" estava sempre vazio porque nada gravava as pesquisas — corrigido.
O motor de pesquisa do Bora Assistente dá "certeza alta" a produtos absurdos — contornei na receita,
o defeito do Assistente continua. O agente "juiz-revisor" do manual não existe nesta instalação.
Quatro tarefas agendadas do PC estão a falhar (vigia da VPS, BoraStudio, batimento, retomar).
O mapa de contas põe a Supabase e a Cloudflare no perfil pessoal e o teu Protocolo diz perfil Bora.
O Córtex não respondeu nesta sessão (precisa de nova autorização).

**Próximo passo.**
Escolher o que fazer ao repositório (pagar, mover compilações para a VPS, ou esperar), e dizer quando
queres que as trancas sejam corrigidas.

## Provas (resumo; detalhe no `e2e_log`)

| Bloco | Estado | Prova |
|---|---|---|
| 0.1 repo privado | 🔴 parado | API GitHub `visibility=public`; 30 dias: 4 977 min macOS + ~4 400 min Linux |
| 0.2 segredos fora do código | ✅ | commit `40d690c4`; descodificação dos JWT no `git grep`: 0 `service_role` |
| 0.3 chave secreta nova | 🔴 parado | 58 funções leem `service_role_key`, 25 Edge Functions chamadas (SELECT) |
| 0.4 chave publicável | ✅ 3 lojas | web: bundle com `sb_publishable`, 0 JWT legados, REST/Auth 200 a partir do site; Android CI `38729041089` autoteste ✅ + AAB alpha (versionCode 671); iOS CI `38729041180` A ✅ + B (IPA → App Store Connect) ✅ |
| 0.5 / 0.6 | ✅ | `docs/SEGURANCA-CHAVES.md`; histórico não reescrito |
| 1.1–1.2 trancas | ✅ | `docs/TRANCAS.md` |
| 1.3 correções | 🔴 tranca recusou | "zona vermelha: bora-mods (a propria tranca)" |
| 1.4 prova | ✅ (antes) | leitura ✅, edição ✅, `rm` no scratchpad ❌ bloqueado |
| 1.5 Protocolo + navegadores | ✅ | `cmp` igual nos 3 ficheiros; skill atualizada |
| 2 RAM | ✅ parcial | `docs/RAM-2026-10-15.md`; 869 → 1 599 MB; prova com emulador não feita |
| 3.1 tvde nunca trava | ✅ | migração aplicada; 26 testes; nas 3 lojas com o primeiro envio |
| 3.2 / 3.3 toque / 3.4 / 3.7 | ✅ já estavam | commits `4d0b1c3c`, `8b7c2c0f`, `3986642f`, `a1e7eddf`, `5dad44a7` |
| 3.3 reembolso | 🔴 fora da autorização | Stripe |
| 3.5 login social | 🔴 | só esqueleto; precisa de segredos Google/Apple |
| 3.6 Goola / 4.1 carro ao vivo | 🔴 | prompts de 14/10 não encontrados |
| 4.2 pesquisa única | ✅ 3 lojas | commit `151add10`; revisão 3 correções; 20 testes; web `38741205907` ✅; Android `38741205960` ✅; iOS `38741206026` ✅ |
| 4.3 Receita do Dia | ✅ 3 lojas | 3 migrações; 56 + 8 carrinhos simulados certos; Android autoteste ✅ (versionCode 672); iOS A ✅ + B (IPA → App Store Connect) ✅ às 14:47 UTC |
| Fecho | ✅ | digest `digest-2026-10-15-sistema-sem-travas` em `claude_ai_memoria`; prompt e relatório no Obsidian; `ctx doctor` tudo OK (v1.0.169) |
