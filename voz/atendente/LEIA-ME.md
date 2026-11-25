# Atendente de voz da Bora — central na VPS

Missão `atendente-voz-2026-11-25` (blocos B1, B2, B8). Quem liga para o telefone da Bora é atendido
por um assistente virtual em pt-PT. O cérebro (Claude Opus 5.5) e as ferramentas vivem nas Edge
Functions `voz-cerebro` e `voz-ferramentas` (já publicadas). Esta pasta é só a parte do som.

```
telemóvel da Bora 937 501 673 --(**21*)--> número Zadarma --SIP--> Asterisk (VPS)
   --AudioSocket 127.0.0.1:9092--> central.py: Groq Whisper -> voz-cerebro -> edge-tts pt-PT
   --> voz-ferramentas: chamada, falas, áudio (bucket privado 90 dias), resumo, push ao admin
```

Porquê não Pipecat: não tem transporte AudioSocket nativo e a VPS tem 1 CPU e ~330 MB livres;
`central.py` faz a mesma cascata sem modelos locais (testado em texto pelo `simular_texto.mjs`;
o som ainda não foi testado numa chamada real).

## Instalar (precisa de root no anfitrião da VPS — o robô dentro do contentor não chega ao Docker)

1. `git clone` deste repositório (ramo da missão) para `/opt/voz` e `cd /opt/voz/voz/atendente`.
2. Senha da central: `openssl rand -hex 32` → guarda o texto só no `.env` (passo 3). Grava a
   impressão digital na base (MCP Supabase, projeto ojykpzwqrtusfeakzrna):
   `insert into voz_ferramentas_tokens (hash, nome) values (encode(extensions.digest('<senha>','sha256'),'hex'), 'vps-atendente-voz');`
3. `.env` (chmod 600, nunca no git):
   ```
   VOZ_SENHA=<senha do passo 2>
   GROQ_API_KEY=<a mesma que o Hermes já usa>
   SUPABASE_FN=https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1
   VOZ_PORTA=9092
   VOZ_LINHAS=1
   ZADARMA_SIP_USER=<número SIP da conta Zadarma, ex. 123456>
   ZADARMA_SIP_SENHA=<senha SIP da Zadarma>
   IP_PUBLICO=<IP público da VPS>
   ```
4. Som de recurso (se a central cair): `mkdir -p asterisk/sons && edge-tts --voice pt-PT-RaquelNeural --text "Olá, ligou para a Bora. Neste momento não conseguimos atender. Escreva para suporte arroba boraguarda ponto com. Obrigado." --write-media /tmp/r.mp3 && ffmpeg -i /tmp/r.mp3 -ar 8000 -ac 1 asterisk/sons/recurso.wav`
5. Firewall: abrir 5060/udp e 10000-10099/udp só aos IPs da Zadarma (lista no painel deles); 9092 fica fechado (a central escuta só em 127.0.0.1).
6. `docker compose up -d --build` e `docker compose logs -f` (procurar "Registered" no Asterisk e "central à escuta").
7. Vigia de 5 em 5 min (crontab do root): `*/5 * * * * cd /opt/voz/voz/atendente && docker compose ps --status running | grep -q central || docker compose up -d`

## Zadarma (B1)

- Conta em nome da Bora (e-mail suporte@boraguarda.com; o código chega à tabela `agentes_email`),
  morada Rua do Torreão 14, 6300-610 Guarda, NIPC 519686233. Número nacional (Guarda/centro se houver).
- Pagamento (~4 USD/mês): é do Danilo, com a página aberta à frente dele.
- No painel da Zadarma: número → "Encaminhar para SIP" (a conta SIP desta central); "se não atender" →
  correio de voz com envio do áudio para suporte@boraguarda.com.

## Ligar o 937 501 673 (B8, só depois das chamadas de teste aprovadas)

No telemóvel da Bora: `**21*<número Zadarma sem espaços e com 00351>#` e chamar.
Para desligar o desvio: `##21#` (ou `##002#` para todos os desvios).

## Provas

- Texto (sem telefone): `node voz/atendente/simular_texto.mjs <ficheiro-com-a-senha> saida.json` — 10 casos.
- Painel: admin → "Chamadas (atendente de voz)" (marcar "Mostrar testes").
- Gasto: `select * from ia_gastos where robo='edge-atendente-voz' order by quando desc;`
