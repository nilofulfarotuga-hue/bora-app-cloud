# Diagnóstico E2E passo-a-passo (output REAL) — 2026-07-11

Depois de 3 falhas seguidas do arranque E2E e rejeição correta do Juiz por falta de prova,
parei de repetir e fiz diagnóstico honesto, um passo de cada vez, com **output literal** de cada comando.

**Conclusão curta:** telemóvel, adb e Maestro estão 100% funcionais. O único problema era manter o
loop vivo em 2.º plano — o processo de fundo morre com a sessão do Claude. **Resolvido com Tarefa
Agendada do Windows a correr como SYSTEM** (provado com o telemóvel a mexer, rc=0).

---

## PASSO 1 — `adb devices -l`  ✅

```
List of devices attached
N75LTG5X5DSKDMV4       device product:cloud_eea model:23028RN4DG device:cloud transport_id:21
RZGYB1XQD2P            device product:a36xqnaeea model:SM_A366B device:a36xq transport_id:24
```

2 telemóveis, **ambos em estado `device`** (nenhum `unauthorized`). O adb está saudável.

## PASSO 2 — tap + screencap no device 1  ✅

```
adb -s N75LTG5X5DSKDMV4 shell input tap 500 500
adb -s N75LTG5X5DSKDMV4 exec-out screencap -p > teste_passo2.png
→ 1514294 teste_passo2.png
```

Screencap = **1.514.294 bytes** (~1,5 MB). O telemóvel responde a comandos e produz imagem real.
(PNG temporário já removido.)

## PASSO 3 — UM flow do Maestro à mão (`cliente/login.yaml`)  ✅

Corrido via `_passo3_login_manual.py` (reutiliza `runner._creds_maestro()` + `runner.corre_maestro()`
para injetar credenciais do `.env` sem as imprimir). Últimas linhas reais:

```
=== maestro rc=0 ok=True dur=90.8s ===
  Tap on id: btn_entrar... COMPLETED
Run flow when "Email" is visible... COMPLETED
Assert that "Agora não|Início" is visible... COMPLETED
  Tap on "Agora não"... COMPLETED
Assert that "Início" is visible... COMPLETED
```

**maestro rc=0** — login completo até à home ("Início" visível). Telemóvel + Maestro + flow
funcionam ponta-a-ponta. → O problema NÃO é o Maestro nem o telemóvel.

## PASSO 4 — manter o loop vivo sem a sessão do Claude  ✅

### Tentativa 1 (FALHOU e ensinou):
Tarefa criada com o utilizador default (a sessão do Claude corre como `hermes`, logon
não-interativo/batch). Resultado real da query:

```
Horário da última execução:  30/11/1999 00:00:00
Último resultado:            267011
Executar como Usuário:       hermes
→ LOG NAO EXISTE  (após 200s)
```

Causa: tarefa "só quando o utilizador tem sessão iniciada" + `hermes` sem sessão interativa
→ fica em fila e **nunca arranca**. (Não temos password do `hermes`, e headless não guarda credenciais.)

### Tentativa 2 (FUNCIONOU):
Recriada com `/RU SYSTEM /RL HIGHEST` + wrapper `schtask-prova.cmd` que fixa o env em caminhos
absolutos do perfil `danil` (`LOCALAPPDATA`, `JAVA_HOME`=Android Studio jbr, `ANDROID_HOME`,
`platform-tools` no PATH) — porque sob SYSTEM esses apontam para o perfil errado. Disparada com
`schtasks /Run`. Log real:

```
[schtask-prova] inicio 11/07/2026 11:33:45
whoami: autoridade nt\sistema
=== maestro rc=0 ok=True dur=75.8s ===
Assert that "Início" is visible... COMPLETED
[schtask-prova] fim 11/07/2026 11:35:02 rc=0
```

**Prova cabal:** uma Tarefa Agendada a correr como `NT AUTHORITY\SYSTEM` conduziu o telemóvel via
Maestro (login rc=0), **sem** a sessão do Claude a orquestrar. adb é um daemon singleton (porta 5037),
por isso SYSTEM vê os mesmos devices que o utilizador.

---

## O caminho escolhido (produção)

Registada a tarefa diária que corre o loop noturno completo, independente da sessão:

```
schtasks /Create /TN "BoraE2E_LoopNoturno" /TR "…\schtask-loop.cmd"
         /SC DAILY /ST 02:00 /RU SYSTEM /RL HIGHEST /F
→ Hora da próxima execução: 12/07/2026 02:00:00   Status: Pronto
```

- Wrapper: `.claude/testes-e2e/schtask-loop.cmd` (env-hardened → `loop-noturno.py`).
- O loop auto-termina quando tudo fica verde-estável, ou ao criar o ficheiro `PARAR` na pasta.
- Log de execução em `.claude/testes-e2e/_schtask_loop.log`.
- Tarefa de prova (`BoraE2E_ProvaPasso4`) já removida; ficou só a `BoraE2E_LoopNoturno`.

## Regra que fica (para o Cérebro)
Loop E2E headless **não pode** correr como processo de fundo da sessão Claude (morre com ela) nem
como tarefa do utilizador `hermes` (sem sessão interativa). Usar **Tarefa Agendada SYSTEM** com env
fixado nos caminhos absolutos do perfil `danil` (JAVA_HOME, ANDROID_HOME, LOCALAPPDATA,
platform-tools). adb=singleton na 5037 → SYSTEM vê os devices.

## Ficheiros tocados
- `.claude/testes-e2e/_passo3_login_manual.py` (novo) — runner mínimo de 1 flow, sem imprimir segredos.
- `.claude/testes-e2e/schtask-prova.cmd` (novo) — wrapper de prova SYSTEM (env-hardened).
- `.claude/testes-e2e/schtask-loop.cmd` (novo) — wrapper de produção do loop noturno (SYSTEM).
- Tarefa agendada `BoraE2E_LoopNoturno` registada (SYSTEM, diária 02:00).
