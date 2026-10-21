# Relatório N5 — e-mail próprio para cada agente (boraguarda.com)

Missão geral-noite-2026-10-21, bloco N5 (agente-email-n5). 21/10/2026, 20:44–21:35 (hora de Lisboa).
Autorização: missão agentes-email-2026-10-21 (Danilo, 21/10 07:58) reafirmada às 20:15 na missão geral-noite.
Registo detalhado: `e2e_log`, fluxo `fechar-pendencias-20-10`, passos `N5-*`, run_id `geral-noite-2026-10-21`.

## Para o Danilo (ler em voz alta)

Fiz isto: cada agente já tem o seu e-mail na boraguarda.com — emerson, suporte, parceiros,
vendas, redes, radar e assinaturas. Um e-mail que chega de fora entra na caixa certa, com os
anexos guardados num cofre privado. O Emerson já lê e responde sozinho a partir da VPS, e a
resposta sai com o endereço do agente. No painel admin há um ecrã novo, "E-mail dos agentes",
onde vês a caixa de cada um, os enviados, abres os anexos, respondes, e ligas ou desligas tudo.
Testei a volta inteira: um único e-mail para o emerson, o suporte e o radar entrou uma vez em
cada caixa; o Emerson respondeu e a resposta chegou do outro lado, na mesma conversa.

Falta isto: o teste com o teu Gmail pessoal. Mandar um e-mail a partir do teu Gmail (ou para ele)
é falar em teu nome, e isso só faço com o teu sim aqui na conversa. Se disseres "pode", mando um
"[teste agentes]" do teu Gmail para o emerson@ e confirmo que a resposta te chega.

Erros que encontrei pelo caminho: a chave do servidor não está dentro do contentor do Emerson
(só no anfitrião da VPS). Em vez de a copiar, montei uma "ponte": o Emerson deixa o pedido numa
pasta e a VPS responde. Também: as chaves da Cloudflare guardadas no PC não podem mexer no
encaminhamento de e-mail, por isso essa parte foi feita no Chrome, no teu perfil pessoal.

Próximo passo: o teu sim para o teste com o Gmail, e o revisor passar os 5 registos antes de
irem para o ar.

## O que ficou feito, com prova

| Bloco | Estado | Prova |
|---|---|---|
| B1 banco | confirmado, não recriado | 3 migrações 20261021112939/113238/113320 no banco; md5 dos ficheiros = statements (718ac15e…, 8b27342b…, bf3d9c06…) |
| Ajustes | aplicado | `agentes_email_ajustes` = versão 20261021194537, md5 408743b7dc4b35a5dcb4bc116e200772 igual ao ficheiro; índice único (direcao, agente, message_id); authenticated só SELECT/UPDATE; política de leitura dos anexos para admin; `agentes_email_resumo()` |
| Edge receber | no ar, verify_jwt=false | sem segredo 403; segredo errado 403; segredo certo + endereço desconhecido 404; e-mail real 200 |
| Edge enviar | no ar, verify_jwt=true | sem auth 401 (portão); anon 403; sb_secret 400 (agente inválido = passou a porta); service_role legada 400 idem |
| Worker Cloudflare | publicado | `agentes-email`, handlers email+fetch, secret AGENTES_EMAIL_SEGREDO (secret_text), workers.dev desligado |
| Email Routing | ligado | MX route1/2/3.mx.cloudflare.net, SPF da raiz, DKIM cf2024-1; catch-all → Worker, Ativo; `_dmarc` = `v=DMARC1; p=none` |
| Registos do Resend | intactos | resend._domainkey (id 4762530b), MX de send. (94ab29f8) e SPF de send. (c2c9afd2) iguais antes e depois |
| VPS | instalado | `hermes-email` no contentor e no host; `agentes-email-ponte.path` active; bloco no SOUL.md (cópia SOUL.md.bak-agentes-email-20261021) |
| Painel admin | pronto | `/admin/agentes-email` + item no menu; analyze 0 avisos no ecrã novo; teste do menu verde (18) |
| Prova de ponta a ponta | provada (sem Gmail) | ver abaixo |

