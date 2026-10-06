# Diagnóstico — porque é que o sistema trava e pede cliques (06/10/2026)

> Missão `quatro-blocos-06-10`, Bloco D. **Só diagnóstico: nada foi alterado** no Windows, no
> Chrome, na app Claude, nem se criaram tarefas. A próxima missão aplica as correções que o
> Danilo escolher, sem repetir esta investigação.
>
> Pedido do Danilo (06/10): *"toda hora precisa da minha autorização, toda hora some um negócio do
> PC… eu fico com o PC ligado 24 horas. Eu quero que seja automático."*

## Resumo numa frase

**O PC está sem memória.** Tem 13,7 GB de RAM, mas a memória comprometida estava em **54,5 de
55,7 GB** (quase tudo em ficheiro de paginação) e havia **~200 MB livres**. Quase todos os
sintomas de hoje — sessão que cai, extensão que desliga, vigia que diz que a VPS morreu — saem
daqui. Não foi suspensão do Windows: hoje o PC **não suspendeu nenhuma vez**.

## Quem está a comer a memória (medido às 15:20)

| O quê | Quanto | Desde quando |
|---|---|---|
| **Windows Terminal** (um só processo, PID 11584) | **12,8 GB** comprometidos | aberto desde 30/09 20:51 (6 dias) |
| **40 processos `claude.exe`** (9–10 sessões vivas ao mesmo tempo, mais as tarefas `ClaudeRC-bora` e `ClaudeRC-emdia`) | **17 GB** comprometidos, 2,6 GB em uso | — |
| **Ollama** a servir `qwen2.5:7b-instruct` | **5,5 GB**, a **100 % de CPU** | carregado às 06:33; a VPS chama-o pelo túnel `tunel-ollama-vps` e mantém-no sempre quente |
| McAfee (`mc-fw-host.exe`) | 1,4 GB | — |

O Windows registou **12 avisos de "falta de memória virtual"** só hoje (evento 2004), todos a
apontar os mesmos culpados: Windows Terminal 13 GB, llama-server (Ollama) 5,6 GB, McAfee 1,4 GB.
A app Claude registou hoje **299 avisos de pressão de memória "crítica"** e 386 de "aviso".

## 1. Porque é que a sessão do Claude Code cai ("Não foi possível alcançar Danilo")

**Causa provada:** às **12:19:34** o registo da app (`%LOCALAPPDATA%\Claude\logs\main.log`) diz
`[WarmLifecycle:session] Idle timeout reached, disconnecting local_…` — a app **desligou a sessão
por estar 15 minutos (900 s) parada**, em plena pressão de memória crítica (às 12:14–12:21 a
linha `memory pressure (critical)` repete-se de 30 em 30 s). É o minuto exato em que a sessão do
Jai caiu. Isto acontece ~4 vezes por hora (62 desligamentos hoje).

Outras provas no mesmo registo:
- 09:32:12 — a rede da própria app falhou com `net::ERR_INSUFFICIENT_RESOURCES` e um processo do
  Claude Code morreu (`exited with code 3`).
- A ligação remota (`remote-tools-device`) fechou-se de forma anormal (código 1006) 5 vezes hoje
  (00:56, 08:04, 12:50, 13:32, 13:38) e religou-se sozinha em 1–4 s.
- **Atualização pendurada:** a versão 2.19675.1 está descarregada e à espera de reinício há
  **98 horas** (`Deferring auto-restart after 98 hours: Claude is working`). A app instalada é a
  2.16120.0.0. No dia em que o Claude parar de trabalhar uns minutos, a app reinicia sozinha e
  derruba todas as sessões de uma vez.

**Não é:** suspensão (hoje 0 eventos de suspensão; suspender em corrente = "Nunca"; ecrã desliga =
"Nunca"), nem atualização do Windows (houve instalações às 10:05–10:48 mas sem reinício).

**Nota de 02/10:** nesse dia o PC suspendeu às 16:57 com **razão "Battery"** e só acordou às
21:04 quando alguém carregou no botão. Ou seja: o carregador saiu da tomada ou faltou a luz.
Num portátil, isso volta a acontecer sempre que ficar sem corrente.

## 2. Porque é que a extensão Claude in Chrome desliga

Hoje: **11 vezes** `Chrome extension disconnected from bridge` (03:29, 03:38, 03:45, 04:21,
04:23, 08:56, 09:20, 09:32, 09:34 ×2, 13:29). Em 7 delas ela religou-se sozinha
(`Previously selected extension reconnected`).

Causas encontradas, com prova:
1. **Poupador de memória do Chrome LIGADO** (`Local State → performance_tuning.high_efficiency_mode.state = 2`).
   Com a máquina sem memória, o Chrome descarta separadores e encerra o trabalhador de fundo da
   extensão — o anfitrião nativo regista `Chrome disconnected (EOF received)` (09:34:03).
2. **O anfitrião nativo da extensão não se consegue atualizar:** 26 vezes hoje
   `[Chrome Extension MCP] Failed to copy native host binary: Error: EBUSY: resource busy or locked`
   — o ficheiro está preso por um processo antigo, por isso a extensão fala com um binário de
   uma versão anterior da app.
3. **Dois perfis com a extensão** (Danilo e Bora, versão 1.0.98 nos dois): várias quedas ficam
   com `selected=none` — a app perde qual dos dois está escolhido e é preciso voltar a selecionar
   pelo `deviceId`.
4. A pressão de memória do ponto 1 (a extensão vive dentro do Chrome, que também é cortado).

## 3. O que impede a automação em separadores escondidos

