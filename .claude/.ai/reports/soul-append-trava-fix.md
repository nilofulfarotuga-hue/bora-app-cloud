<!-- TRAVA-HOOK-FIX-2026-07-08 -->
## 🔒 Lição — TRAVA (protege-banco.sh) e paths de hook (2026-07-08)
- **Sintoma:** `bash: .claude/hooks/protege-banco.sh: No such file or directory` em chamadas Bash do deploy.
- **Causa-raiz:** hook registado com **path RELATIVO** em `.claude/settings.json` + um `cd` para
  subpasta (`hermes/socio-ai`) que **persistiu** como cwd da sessão Bash → o hook correu de cwd
  errado → não achou o script → non-blocking → **guarda de DB saltada** nessas chamadas.
  O script em si está 100% (7/7 testes: bloqueia git-hard/DROP-financeiro/deploy-protegido/DDL-money;
  deixa passar SELECT/echo/view read-only).
- **Correção:** path **ABSOLUTO** no comando do hook. Proposta em `.claude/settings.proposto.json`
  (a Trava bloqueia o agente de editar o `settings.json` vivo — precisa de ato manual do Danilo + restart).
- **Path correto:** `bash /c/Users/danil/Desktop/projetosflutter/bora_app/.claude/hooks/protege-banco.sh`
- **Regra futura em deploys:** NUNCA `cd` para subpasta em Bash; usar paths absolutos / `git -C`.
<!-- /TRAVA-HOOK-FIX-2026-07-08 -->
