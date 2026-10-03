---
id: memoria-claude-ai-digest-2026-09-24-noite-fecho
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-25
zona: verde
confianca: alta
estado: atual
---

# Noite de fecho 24-25/09: verificar do motorista, aviso por email, decisor e sombra no Hermes

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-24-noite-fecho`, origem `claude-code`, atualizada em 2026-09-25T06:56:39.667074+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 24 noite fecho · memoria claude.ai · claude_ai_memoria

O QUE MUDOU NESTA NOITE.

1) A pagina de verificacao do motorista ja abre pelo caminho curto. boraguarda.com/verificar/<token> dava 404 e so funcionava com ?t=. A causa nao era obvia: a reescrita do _redirects apontava para /verificar/index.html e o Cloudflare Pages redireciona 308 qualquer URL acabado em .html para a forma limpa, matando a reescrita. O alvo passou a ser a PASTA. Isto importa porque o QR e o PDF da ficha usam o caminho curto. Pelo caminho: _redirects e _headers tinham fins de linha do Windows; no _redirects isso faz a regra ser descartada em silencio. Ficaram em LF, com .gitattributes a prende-los e o deploy a tirar o CR.

2) O aviso critico por email ja sai. Nao era a chave da Resend: era o notify-admin-urgent, que so lia a chave do ambiente e nunca do cofre (as irmas ja liam), e tinha remetente noreply@boraapp.com, dominio nao verificado. Passou a ler o cofre por get_resend_key e a enviar de avisos@boraguarda.com. Escrevia "email skipped" 13 vezes por dia. Provado com o email a chegar a caixa.

3) O decisor deixou de ficar preso. Era 20 s por modelo e repetia o MESMO modelo em 429/503. Agora: 8 s, uma tentativa por modelo, e 429/503/404 passam ja ao seguinte; ordem gemini-3.6-flash, 3.5-flash-lite, 3.1-flash-lite. Nas mesmas 20 provas de 23/09 (19 sem motor) responderam 20 de 20 sem erros, ~800 ms. MAS O ACERTO E MAU: 5 em 10 no Robot B e 2 em 6 no suporte, porque responde "nao" a quase tudo. A confianca separa (0,61 certo, 0,28 errado), o que aponta para o corte. Por isso continua em SOMBRA.

4) O Hermes ja pergunta ao decisor, em sombra, sem levar a chave de servico para a VPS. Ha uma porta estreita, decidir_sombra, com chave propria (hermes_decisor_key), que faz a chamada por dentro. Na VPS: /opt/data/ferramentas/decidir.py e HERMES_DECISOR_KEY no .env. Ligada em rotinas/emerson.py (Porteiro do Telegram) e rotinas/despachante.py (escolha do agente). Provado ao vivo pelo despachante. Como ligar o Jev quando a chave chegar esta escrito no MOTORES.md (~/.claude/motores/ e /opt/data/).

5) O radar dos videos das 02:00 CORRE e avisa ha varias noites (registo da ponte a 22, 23, 24 e 25). O problema e a fonte: um historico do Takeout parado, com os 12 videos ja lidos, por isso entram ZERO novos. A mensagem do Telegram passou a levar os numeros em vez de dizer sempre "corrida terminou". Quem quer videos novos todos os dias ja tem o radar-crescimento das 19:00.

6) Os tres ecras do painel (Decisoes Jev, Documentos dos motoristas, Atraso da oferta) estao no pacote publicado. Os documentos abrem vazios porque a tabela tem zero linhas.

ARMADILHA A GUARDAR: procurar texto com acentos dentro do main.dart.js compilado da SEMPRE zero, porque os acentos vao escapados. Quase reportei que o painel estava atrasado. Procurar pelos ids sem acentos.

POR FECHAR: Jev sem chave (registo fechado no TypeSafe); commits do bora-site por empurrar (guardrail); 3 testes do ecra da ficha legal falham por um ListTile dentro de caixa com cor, achado ontem e nao corrigido de proposito.
