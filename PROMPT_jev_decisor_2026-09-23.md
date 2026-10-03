⚠️ MODO PROTECÇÃO TOTAL ⚠️
MOTOR: OPUS (Claude Code no PC, com --chrome) como maestro; código pesado por `opencode run -m opencode/glm-5.2` por dentro quando der.
Pasta C:\BoraLocal\projetosflutter\bora_app, ramo autonomous-night-2026-04-29, WORKTREE próprio (há outras sessões no repo). Invoca primeiro o orquestrador CEO-AI em .claude/skills/ceo-ai/ e lê a skill protocolo-missao-bora. Idiomas: app PT-PT, painel admin PT-BR. run_id `jev-decisor-2026-09-23`, fluxo e2e_log `jev-decisor-2026-09-23`, uma linha por bloco com prova.

CARTA DE AUTONOMIA (ordem do Danilo 23/09: autoridade total, "não me perguntem mais nada"): nunca terminas o turno à espera dele; decides, aplicas, registas; bloco bloqueado = motivo no e2e_log e segues; Telegram um resumo por bloco, em voz; contexto a acabar = crias tu a ordem de continuação. Logins: só sessão já iniciada no Chrome (perfil Bora); nunca senhas; se pedir palavra-passe/captcha/cartão, deixa a página aberta e avisa numa linha. Outro erro pelo caminho: reporta no e2e_log com passo `fora-de-scope`, não corrige.

CONTEXTO: o Danilo viu vários vídeos sobre o JEV (TypeSafe AI, lançado 15/09/2026, do Diogo Almeida ex-OpenAI) e mandou: "esse JEV tem que estar a funcionar, ou faz alguma coisa bem parecida". Apurado por mim: NÃO é chat — é um modelo "System One" que devolve decisões tipadas (Choice = escolher entre opções, Score = nota numa escala, Noul = sim/não) com probabilidades e confiança, em 70-500 ms. Acesso self-serve: chave em https://console.typesafe.ai/keys ; endpoint `POST https://api.typesafe.ai/v1/systemone` com `Authorization: Bearer <chave>`, body `{state, model:"jev-latest", questions:[...]}`; docs https://docs.typesafe.ai/introduction/quickstart.md , https://docs.typesafe.ai/api.md , https://docs.typesafe.ai/models.md ; custo anunciado 42 USD por mil milhões de tokens de entrada.

O QUE VAIS FAZER E PORQUÊ: dar ao Bora um DECISOR único, rápido e barato para as decisões pequenas que hoje não existem ou passam pelo Gemini.

BLOCO 1 — conta e chave. Abre console.typesafe.ai no Chrome (perfil Bora) e entra com "Continue with Google" na sessão já iniciada de boraappbora@gmail.com. Cria a chave; guarda-a no Vault do Supabase (`typesafe_api_key`) e como secret da Edge Function — nunca no repo. Regista os limites/preços reais que a consola mostrar. Se a conta não abrir sem palavra-passe nova, captcha ou cartão: página aberta, linha no Telegram, e continuas com o fallback do bloco 2.

BLOCO 2 — Edge Function `decidir` (Deno): recebe `{pergunta_tipo: choice|score|noul, pergunta, estado (texto/JSON), opcoes|escala, usado_por, contexto_id}`; chama o Jev; sem chave ou com erro cai em `gemini-3.1-flash-lite` com o MESMO contrato de saída (resposta tipada + confiança + probabilidades). Grava tudo na tabela nova `decisoes` (id, quando, tipo, pergunta, estado_resumo, resposta, confianca, probabilidades jsonb, motor jev|gemini, latencia_ms, usado_por, contexto_id, resultado_real nullable para aprender depois). RLS: admin vê tudo, serviço escreve. Migração no repo + aplicada.

BLOCO 3 — primeiras 4 utilizações, cada uma com interruptor em platform_settings e em MODO SOMBRA por defeito (decide e regista, não manda):
a) escolha do estafeta/motorista quando há 2 ou mais candidatos a uma entrega ou corrida — Choice do melhor com o estado (distância, aceitações recentes, avaliação, carga atual);
b) reservas de serviços — Score de risco de no-show ao criar a reserva;
c) Robot B — Noul "vale a pena abrir sugestão?" antes de gravar em robot_suggestions;
d) support-chatbot — Noul "passar a humano?" por mensagem.
Nenhuma decisão altera valores nem regras de negócio — só escolhe, pontua ou diz sim/não.

BLOCO 4 — painel admin (PT-BR): ecrã "Decisões" com lista, filtro por tipo/motor/usado_por, confiança, interruptor sombra/ativo por regra, e cartão "quanto custou hoje" (tokens × preço).

BLOCO 5 — provas: 20 chamadas reais ao Jev com estados reais anonimizados e tempo medido; as mesmas 20 no Gemini, lado a lado (acerto vs o que aconteceu de verdade quando houver `resultado_real`); testes; `flutter analyze` 0 erros.

BLOCO 6 — fecho: push (o CI sobe o versionCode, nunca à mão), relatório `JEV-DECISOR-2026-09-23.md` na raiz + cópia em C:\Users\danil\Desktop\Bora\Projetos\, digest no Córtex (cortex_reportar), linha final no e2e_log, resumo em voz no Telegram a dizer em duas frases o que o decisor já decide e o que ainda está em sombra.
Termina com /ctx doctor e /ctx stats.
