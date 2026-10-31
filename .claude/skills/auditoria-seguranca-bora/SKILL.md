---
name: auditoria-seguranca-bora
description: "Auditoria de segurança, só de leitura, às NOSSAS coisas: o site boraguarda.com, o APK pt.boraapp.bora e as Edge Functions do Bora. Método da skill security-audit da Cloudflare (reconhecimento, hipóteses, validação, relatório) com o script auditar-site.mjs e o REA pela linha de comandos. Nunca aponta a apps ou sites de terceiros. Usar quando o Danilo pedir uma auditoria, um teste de segurança ou perguntar se o site está seguro."
---

# Auditoria de segurança do Bora (só leitura)

Escrita por nós, a partir do método da skill `security-audit` da Cloudflare (texto completo em
`C:\Users\danil\ferramentas\dsh-plugins\cloudflare__security-audit-skill\skills\security-audit\`: ler `SKILL.md`,
`WEB-PROTOCOL-AND-AUTH.md` e `ATTACK-CLASSES.md` só se a auditoria for funda). Aqui está o essencial.

## Âmbito (nunca sair daqui)
- **Site:** `boraguarda.com` e subdomínios `*.boraguarda.com`.
- **Nossa API:** `ojykpzwqrtusfeakzrna.supabase.co` (só pedidos simples sem credenciais, para ver o que está aberto).
- **Nosso APK:** `pt.boraapp.bora` (ficheiros em `C:\BoraLocal\projetosflutter\bora_app`, leitura estática).
- **Nossas Edge Functions:** o código em `supabase/functions/` (leitura) e a lista pelo MCP do Supabase (só leitura).
- **Nunca** apps ou sites de terceiros (iFood, Glovo, Uber Eats, concorrentes): regra do Danilo. A guarda do Dipsy
  barra o REA e o script se o alvo não for nosso.

## Regras de ouro
1. Só leitura: GET, HEAD e OPTIONS simples. Nada de explorar falhas, adivinhar palavras-passe, forçar entradas,
   inundar de pedidos, nem usar credenciais de ninguém.
2. Um achado só conta com prova concreta (o pedido e a resposta que o mostram). Sem prova é "por confirmar".
3. Nunca copiar segredos para o relatório: se vires uma chave, regista só onde está e que tipo é.
4. Corrigir não faz parte: dá a correção mais pequena possível. Mexer em dinheiro, Stripe, RLS ou despacho é
   do Claude Code e do Danilo.
5. Cada achado vai para o `e2e_log` (fluxo da missão, passo `auditoria-<alvo>-N`) e para o relatório.

## Como fazer (por ordem)
1. **Reconhecimento do site (feito pelo nosso script):**
   `node C:\Users\danil\.dsh\skills-ponte\auditoria-seguranca-bora\scripts\auditar-site.mjs boraguarda.com`
   Devolve JSON: cabeçalhos de segurança (HSTS, CSP, anti-framing, referrer, permissions), HTTP para HTTPS, cookies,
   CORS, TLS, ficheiros que não deviam estar públicos (`.env`, `.git`, mapas de código…), conteúdo misto, scripts
   de terceiros sem SRI. Recusa domínios que não são nossos.
2. **REA pela linha de comandos** (só para o que é nosso). Usa o nosso envólucro, que corre o REA 6.8.0 já instalado
   (sem npm, sem downloads, com o Node portátil certo):
   `powershell -NoProfile -File C:\Users\danil\.dsh\rea-bora.ps1 <comando>`. Comandos úteis: `doctor` (estado),
   `capture-web-screenshot https://boraguarda.com/`, `decode-android-resources <nosso.apk>`,
   `inspect-apk-signature <nosso.apk>`; `--help` em qualquer um mostra as opções.
   O REA já está instalado e registado (a 26/10): **não corras `setup`** nem `npx rea-agents` (o npm não pode escrever
   na cache dentro do sandbox, e o `setup` mexe nas configurações dos agentes). A skill `reverse-engineer-anything`
   explica o REA por inteiro. A guarda recusa qualquer alvo que não seja nosso.
3. **Edge Functions (leitura estática):** em `supabase/functions/`, procurar: funções sem verificação de quem chama,
   `verify_jwt` desligado sem motivo, segredos no código, SQL montado com texto do utilizador, CORS aberto em
   funções que escrevem. As de dinheiro (`stripe-webhook`, `create-payment-intent`, `dispatch-engine`…) só se
   leem e se reportam.
4. **Triagem:** ordenar por severidade (alta, média, baixa, informativa). Alta = dá acesso ou dinheiro a quem não
   devia. Para cada um: o que é, a prova, o risco em português simples, a correção mais pequena.
5. **Relatório:** ficheiro `.claude/.ai/reports/auditoria-<alvo>-<AAAA-MM-DD>.md` (texto corrido, sem jargão para o
   resumo; os detalhes técnicos por baixo) e uma linha por achado no `e2e_log`.

## Formato de um achado
`[severidade] título curto` / **Onde:** URL, ficheiro ou função / **Prova:** o pedido e a resposta (sem segredos) /
**Risco:** uma frase simples / **Correção:** a mais pequena que resolve.
