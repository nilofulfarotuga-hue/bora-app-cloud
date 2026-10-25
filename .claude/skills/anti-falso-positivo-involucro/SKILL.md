---
name: anti-falso-positivo-involucro
description: >
  Usa esta skill sempre que fores confiar num exit code, HTTP status, ou 'sucesso' de alto nível de qualquer script/curl/alarme/roteador do sistema Bora. Regra: exit code 0 ou HTTP 200 NÃO prova que o trabalho de dentro correu — já aconteceu 3 vezes em 2 dias (hermes, canal de alarme via curl, roteador de candidatos) o invólucro dizer sucesso com o conteúdo a dizer falha. Sempre verificar o CONTEÚDO da resposta, nunca só o código.
metadata:
  versao: 1.0
  criada: 2026-09-17
  criada_por: vigia-habilidades (corrida 2026-09-17_1141)
  tema: "Falso positivo do invólucro — código de saída/HTTP OK escondendo falha real, repetido 3x em 2 dias em sistemas diferentes"
  origem: texto-automatico-nao-fala-do-danilo
  origem_corrigida_em: 2026-09-17
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# anti-falso-positivo-involucro

> Criada pelo vigia a 17/09/2026 a partir de texto automatico (ordens/despacho/memoria), nao de uma fala literal do Danilo - origem corrigida a 17/09/2026 (ver seccao Origem). A regra mantem-se porque foi validada.

# Anti Falso-Positivo do Invólucro

## Quando usar
Sempre que um script, chamada curl, alarme ou roteador de candidatos disser 'correu bem' — antes de aceitar isso como prova.

## Por que existe
Em 2 dias (registo de 08/09/2026) o mesmo padrão apareceu 3 vezes:
1. O `hermes` saiu com código 0 (sucesso) mas o erro estava escrito dentro da própria resposta.
2. Um `curl` devolveu código de saída 0 sobre um HTTP 401 — o canal de alarme achou que tinha avisado, mas não avisou nada.
3. Um roteador descartou candidatos em silêncio, sem erro nenhum visível, quebrando uma cadeia a jusante.

## Regra
1. Nunca aceitar "exit code 0" ou "HTTP 200" como prova sozinha — ler o CONTEÚDO da resposta/log.
2. Para curl: verificar o código HTTP explicitamente (`-w "%{http_code}"` ou equivalente), nunca só o exit code do curl.
3. Para scripts/roteadores: procurar por mensagens de erro DENTRO do stdout/stderr mesmo quando o exit code é 0.
4. Para qualquer roteador/dispatcher que descarte itens: logar TODO descarte com o motivo, nunca descartar em silêncio.
5. Isto é a mesma regra 4 do CLAUDE.md global ("cuidado com o falso positivo") — esta skill só a torna concreta e testável nos 3 casos já vistos, para não repetir uma 4.ª vez.

## Origem (corrigida a 17/09/2026)
despacho da Claude.ai de 08/09/2026 ('Registar a licao das tres mentiras do involucro') - NAO e fala literal do Danilo; a regra ja esta no ~/.claude/CLAUDE.md seccao 4 (prova material / falso positivo); esta skill e o gatilho pratico.
