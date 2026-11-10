# Bloco H — robôs que usavam o Gemini do projeto Google `bora-juiz`

Missão fechar-tudo-2026-11-10, agente H, ramo `ai/2026-11-10-fechar-tudo-h`. Escrito a 10/11/2026.

Porquê: o projeto Google `bora-juiz` (gen-lang-client-0518472552) tem a conta de pagamento vencida e o
juiz de visão levou HTTP 402 a 09/11. O Danilo não põe pagamento novo em nenhum projeto Google. Ordem
dele: os robôs usam primeiro a API do Claude e, se falhar ou acabar o crédito, a rotação de motores
grátis. A API do Claude é só para os robôs (01/11), nunca para o Claude Code.

## 1. Segredos das Edge Functions (só nomes, lidos com `supabase secrets list` a 10/11)

Existem: `ANTHROPIC_API_KEY` (31/10, a chave dos robôs), `GEMINI_API_KEY` (12/08), `FIREBASE_*`,
`GOOGLE_DRIVE_*`, `STRIPE_*`, `SUPABASE_*`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`.

Há chave da Anthropic para os robôs: sim, `ANTHROPIC_API_KEY`, e o livro `ia_gastos` mostra o Claude a
responder nas Edge hoje (edge-decidir, edge-robos, edge-assistente, edge-amigo; nenhuma falha de crédito).

Faltam, para a reserva grátis das Edge (nenhuma é obrigatória; sem elas a reserva salta esse motor e o
erro diz o nome que falta):

- `GROQ_API_KEY` — o único motor grátis que NÃO treina com o que recebe; é a reserva dos robôs com dados
  privados (texto). Está nos `.env` do Motor Bora da VPS (`/opt/whatsapp-bora/.env` ou `/opt/data/.env`,
  segundo `ferramentas/motor-bora/MOTORES.md`). Não li o valor.
- `GEMINI_API_KEY_FALLBACK` — uma chave do Gemini de um projeto Google SEM conta de pagamento (camada
  grátis). Nunca a do bora-juiz. Só serve robôs sem dados privados (a camada grátis pode usar o conteúdo).
  O nome já existia no código (client-assistant), mas o segredo não existe no servidor.
- `OPENROUTER_API_KEY` — modelos `:free` (texto e visão). Existe no `.env` do Motor Bora do PC. Não treina?
  Depende do fornecedor por trás: tratado como "pode treinar" (só robôs sem dados privados).
- O Kilo Gateway não precisa de chave.

Que projeto Google é a `GEMINI_API_KEY` das Edge: NÃO confirmado (não li a chave). O código diz duas
coisas: `verificar-documento`, `etiquetas-menu-ia` e `resumo-avaliacoes` (29/10) dizem "projeto
bora-juiz, nível 1 pago"; `robot-b` (12/08) diz "passou para um projecto sem faturação". Última
chamada boa vista nas Edge com essa chave: talão a 09/11 19:55 UTC e documentos a 09/11 17:27 UTC; nas
últimas 24 h não há 402 nos registos das Edge. Ou seja: as Edge ainda não mostraram o 402, mas estão
na mesma conta vencida segundo o código — risco real.

## 2. Inventário

Legenda da última coluna: MUDADO = passa a usar o módulo novo; NÃO MEXIDO = porquê.

| Robô (ficheiro) | Para que serve | Chave | Vê imagens | O 402 afeta | Estado |
|---|---|---|---|---|---|
| `.claude/juiz/vision_judge.py` (PC) | Juiz de visão das capturas golden e dos artefactos do Robo; grava em `vision_findings` | `GEMINI_API_KEY` de `backend/.env` (bora-juiz) | sim | SIM, deu 402 a 09/11 | MUDADO: `.claude/juiz/ia_visao.py`. Provado ao vivo a 10/11 18:00 UTC: respondeu o Claude Haiku pelo porteiro, linha em `ia_gastos` (robo `juiz-visao`, 308+78 tokens, 0,00127 USD) |
| `_shared/documentos_robo.ts` → `verificar-documento`, `verificar-documento-previa` | Fiscal de documentos de estafetas e prestadores (cartão de cidadão, carta, selfie, documentos do veículo, comprovativo AT; imagem e PDF) | `GEMINI_API_KEY` | sim (+PDF) | sim | MUDADO: Claude Haiku, pouca certeza → Sonnet; `privado` (sem motor grátis) |
| `ocr-receipt` | Lê os talões (loja, total, linhas, NIF do cliente) → preço vivo e NIF da caixa | `GEMINI_API_KEY` | sim | sim | MUDADO: Claude Haiku, vazio → Sonnet; `privado` (o talão tem o NIF do cliente) |
| `etiquetas-menu-ia` | Etiquetas do menu (vegetariano, picante, sem glúten) | `GEMINI_API_KEY` | não | sim | MUDADO: Claude → Groq → Gemini grátis → OpenRouter → Kilo (dados públicos) |
| `resumo-avaliacoes` | Resumo das avaliações para o parceiro | `GEMINI_API_KEY` | não | sim | MUDADO: Claude → Groq (`privado`: comentários de clientes) |
| `analyze-conversations` | Análise semanal das conversas do suporte → `skill_suggestions` | `GEMINI_API_KEY` + `support_settings.gemini_model` | não | sim | MUDADO: Claude (até 90 s) → Groq (`privado`) |
| `support-human-chat` | "Falar com humano" (persona do suporte) | `GEMINI_API_KEY` + `support_settings.gemini_model` | não | sim | MUDADO: Claude (P1, Sonnet) → Groq (`privado`); sem motor → escala ao responsável como já fazia |
| `decidir` | Decisões | Claude primeiro desde 31/10; reserva `GEMINI_API_KEY` | não | só a reserva | NÃO MEXIDO: já é Claude primeiro; a reserva é o Gemini com ferramentas (outra forma de conversa) |
| `client-assistant` | Bora Assistente / Amigo | Claude primeiro; reserva `GEMINI_API_KEY` e `GEMINI_API_KEY_FALLBACK` (que não existe) | sim (fotos do cliente) | só a reserva | NÃO MEXIDO: idem; conversa com ferramentas |
| `support-chatbot` | Chat de ajuda | Claude primeiro; reserva Gemini | não | só a reserva | NÃO MEXIDO: idem |
| `admin-ai-assistant` | Assistente do painel | Claude primeiro; reserva Gemini | não | só a reserva | NÃO MEXIDO: idem |
| `robot-b` | Robô B | Claude primeiro; reserva Gemini | não | só a reserva | NÃO MEXIDO: idem |
| `_shared/embeddings.ts`, `embeddings-gte`, `cortex-embedding`, `reindex-knowledge` | Vetores (`gemini-embedding-001`) do catálogo, do manual, do Córtex e do RAG do suporte | `GEMINI_API_KEY` | não | sim, se o 402 chegar às Edge | NÃO MEXIDO: o Claude não faz vetores. Produtos e manual já têm o gte-small local (Supabase.ai) como motor principal; o Córtex e o RAG do suporte ficam sem vetores novos se o 402 chegar |
| `ferramentas/motor-bora`, `ferramentas/vps/motor-bora` (porteiro) | Motor Bora: Claude primeiro → rotação grátis (VPS e PC) | Gemini como um dos grátis (chave dos `.env` da VPS, não lida) | perfil `visao` | só se essa chave for do bora-juiz | NÃO MEXIDO: já é Claude primeiro; um 402 só castiga esse fornecedor e desce |
| `ferramentas/omniroute` | OmniRoute da VPS (Hermes, Emerson) | Gemini como fornecedor | — | idem | NÃO MEXIDO (VPS; já desce sozinho) |
| `ferramentas/assistente-negocio`, `ferramentas/whatsapp-loja/cerebro` | Assistente de negócio e cérebro do WhatsApp (VPS) | Gemini entre outros (patch "Claude primeiro" de 31/10) | áudio | idem | NÃO MEXIDO (VPS) |
| `scripts/rag/ingest_knowledge.ts`, `scripts/crosstalk/query_knowledge.ts` | Ingestão e consulta do RAG (vetores) | `GEMINI_API_KEY` | não | sim | NÃO MEXIDO: vetores |
| `supabase/functions/_arquivo/*`, `scripts/e2e/*` | Funções arquivadas; ajudas de teste | — | — | — | Ignorados (não são robôs vivos) |

O "fiscal de arte" não está neste repositório (vive na VPS e, desde 21/09, o juízo da arte faz-se no
Gemini web pago do perfil Bora — não é API).

## 3. O que mudou

- Módulo novo das Edge: `supabase/functions/_shared/ia_visao.ts` (`pedirIa`). Ordem: Claude
  (`claudePrimeiro`: porteiro `ia_claude_pode`, livro `ia_gastos`, modelo do painel ou Haiku) → rotação
  grátis (lista medida do Motor Bora: Groq, Gemini grátis, OpenRouter `:free`, Kilo) → erro claro com o
  que cada motor disse. `privado: true` (por defeito) só deixa motores que não treinam (hoje só o Groq, que
  não tem visão grátis desde 08/09). A reserva escreve em `ia_gastos` com `modelo = "<motor>:<modelo>"` e
  custo 0. Imagens JPEG/PNG/GIF/WebP até 5 MB e PDF vão ao Claude; HEIC não (nos últimos 60 dias não houve
  nenhum HEIC nem imagem acima de 2,3 MB nos baldes de documentos e talões).
- `_shared/claude.ts`: mudanças só aditivas — `diagnostico` (porquê o Claude não respondeu), `timeoutMs`
  (respostas longas) e `registarGasto` exportada. Os 6 robôs que já o usavam não mudam.
- PC: `.claude/juiz/ia_visao.py` (`pedir`). Ordem: Claude direto só com `CLAUDE_ROBOS_API_KEY` (nunca a
  `ANTHROPIC_API_KEY`, que o Claude Code apanharia) → Claude pelo porteiro da VPS (perfil
  `claude-so-volume`, Haiku, sem cauda grátis) → rotação grátis de visão do porteiro (perfil `visao`) →
  erro claro. O juiz de visão usa-o; sem nenhum motor, sai 0 com aviso.
- SQL: `supabase/migrations/20261110210000_ia_robos_claude_primeiro_reserva_gratis.sql` — o porteiro
  `ia_claude_pode` só conta linhas do Claude (sem isto, uma resposta boa da reserva acordava o Claude logo
  a seguir a ele dizer "sem crédito", e um 402 de um motor grátis parecia "sem crédito do Claude"); os
  robôs novos entram em `claude_robos` (interruptor "usar Claude" no painel, Motores → Crédito Claude).
  Provado no PGlite (10 cenários, todos OK). Não aplicado.
- Gasto por robô por dia: a tabela `ia_gastos` já existia e o painel já tem "Gasto por robô (este mês)"
  com o valor de hoje e a exportação CSV (com o modelo de cada chamada) — não foi preciso ecrã novo.

## 4. Provas

- `deno test --allow-env --allow-read supabase/functions/_shared/ia_visao_test.ts` → 16 passed (Claude
  responde; Claude 402/429/500 → reserva grátis com custo 0 no livro; privado com imagem → nenhum motor
  grátis vê a imagem; tudo a falhar → erro claro com cada motor; sem chaves → nomes das chaves em falta;
  JSON inválido → passa ao seguinte; HEIC; erro de saldo da reserva nunca parece "sem crédito do Claude";
  documentos Haiku → Sonnet; documentos com 402 não repetem). Com `claude_test.ts`,
  `documentos_robo_test.ts` e `ocr-receipt/nif_talao_test.ts`: 58 passed na mesma corrida.
- `deno check` das 10 funções/ficheiros mudados e dos 6 robôs que já usavam o `claude.ts`: sem erros.
- `python .claude/juiz/test_ia_visao.py` → 9 testes OK (Claude direto; 402/429/500 → porteiro grátis;
  porteiro em baixo; nada configurado; nunca lê a `ANTHROPIC_API_KEY`; juiz de visão por cima).
- Ao vivo (1 captura de teste, sem dados de ninguém): `porteiro-claude:claude:claude-haiku-5-5`, 1,6 s,
  veredito "amarelo" com o motivo; linha em `ia_gastos` (vps, juiz-visao, claude-so-volume).
- `python .claude/juiz/anti_trapaca.py --base HEAD` → CLEAN.

## 5. Limites conhecidos (ditos, não escondidos)

- Imagens privadas (documentos, talões) não têm reserva grátis: sem Claude ficam "ia_falhou"/sem leitura e
  vêem-se à mão, como já acontecia quando o Gemini falhava. Se o Danilo quiser que os talões caiam no
  Gemini grátis quando o Claude falhar, é mudar `privado: true` para `false` em `ocr-receipt` (o talão leva
  o NIF do cliente — por isso ficou fechado).
- `support-human-chat`: o texto da persona diz "nunca revelas que és IA". O Claude faz a persona, mas se um
  cliente perguntar a sério se fala com uma máquina, não diz que é uma pessoa. Fica dito.
- A lista de modelos grátis envelhece (o fornecedor retira modelos); um 404 só passa ao seguinte. Trocar
  em `MOTORES_GRATIS` (ia_visao.ts) quando o auto-teste do Motor Bora mudar a lista.
- Os 5 robôs que já eram "Claude primeiro" continuam com o Gemini como reserva (conversas com
  ferramentas); se o 402 chegar às Edge, a reserva deles falha e devolvem o erro que já tinham.
