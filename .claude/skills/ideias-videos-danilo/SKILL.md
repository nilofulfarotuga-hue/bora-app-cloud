---
name: ideias-videos-danilo
description: >
  Usa SEMPRE que o Danilo mandar um vídeo, transcrição ou link de ideias, ou antes de propor funcionalidades novas, propostas a clientes ou automações. Ele não quer ter de pedir duas vezes: tira-se o que presta, grava-se na página 'ideias-videos-danilo' (claude_ai_memoria + Córtex) e consulta-se antes de propor.
metadata:
  versao: 1.0
  criada: 2026-10-01
  criada_por: vigia-habilidades (corrida 2026-10-01_2330)
  tema: "Ideias dos vídeos que o Danilo manda: gravar no Córtex e consultar antes de propor"
  origem_literal:
    - "2026-10-01: REGRA (Danilo, 01/10/2026): tudo o que ele mandar (vídeos, transcrições, links), Claude.ai tira o que presta, grava AQUI no Córtex, e usa quando for preciso — sem ele ter de pedir de novo."
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# ideias-videos-danilo

> Criada pelo vigia a 01/10/2026 porque o Danilo disse: 2026-10-01: REGRA (Danilo, 01/10/2026): tudo o que ele mandar (vídeos, transcrições, links), Claude.ai tira o que presta, grava AQUI no Córtex, e usa quando for preciso — sem ele ter de pedir de novo.

# Ideias dos vídeos do Danilo

## Origem
- 2026-10-01, regra do Danilo (via página `ideias-videos-danilo` da Claude.ai): "tudo o que ele mandar (vídeos, transcrições, links), Claude.ai tira o que presta, grava AQUI no Córtex, e usa quando for preciso — sem ele ter de pedir de novo."

## Quando consultar
- Antes de propor funcionalidade nova do Bora, proposta a cliente ou automação.
- Primeiro lê a página: `select pagina, conteudo from public.claude_ai_memoria where pagina = 'ideias-videos-danilo'`, ou `cortex_buscar "ideias videos danilo"`.

## Quando gravar
- O Danilo manda vídeo, transcrição ou link sem mais instruções: extrai só o que serve ao Bora ou às propostas a clientes.
- Acrescenta uma secção datada `## DD/MM/AAAA — <título>` com três blocos: o que NÃO adotar e porquê, ideia para o Bora, ideia para vender.
- Marca sempre o estado (ideia, proposta, lançada). Não escrevas ideia como se fosse facto.
- Grava no Córtex com `cortex_memorizar` (origem Claude Code). Nunca incluas segredos nem transcrições brutas.

## Limites
- Não lanças a ideia por tua conta: dinheiro, preços, push e publicação seguem as regras habituais.
- Feature com ecrã precisa de correspondência no painel admin (PT-BR).
- Resposta ao Danilo: curta e em texto corrido, para ser ouvida. Ele não lê listas nem decide itens técnicos.
