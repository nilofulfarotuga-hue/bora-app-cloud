---
id: relatorio-e2e-login-sync-2026-07-10
tipo: relatorio
origem: [Tarefa 1 missão 3-em-1 2026-07-10 — fix login E2E]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: verificado
---

# ✅ Relatório — Fix login E2E (Tarefa 1)

## Causa raiz (confirmada, determinística)
**Divergência banco↔runner:** a password de `teste-cliente@bora.app` foi rodada no banco
fora do fluxo, sem atualizar `.claude/testes-e2e/.env` → o Maestro digitava a password
antiga → `AuthApiException invalid_credentials 400` (visto no logcat dos DOIS devices).
O REST validava 200 com a password do momento — mascarando o problema.

## O que foi feito (na ordem da tarefa)
1. Password lida do `.env` (fonte da verdade; 13 chars "Bora…").
2. Banco sincronizado com o `.env` via Auth Admin API (equivalente ao `UPDATE ... crypt()`),
   HTTP 200.
3. Validação `signInWithPassword` = **200 ANTES** do Maestro.
4. Nota canónica criada: `permanente/semantica/credenciais-teste.md` (regra: quem muda a
   password no banco atualiza o `.env` no MESMO ato; smoke com invalid_credentials → 1.º
   verificar o sync, só depois culpar o Maestro).
5. **Smoke `smoke-login-cliente`: PASSOU (326 s, 1/1 verde)** — entrada na Área do Cliente
   confirmada no banco/asserts do runner. Suite single-device `--todos` disparada a seguir
   (resultado em `inbox/e2e-resultados-2026-07-10.md`).

## Melhorias de robustez que ficaram (da investigação)
- `flows/cliente/login.yaml`: campos por **ID Semantics** (`fld_email`/`fld_password`/
  `btn_entrar`) + password digitada em 3 blocos com pausa (mitiga char-dropping de
  inputText em campos obscureText).
- `runner.py`: injeta blocos `CLIENT_PW_A/B/C` e `DRIVER_PW_A/B/C`.

## Bugs/factos fora do escopo
- `teste-estafeta@bora.app` NÃO existe no Supabase Auth (drivers usam email sintético
  `{phone}@driver.bora.app`) — o fluxo de login do estafeta na suite valida/expõe isto.
- Trilha de diagnóstico anterior (falsas pistas descartadas): APK sem defines (não — build
  396 CI), internet do device (ok), GPM overlay (não), maxLength (não existe).

---

## 2ª confirmação — re-run 2026-07-10 (executor headless)
Re-validação determinística de que o sync se mantém (nenhuma alteração necessária):
- **Banco** (SQL via MCP service_role): `teste-cliente@bora.app` →
  `encrypted_password = crypt('BoraTeste2026', encrypted_password)` = **true**, confirmado,
  não banido. `auth.users` NÃO tocado (só SELECT).
- **`.env`**: `E2E_CLIENT_PASSWORD=BoraTeste2026` — idêntica ao banco. ✅
- **AUTH REST** `signInWithPassword` (anon key): **HTTP 200**, `access_token` presente,
  `bora_role=client`. ✅
- Password antiga `0yKWYUNgzrbjOMv1jQnlApu...`: grep vazio em todo o repo — era efémera
  (gerada por `criar-contas-teste.py` antes de o `.env` ser fixado).
- **Launch smoke** device cliente Samsung `RZGYB1XQD2P`: app `pt.boraapp.bora` instalada e
  arranca (`ResumedActivity = .MainActivity`). ✅
- **Suite Maestro UI não corrida neste run**: executor headless sem Python nem Maestro
  (`runner.py`/`loop-noturno.py` dependem de ambos). Correr `run-tudo.cmd` numa máquina com
  Python + Maestro para a suite completa — dados e fix de digitação já em vigor.
- Nota canónica confirmada: `permanente/semantica/credenciais-teste.md` (duplicado
  `credenciais-teste-e2e.md` criado por engano neste run foi removido).
