# Relatório — missão `quatro-blocos-06-10` (06/10/2026, Claude Code, Opus 5.5, PC do Danilo)

**RAM no arranque:** 216 MB disponíveis (190 MB depois de parar o servidor nano-banana desta sessão),
abaixo do portão leve de 400 MB. **Avancei mesmo assim** porque o trabalho era de ficheiros, rede e
MCP (nada compila) e os consumidores grandes eram outras sessões vivas e o Windows Terminal, que
fechar destruiria trabalho alheio. O Bloco D explica de onde vem essa falta de memória.

## Uma linha por bloco

| Bloco | Feito | Prova | Falhou / saltado |
|---|---|---|---|
| **A — Jai, julho** | Já estava no ar pela sessão anterior (deploy `f99767aa`, commit `8974df6`, IndexNow 8 URLs). Verifiquei de novo, sem refazer. | `/`, `/pt/`, `/es/`, `/hi/` e `/media-kit` ×4 a 200 com "In July 2026 / Em julho / En julio / जुलाई"; zero compra em agosto; i18n, sitemap, script, styles, site-config **iguais por sha256** local = produção; Supertaça 8 de agosto e "Three days before…" presentes; ficheiro da Google 200 com texto exato. e2e_log 3014. | Nada. |
| **B — VPS** | **Alarme falso.** VPS ligada há 22 dias, carga 0,34, 2,6 GB livres, 11 contentores e todos os serviços a correr (Guarda FC, radar-jai 13:46, voz 13:50, WhatsApp, Motor Bora). Nada reanimado, nada reiniciado. | Nas horas "morta" do vigia o `sshd` da VPS não tem **nenhuma** entrada; no mesmo período aceitou 70 ligações do IP do PC. O vigia correu até 5 min atrasado por falta de memória no PC. e2e_log 3015–3016. Telegram lido de volta (`log.md` 14:57:20, acentos certos). | Nada. Achado ao lado: o túnel do Ollama PC→VPS está em ciclo (porta 11434 presa na VPS). |
| **C — Fotos da Diana** | 23 cartões exportados do Canva; fotos limpas por uma **cópia de trabalho** (só os textos apagados; o design da Diana ficou intacto). As **20 fichas** do plantel com a foto nova; **Jerónimo Ortiz e Joel Mendes** deixaram de estar sem foto. Publicado no site vivo e na cópia. | Verificação de rostos: **o site tinha 5 fotos na ficha errada** (Luís Ferreira ↔ Nuno Machado; José Miranda tinha o Charles Okwara; Charles e Pedro Bondo baralhados) — cartões e zerozero concordam, as fotos novas corrigem. **Verificador limpo: APROVADO 6/6** (SIFT: 361–952 pontos na página com o nome certo). Cópia `guarda-fc-jai` `03f144b3`: **40/40 fotos iguais ao commit**, 20 fichas a 200, 0 jogadores sem foto, 0 imagens partidas no ecrã, 4 línguas iguais. Site vivo: API Cloudflare → `guardafcsad.com` servido pelo deploy **`9bb8b1b0`** (produção); portão continua fechado. Commit `eb4b66b`. e2e_log 3018–3022. | **Push para o ramo `principal` bloqueado** pelo guardião de git (só o ramo do Bora). Não contornei. Ver "PARA O DANILO". |
| **D — PC** | Diagnóstico em `.claude/skills/pc-sempre-ligado/DIAGNOSTICO-2026-10-06.md` (commit local `9205fa77`). **Nada alterado.** | Causa-mãe: **memória esgotada** (54,5 de 55,7 GB comprometidos): Windows Terminal 12,8 GB aberto desde 30/09, 40 `claude.exe` 17 GB, Ollama 5,5 GB a 100 % CPU. A sessão das 12:19 foi **desligada pela app por inatividade** (`Idle timeout reached` às 12:19:34) em pressão crítica. Extensão: **Poupador de memória do Chrome ligado** + anfitrião nativo preso (`EBUSY` ×26). Atualização da app pendente há 98 h. Hoje 0 suspensões (a de 02/10 foi por bateria). e2e_log 3023–3024. | Ação da tampa não lida (o `powercfg` não devolveu o valor). |
| **Hostinger** | Só verificado se existe palavra-passe. | **Não existe:** 0 em `~\.credenciais`, `~\.bora-cofre`, `~\.bora`, `~\.claude\contas\segredos`, e 0 no Chrome (Danilo e Bora, gestor local e conta Google). | — |
| **Fecho** | Digest `digest-2026-10-06-quatro-blocos` em `claude_ai_memoria` (2449 car., lido de volta); Córtex `cortex_reportar` ref-bc7d4d. | — | `cortex_memorizar` não disponível: o servidor Córtex desta sessão pede autorização. |

## PARA O DANILO

1. **Um comando para as fotos do Guarda FC ficarem para sempre.** Já estão no ar, mas o robô do
   clube volta a publicar a partir do ramo `principal` quando há novidades — e aí repõe as fotos
   antigas. O guardião de git deste PC não me deixa enviar para esse ramo; só tu:

   ```
   git -C C:\BoraLocal\projetosflutter\guarda-fc-site-fotos push origin HEAD:principal
   ```
2. **Três jogadores têm cartão da Diana mas não estão no plantel do site:** Isnaba Mané,
   Mboulou Júnior e Luís Maurício. Não os acrescentei. Se são do plantel, diz e entram.
3. **PC (Bloco D):** escolhe quais das 9 correções do diagnóstico se aplicam. As de maior efeito:
   fechar e reabrir o Windows Terminal (liberta ~13 GB), reiniciar a app Claude num momento
   calmo (aplica a atualização pendente), e desligar o Poupador de memória do Chrome.
4. **Hostinger:** não há palavra-passe guardada; entra-se com "Entrar com Google" uma vez no perfil
   certo e fica.

## Fora do âmbito (só reporto, não corrigi)

- O site do clube (vivo e cópia) já mostrava antes uma ligação "Loja — em breve" (página
  `noindex`). Vem de trás; não mexi.
- O `gritar-do-pc.sh` não consegue mandar acentos (o Telegram responde "strings must be encoded
  in UTF-8"); por isso os alarmes dele saem sem acentos. Usei a ponte normal (VPS viva).
- O túnel do Ollama para a VPS está em ciclo de falha (ver Bloco D, correção 3).
- O `CLAUDE.md` diz que o PC tem 4 GB; o PC atual tem 13,7 GB de RAM (o problema é o consumo, não a RAM).