- **Poupador de memória ligado** (acima): o separador em segundo plano é congelado ou descartado.
- O Chrome **não desenha** separadores que não estão à frente nem janelas tapadas/minimizadas
  (oclusão nativa) — daí as capturas "0 width" e os cliques que não chegam ao Search Console.
  É o que as memórias `aba-do-chrome-colapsa-para-zero-por-zero` e
  `aba-hidden-resolve-se-com-foreground-e-ctrl9` já descreviam; hoje a falta de memória agrava.
- O separador novo da extensão nasce em segundo plano (regra conhecida).

## 4. O alarme "A VPS deixou de responder" (13:13)

Foi **falso**. A VPS esteve sempre ligada (22 dias sem reiniciar). Nas janelas em que o vigia
disse "morta" (04:42–07:08, 07:40–10:08, 12:08–13:07 UTC), a VPS **não recebeu nenhuma tentativa**
de ligação — o pedido nem saiu do PC. O vigia (`BoraVigiaVPS`, de 30 em 30 min) chegou a correr
65 s e até 5 min depois da hora marcada, por falta de memória, e o `ssh` com limite de 25 s
morreu antes de sair. O vigia desiste à primeira falha e não guarda o erro.

**Achado ao lado:** o túnel do Ollama para a VPS está em ciclo: entre as 12:19 e as 12:59 UTC a
VPS aceitou **70 ligações SSH** do PC, cada uma a falhar com `bind 172.16.1.1:11434: Address
already in use` — a porta na VPS ficou presa a um túnel antigo e o guardião (`GuardiaoTunelOllama`)
tenta de novo a cada ~15 s.

## Hostinger

Verificado só **se existe** palavra-passe guardada (sem abrir nada, sem fazer login):
`~\.credenciais`, `~\.bora-cofre`, `~\.bora`, `~\.claude\contas\segredos` → **0** ficheiros com
"hostinger"; Chrome Danilo e Bora, gestor local **e** palavras-passe da conta Google → **0**
entradas Hostinger. **Resposta: NÃO há.** Pela memória de 09/09, o hPanel entra com "Entrar com
Google" (sem palavra-passe) — basta esse login uma vez no perfil certo.

## Correções propostas (por ordem de efeito) — NADA aplicado

| # | O que mudar | Onde | Porquê |
|---|---|---|---|
| 1 | **Fechar e reabrir o Windows Terminal**; passar os ciclos que lá correm para tarefas escondidas com registo em ficheiro (ou limitar `historySize`, hoje no padrão 9001 linhas por separador) | Windows Terminal | Liberta ~13 GB de uma vez; é o maior consumidor |
| 2 | **Ollama:** `OLLAMA_MAX_LOADED_MODELS=1`, `OLLAMA_NUM_PARALLEL=1` e `OLLAMA_KEEP_ALIVE=5m`; ou tirar o modelo do PC se a VPS não precisa dele 24 h | variáveis de utilizador + reiniciar Ollama | 5,5 GB e 100 % de CPU sempre ocupados |
| 3 | **Túnel do Ollama:** na VPS, `ClientAliveInterval 30` + `ClientAliveCountMax 3` no `sshd_config`; no PC, o túnel com `-o ExitOnForwardFailure=yes` e espera crescente entre tentativas | VPS + script do túnel | Acaba com as 70 ligações/hora a falhar e a porta presa |
| 4 | **Reiniciar a app Claude num momento calmo** (aplica a 2.19675.1 pendente há 98 h) e arquivar as sessões paradas (hoje 9–10 vivas) | App Claude | Evita o reinício-surpresa; menos 17 GB de sessões |
| 5 | **Desligar o Poupador de memória** nos dois perfis do Chrome, ou pôr exceções: `search.google.com`, `hpanel.hostinger.com`, `canva.com`, `claude.ai`, `business.facebook.com`, `play.google.com` | Chrome → Definições → Desempenho | Para de congelar os separadores que a automação usa |
| 6 | Depois do #4, **fechar todas as janelas do Chrome uma vez** e reabrir | Chrome | O anfitrião nativo da extensão sai do "EBUSY" e passa à versão nova |
| 7 | **Vigia da VPS:** 3 tentativas com 60 s de intervalo, guardar o erro do `ssh`, e medir a memória do PC antes de gritar | `orquestracao/vigia-vps.sh` | Acaba com os alarmes falsos |
| 8 | **Carregador sempre ligado**; na falta de luz, definir "ação de bateria crítica = hibernar" (não suspender) | Windows → Energia | O 02/10 parou 4 horas por bateria |
| 9 | Ver se o McAfee é preciso (o Windows Defender já protege) | Apps | Mais 1,4 GB |

O plano de energia **já está bem** em corrente: suspender = Nunca, ecrã = Nunca, Wi-Fi em
desempenho máximo. Não é aí que está o problema.

## Como se mediu (para repetir)

- Memória: `(Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes` e `Win32_OperatingSystem` (commit).
- Eventos: `Get-WinEvent -FilterHashtable @{LogName='System'; Id=2004}` (falta de memória) e `Id=42,107,506,507,1` (suspensão).
- App Claude: `%LOCALAPPDATA%\Claude\logs\main.log` (procurar `Idle timeout reached`, `memory pressure`, `updater`, `disconnected from bridge`, `EBUSY`).
- Chrome: `User Data\Local State` → `performance_tuning`; `Login Data` / `Login Data For Account` só contagem por domínio.
- Ollama: `ollama ps`. Túnel: `journalctl -u ssh` na VPS.
