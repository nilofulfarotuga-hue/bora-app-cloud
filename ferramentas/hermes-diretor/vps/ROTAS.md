# ROTAS.md — quem faz o quê (22/11/2026, missão hermes-diretor-2026-11-20)

O diretor é o Hermes (emerson). Mando trabalho pelo despacho:
`python3 /opt/data/bin/porta.py despacho_inserir '{"para":"<agente>","titulo":"...","tarefa":"..."}'`

Três estados: **relógio** (corre sozinho à hora dele), **a pedido** (só corre quando eu mando ou há
evento; o despachante acorda-o para essa tarefa), **arquivado** (não corre; faz o substituto).
Dinheiro e apagar: qualquer agente pára e pede o "autorizo" do Danilo.

## Assunto → agente (substituto)

- Pedido parado, estafeta, corrida, loja que não aceita, app ou site em baixo → **torre** (emerson)
- Conferir se um trabalho foi mesmo feito, prova, bug, resposta errada de um robô, texto antes de
  publicar (o Refinador) → **fiscal** (emerson)
- Cliente no WhatsApp da loja, comentário nas redes, reclamação, pedido de pessoa → **atendimento** (emerson)
- Loja parceira: entrada, menu, horário, dúvidas, loja parada → **gestor-parceiros** (vendedor)
- Parceiro novo a angariar, proposta a uma loja → **vendedor** (gestor-parceiros)
- Sites, presença digital e assessoria para vender a negócios → **vendedor-servicos** (vendedor)
- Construir ou vigiar um site publicado → **arquiteto-sites** (vendedor-servicos)
- Fecho semanal, quem deve, custos, renovações de subscrições, contas a receber → **cobrador** (emerson).
  Só rascunhos e contas; mexer em dinheiro é com o autorizo.
- Estafeta novo, lista de espera, documentos → **recrutador** (gestor-parceiros). Regra: não há
  vagas; guarda o nome e o número e avisa.
- Publicar a app (Play, App Store, web), loja ou categoria nova → **lancamentos** (emerson). Segue o
  `PADRAO_BORA.md`.
- Chaves, permissões, validade de tokens, acessos → **seguranca** (emerson)
- Redes sociais, grupos da Guarda, Comunidade 24h, calendário → **redes** (designer)
- Arte, imagens, material impresso → **designer** (redes)
- Vídeo e filme (Bora Studio, no PC) → **estudio** (designer)
- Números do negócio, crescimento, o que subiu e desceu → **crescimento** (emerson)
- Novidades de IA e ferramentas (radar semanal, sem repetir o que o Danilo já tem) → **batedor** (emerson)
- App Em Dia → **gestor-em-dia** (emerson)
- Apoios, papelada e prazos oficiais → **burocracia** (emerson)
- Erro, crash, ecrã partido, CI vermelho, conserto de código → **engenheiro** (emerson). Conserta por
  `ordem` ao Claude Code; só entra em produção com o fiscal a aprovar e o CI verde.
- Servidor: disco, memória, processos presos, cópias, atualizações, motores → **zelador** (emerson)
- Mercados (Continente, Pingo Doce, Lidl…): catálogo, produto em falta, foto, preço por conferir →
  **mercados** (gestor-parceiros). Mudar preço é dinheiro.
- TVDE, limpeza, lavagem, marcações e reservas: prestadores, corrida sem motorista, reclamações →
  **gestor-servicos** (torre)
- Loja Online do Bora (nichos, envio por correio) e Mimo Patudo: produtos, fornecedores,
  certificados → **loja-online** (vendedor-servicos)
- Livro, resumos da noite, relatórios para ouvir, e-mail e calendário → **emerson** (faço eu)

## Estado de cada um

- Relógio: torre (de hora a hora até o vigia por eventos estar ligado; depois um resumo por dia e
  só por evento), cobrador, crescimento, gestor-parceiros, vendedor, vendedor-servicos, fiscal (diários).
- A pedido: atendimento, recrutador, lancamentos, seguranca, redes, designer, estudio, batedor,
  gestor-em-dia, arquiteto-sites, burocracia, e os cinco criados a 22/11/2026 por ordem do Danilo:
  engenheiro, zelador, mercados, gestor-servicos, loja-online.
- Arquivado (substituto): critico (fiscal), qualidade (fiscal), escriba (emerson),
  assinaturas (cobrador), gestor-clientes (cobrador), agenda (emerson).
- Bloqueado: trader. Só o Danilo o liga. Nunca o acordo.
