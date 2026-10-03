# Testes E2E — o Olho do Bora

> Missão noturna 2026-07-09 Fase 2. Cinegrafista (scrcpy) + Dedos (Maestro) + Runner.
> Fluxos vêm do Córtex: `permanente/semantica/mapa-de-fluxos*.md`.

## Peças
| Ficheiro | Papel |
|---|---|
| `cinegrafista.py` | grava o ecrã por telemóvel/fluxo (scrcpy `--no-playback --record`); sidecar `.json` com `inicio_epoch` para converter timestamp→segundo do vídeo |
| `extrair-frames.py` | falha no passo N → frames [t−3s, t+3s] a 1 fps em `frames/` (ffmpeg) |
| `runner.py` | orquestra: cinegrafista ON → Maestro → `[2-DEVICES]` poll Supabase (read-only) → validação DB → OFF → `resultados-<data>.json` + resumo no inbox do Córtex. **DEFAULT = `--single-device`** (`--two-devices` = modo antigo) |
| `flows/registry.json` | registo dos fluxos (papel→serial, passos, db_checks, `logout_flows`, `manual_2_devices`) |
| `flows/<papel>/*.yaml` | flows Maestro modulares (login/logout = subflows via `runFlow`; `comum/reset-role-screen.yaml` normaliza para o RoleScreen) |
| `criar-contas-teste.py` | cria `teste-estafeta@bora.app` + `teste-parceiro@bora.app` (Auth Admin API; idempotente) |
| `limpar-dados-teste.py` | pós-ciclo: marca `is_test_order=true` + estafeta de teste OFFLINE (nunca apaga — ledger é append-only) |
| `loop-noturno.py` / `run-tudo.cmd` | Fase 7: loop noturno — corre a suite, classifica falha (BUG DO TESTE → afina o YAML · BUG DO APP → zona verde regista / zona vermelha BLOQUEADO-APROVACAO), re-corre só falhados até tudo verde. Parar a meio: criar ficheiro `PARAR` nesta pasta |

## Modo SINGLE-DEVICE (Fase 7, DEFAULT — só 1 telemóvel)
- O runner auto-detecta o telemóvel no adb e corre TODOS os papéis nele, SEQUENCIAIS:
  cliente cria o pedido (cash, conta de teste) → logout (`cliente/logout.yaml`) → login do
  estafeta de teste no MESMO device → aceita → recolhe → entrega → validação no banco.
  O pedido espera na fila do dispatch, por isso a sequência funciona.
- Antes de cada fluxo corre `comum/reset-role-screen.yaml` (logout de quem estiver logado).
- `manual_2_devices: true` no registry = fluxo que EXIGE 2 telemóveis em tempo real
  (ex.: TVDE cliente↔motorista com localização ao vivo) → o runner marca
  **MANUAL-2-DEVICES** no relatório e NÃO o corre (não bloqueia a noite).
- **CONVENÇÃO**: o papel de PARCEIRO nos fluxos é feito no painel admin/web no PC
  (browser), nunca num telemóvel — os devices são só cliente/estafeta.
- O loop noturno NÃO corrige código da app (lib/, supabase/) — só YAMLs de teste;
  bugs do app ficam registados no inbox para o Danilo/loop de ordens.

## Setup que funcionou (Windows, 2026-07-10)
- **scrcpy 4.0**: `winget install Genymobile.scrcpy` (fica em `%LOCALAPPDATA%\Microsoft\WinGet\Packages\Genymobile.scrcpy_*`)
- **Maestro 2.6.1**: zip do release GitHub `mobile-dev-inc/maestro` → `%LOCALAPPDATA%\Programs\maestro` (roda NATIVO no Windows com o JDK 17 já instalado — **não** foi preciso WSL2)
- **MCPs** (para investigação interativa e auto-correção de flows): `claude mcp add maestro -- %LOCALAPPDATA%\Programs\maestro\maestro\bin\maestro.bat mcp` e `npm i -g scrcpy-mcp && claude mcp add scrcpy -- scrcpy-mcp` (ambos registados; ativos na próxima sessão)
- **adb**: `%LOCALAPPDATA%\Android\Sdk\platform-tools` (runner injeta no PATH)

## Telemóveis
| Serial | Modelo | Papel default |
|---|---|---|
| `RZGYB1XQD2P` | Samsung A36 | cliente |
| `N75LTG5X5DSKDMV4` | Xiaomi Redmi | estafeta |

## Gotchas aprendidos
1. **Cinegrafista via CLI standalone morre com o shell pai** (Windows mata a árvore) → 0 bytes.
   Usar SEMPRE em modo módulo (o runner faz isso). `stop()` gracioso = CTRL_BREAK → o mp4
   fecha bem (moov atom).
2. **RAM**: Maestro (JVM) + gradle build + flutter analyze NÃO podem correr em simultâneo
   (malloc fail). Runner põe `JAVA_TOOL_OPTIONS=-Xmx768m`; o loop noturno espera builds.
3. **Encoding**: consola Windows = cp1252 → `sys.stdout.reconfigure(encoding="utf-8")`.
4. **Isolamento de dispatch**: não há raio/zona duro — o runner ABORTA fluxos 2-devices se
   houver estafetas reais online (`PRE-CONDICAO-FALHOU`).
5. **Pagamento em teste = SEMPRE cash (máx €40)**; cartão/MB Way só até ao ecrã de pagamento.

## Regras de prova (Juiz)
Vídeo + frames = nível MÁXIMO de prova (acima de screenshot). O MP4 inteiro fica em
`gravacoes/<data>/<serial>/` como prova para o Danilo; os frames da falha vão para `frames/`.
