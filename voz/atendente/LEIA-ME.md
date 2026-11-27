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

## Instalar (root no anfitrião da VPS — o robô dentro do contentor não chega ao Docker)

Ligação da Zadarma por **SIP URI** (26/11/2026): o número manda as chamadas para
`<número>@<IP da VPS>`; não há registo nem senha SIP guardada na VPS. O Asterisk só aceita os
servidores da Zadarma (`identify` com sip, sipurifr, sipde e sipuriny.zadarma.com).

1. `curl -fsSL https://raw.githubusercontent.com/nilofulfarotuga-hue/bora-app-cloud/ai/2026-11-26-voz-central-sipuri/voz/atendente/instalar.sh -o /root/instalar-voz.sh && bash /root/instalar-voz.sh preparar`
   — descarrega para `/opt/voz`, gera a senha da central e copia a chave Groq de ficheiro para
   ficheiro (nada aparece no ecrã), cria o som de recurso, abre a firewall (se o ufw estiver ativo)
   e mostra a IMPRESSÃO da senha em duas metades.
2. Gravar a impressão na base (MCP Supabase): `insert into voz_ferramentas_tokens (hash, nome) values ('<impressão>', 'vps-atendente-voz');`
3. `bash /root/instalar-voz.sh ligar` — testa a senha (`ping` ao voz-ferramentas), arranca os dois
   contentores e põe a vigia de 5 em 5 min no crontab do root.
4. `bash /root/instalar-voz.sh estado` a qualquer momento.

## Zadarma (B1)

- Conta em nome da Bora (e-mail suporte@boraguarda.com; o código chega à tabela `agentes_email`),
  morada Rua do Torreão 14, 6300-610 Guarda, NIPC 519686233. Número nacional (Guarda/centro se houver).
- Pagamento (~4 USD/mês): é do Danilo, com a página aberta à frente dele.
- Número: +351 308 812 860 (pedido 26/11/2026, em verificação até 2 dias úteis).
- No painel da Zadarma: número → "Servidor externo (SIP URI)" = `351308812860@187.124.1.156`;
  "se não atender" → correio de voz com envio do áudio para suporte@boraguarda.com.

## Ligar o 937 501 673 (B8, só depois das chamadas de teste aprovadas)

No telemóvel da Bora: `**21*<número Zadarma sem espaços e com 00351>#` e chamar.
Para desligar o desvio: `##21#` (ou `##002#` para todos os desvios).

## Provas

- Texto (sem telefone): `node voz/atendente/simular_texto.mjs <ficheiro-com-a-senha> saida.json` — 10 casos.
- Painel: admin → "Chamadas (atendente de voz)" (marcar "Mostrar testes").
- Gasto: `select * from ia_gastos where robo='edge-atendente-voz' order by quando desc;`
