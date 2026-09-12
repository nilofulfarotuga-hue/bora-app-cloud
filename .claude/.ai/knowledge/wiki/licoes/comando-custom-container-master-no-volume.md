---
id: licao-comando-custom-container-master-no-volume
tipo: licao
origem: [missão noturna 2026-07-09 Fase 0: Hermes voltou a enxergar o Córtex]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: auto
---

# Lição — comando custom no container: master no VOLUME, instalação re-garantida

**Problema.** O Hermes precisava de um comando novo (`cortex`) em `/usr/local/bin` do container
`hermes-agent-fvnc-hermes-agent-1`, mas tudo o que vive na camada gravável do container
**morre num recreate** (`docker compose up -d`) — o mesmo que já tinha acontecido ao binário
do tailscale.

**Tentativas que falhariam.**
1. Instalar só em `/usr/local/bin` → desaparece no próximo recreate, e o SOUL.md fica a ensinar
   um comando que já não existe.
2. Instalar só em `/opt/data/bin` (volume) → sobrevive, mas **não está no PATH** do shell do
   agente (`/usr/local/bin:/usr/bin:/bin`) — o comando nunca é encontrado.

**Solução (regra generalizável — padrão do fix do tailscale).**
- **Master no volume**: o ficheiro canónico vive em `/opt/data/bin/<cmd>` (= host
  `/docker/hermes-agent-fvnc/data/bin/<cmd>`), que sobrevive a recreates.
- **Instalação**: `cp` para `/usr/local/bin/<cmd>` (root, 755).
- **Re-garantia**: bloco idempotente no `/root/bora-bridge-up.sh` (host) que, se
  `/usr/local/bin/<cmd>` faltar, volta a copiar do volume — junto com a re-garantia do
  espelho `cortex-brain` (clone com deploy key `/opt/data/.secrets/cortex_deploy_ed25519`,
  **nunca PAT em URL**) e do binário `git`.

**Bónus 1 (locale).** `grep -E` com classes de acentos (`[aáàâã]`) só funciona com
`LC_ALL=C.UTF-8` — sem isso os multibyte partem a bracket expression e "comissao" não
encontra "Comissão".

**Bónus 2 (edição do volume pelo host).** O volume está montado em
`/docker/hermes-agent-fvnc/data` no host — editar aí evita o inferno de quoting de
`docker exec`; mas `sed -i` troca o dono do ficheiro para root → guardar `stat -c '%u:%g'`
antes e `chown` depois (SOUL.md tem de continuar legível pelo `hermes`).
