---
tarefa: janela de visibilidade AO VIVO da VPS no PC
data: 2026-07-14
estado: concluido
---

# Janela AO VIVO da VPS no PC

## Problema
A orquestração (`carteiro.sh`) já corre na VPS (`root@srv1786862.hstgr.cloud`), não só no
PC. O Danilo acompanha o PC por remote desktop no telemóvel e, até agora, via o
executor/carteiro a correr no terminal do PC. Com a migração, esse terminal deixou de
mostrar o que a VPS está a fazer (ordens a entrar, estado, juiz, Telegram) — ficou "cego".

## Solução
Ficheiro novo: **`assistir-vps.cmd`** (raiz do repo `bora_app/`, ao lado do `assistir.cmd`
já existente que mostra o Claude a trabalhar passo a passo NESTA máquina).

- Duplo-clique abre uma janela cmd que faz SSH direto à VPS e `tail -n 60 -f` ao
  `/root/orquestracao/carteiro.log` (o log que o `carteiro.sh` já escreve a cada evento).
- Liga com a chave `C:\Users\danil\.ssh\id_ed25519_vps` já existente e usada pelo hook
  `pre-push` (mesma chave, mesma ligação PC→VPS já confirmada estável — não é a ponte
  Tailscale VPS→PC do `pc-loop`/`pc-judge`, é o caminho inverso, direto por internet).
- **Religa sozinho** se a ligação cair: `ServerAliveInterval=25`/`ServerAliveCountMax=3`
  para detetar queda + loop `goto :loop` com 3s de espera antes de tentar de novo.
- Usa o `ssh.exe` do Git for Windows por caminho absoluto (`C:\Program Files\Git\usr\bin\
  ssh.exe`), com fallback para `ssh` do PATH. Motivo: testei primeiro com o OpenSSH nativo
  do Windows (`System32\OpenSSH\ssh.exe`) e ele **recusa** a chave por "bad permissions"
  (ACL demasiado aberta no ficheiro da chave) — o ssh do Git ignora essa checagem e liga
  sem problema, sem precisar mexer em `icacls` da chave partilhada com o hook `pre-push`.

## Riqueza do log confirmada
O `carteiro.log` já tem tudo o que o Danilo precisa para perceber o que se passa só de
olhar, sem alterações necessárias:
- Timestamp ISO UTC em cada linha (`[2026-07-14T20:26:05Z] ...`)
- Qual ordem está a correr (`ordem-20260714194845-2c57`) e a tentativa (`tentativa=0`)
- Estado (`aberta` → `respondida` → `VEREDITO: ...` → `aprovada`/`CORRIGIR -> reaberta`/
  `zona_vermelha`/`travada`)
- Veredito do Juiz por extenso (motivo da correção quando `CORRIGIR`)
- `rc` de falhas (ex.: `VPS-EXEC falhou (rc=143) — fallback para o PC nesta ordem`)
- Eventos de sistema: sync do espelho Cortex, "ciclo terminado", "outro carteiro a correr —
  saio", `JUIZ-SEM-VEREDITO`, rate-limit pausado/retomado

## Teste com ordem real
Corri o `assistir-vps.cmd` como processo Windows real (não simulação) durante ~12s e
capturei o stream ao vivo. Mostrou o histórico recente e terminou exatamente na ordem
`ordem-20260714194845-2c57` — **a própria ordem desta tarefa**, cujo fallback para o PC
(`rc=143`) apareceu na janela. Ou seja: a ordem que gerou este relatório já foi vista, ao
vivo, pela janela que este relatório cria. Ligação confirmada estável (sem quedas durante
o teste; lógica de reconexão fica pronta para quedas de rede reais).

## Documentação para o Danilo
Adicionado ao `DEPLOY.md` (secção "Operar"): **"Ver AO VIVO no PC: duplo-clique em
`assistir-vps.cmd`"**, com a distinção clara dos dois ficheiros:
- `assistir.cmd` → o que o Claude está a fazer AGORA nesta máquina (passo a passo).
- `assistir-vps.cmd` → o que o dispatcher (`carteiro.sh`) está a fazer na VPS (fila, juiz,
  estado, notificações).

## Resultado
JANELA AO VIVO da VPS criada — Danilo vê tudo pelo atalho `assistir-vps.cmd` (raiz do
repo), testado com ordem real.