### Volta completa (21/10, UTC)

- 20:11:19 o Emerson, dentro do contentor: `hermes-email enviar vendas "emerson@…, suporte@…, radar@…" "[teste agentes] ida 21-10 2115" …` → Resend 01a16016-…
- 20:11:21 entrou uma vez em cada caixa, com o mesmo Message-ID: radar ef430204, emerson 19b5ed6a, suporte 2a581aa0.
- `hermes-email caixa emerson` → 1 novo; `hermes-email ler 19b5ed6a-…` → marcado lido;
  `hermes-email responder 19b5ed6a-… "Recebido, obrigado…"` → saída 1ffe2a48 "Re: [teste agentes] ida 21-10 2115".
- 20:11:39 a resposta chegou à caixa vendas (1252f582) com `em_resposta_a` = Message-ID do original; o original ficou "respondido" (tratado).
- Antes, prova directa da Edge: mesmo e-mail para emerson repetido → "duplicado"; HTML sem texto + PDF → texto tirado do HTML e anexo guardado; repetido sem Message-ID → "duplicado" pelo resumo SHA-256.
- Todas as linhas de teste ficaram **arquivadas** (nada apagado).

### RLS (prova em rollback)

Admin vê 9 linhas, resumo de 4 caixas, consegue mudar o estado (7), vê o anexo no storage; inserir é
recusado (42501). Utilizador que não é admin vê 0 linhas.

## Commits (ramo agentes-email-21-10, por cima de origin 72ebbd1e, sem push)

- 0536dea6 feat(agentes-email): caixa de e-mail dos agentes no banco (B1 + ajustes)
- e9572338 feat(agentes-email): Edge Functions receber e enviar
- 6da722dc feat(agentes-email): Worker da Cloudflare que entrega o e-mail cru a Edge
- 85816e20 feat(agentes-email): comando hermes-email do Emerson na VPS
- 4ffcbeaa feat(admin): ecra E-mail dos agentes (caixa, enviados, anexos, responder)

## Fiscal de segurança

- Nenhum segredo em ficheiro versionado (varrido o diff dos 5 commits: sb_secret, eyJ, re_, hex de 64, chaves privadas → nada).
- O segredo do Worker veio do cofre para o PC cifrado com uma chave PGP descartável (nunca apareceu
  em texto), foi posto só como secret do Worker, e a cópia local e a chave descartável foram apagadas.
- Tabela com RLS ligada (só admin); bucket privado; `get_agentes_email_key()` só service_role.
- verify_jwt de propósito: false só no receber (porta = segredo em tempo constante), true no enviar.
- Nenhum dado pessoal em sítio público. O Gmail do Danilo não foi usado.

## Notas técnicas

- A chave do servidor no host da VPS (`/opt/assistente-negocio/.env`) é a service_role **legada** (JWT).
  A Edge aceita-a só depois de confirmada no Auth. No dia em que as chaves legadas forem desligadas,
  trocar essa linha pela `sb_secret` (a ponte já prefere `SUPABASE_SECRET_KEY` se existir).
- O `/usr/local/bin` do contentor perde-se se a imagem for recriada; o SOUL.md ensina o caminho que fica
  (`python3 /opt/data/bin/hermes-email`). Reinstalar: `bash /tmp/agentes-email-inst/instalar.sh` com os
  ficheiros de `hermes/agentes-email/`.
- Catch-all em vez de 7 regras: cobre os 7 endereços e postmaster@/abuse@ (vão para o emerson);
  qualquer outro endereço recebe 404 da Edge e o Worker recusa-o.
- Pequeno detalhe que fica: entidades HTML como `&oacute;` não são convertidas no texto tirado do HTML.

## PARA O DANILO

- Posso mandar um "[teste agentes]" do teu Gmail pessoal para emerson@boraguarda.com e ver a resposta
  chegar ao teu Gmail? (precisa do teu sim aqui, porque é um envio em teu nome)
