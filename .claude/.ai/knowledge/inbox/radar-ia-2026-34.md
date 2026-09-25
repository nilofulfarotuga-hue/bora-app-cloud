---
id: radar-ia-2026-34
tema: radar-ia
estado: atual
data: 2026-08-23
autor: batedor (radar de IA semanal) + veredito Claude.ai 23/08
---

# Radar de IA — semana 2026-34

Relatorio completo: `/opt/data/radar/2026-34.md`. Estado do envio: enviado ao Telegram. Modelo usado: gemini/gemini-3.6-flash.
Fontes: API publica do GitHub (6 topicos) + 6 feeds RSS. Sem chave paga, sem web_extract.

Radar de IA da semana 2026-34.

ja tens: Hermes com os tres bots
ja tens: agent-skills
ja tens: Supabase

A Front-End Checklist e uma lista de verificacao para desenvolvimento web que cobre SEO, performance e acessibilidade. Permite auditar e validar sites antes de os entregar a clientes. E totalmente gratis e de codigo aberto em https://github.com/thedaviddias/Front-End-Checklist e serve para: sites que ele vende a clientes e clubes.

O DeepSeek Vision e um modelo experimental de visao computacional acessivel por API. Permite analisar comprovativos, faturas e imagens na tua aplicacao. Custa fracoes de centimo por consumo de tokens na API em https://api-docs.deepseek.com/guides/vision/ e serve para: app Bora multi-vertical em Flutter e Supabase.

A nova API do Bun WebView permite criar rotinas de captura e extracao de dados web sem depender do Chromium. E uma solucao ultraleve para automatizar formularios e dados em sites de clientes. E totalmente gratis e de codigo aberto em https://simonwillison.net/2026/Aug/20/bun-webview-json-api/ e serve para: sites que ele vende a clientes e clubes.

O HeyGen Avatar IV foi portado para as TPUs da Google Cloud para acelerar a criacao de avatares de video hiper-realistas. Permite gerar personagens falantes de alta qualidade para producoes de animacao. E um servico comercial pago por subscricao em https://developers.googleblog.com/heygen-x-google-cloud-bringing-avatar-iv-to-tpus/ e serve para: Bora Studio.

O LFM2.5-DSpark da Liquid AI e um modelo aberto otimizado para inferencia ate tres vezes mais rapida. E totalmente gratis para descarregar, mas nao corre no teu hardware. Esta disponivel em https://huggingface.co/blog/LiquidAI/lfm25-dspark e serve para: poupar dinheiro em modelos e APIs.

Veredito do batedor: O DeepSeek Vision e o Bun WebView sao os unicos que trazem utilidade pratica imediata, enquanto o resto e maioritariamente barulho empresarial.

---

## Achado trazido pelo Danilo 23/08 (video sobre "Comfy MCP") — veredito Claude.ai

CONTEXTO: o Danilo colou a transcricao de um video e perguntou se da para encaixar no sistema dele, so se for gratis.

O QUE E, confirmado em fonte primaria: a Comfy Org lancou a 11/08/2026 o `comfy-mcp` (Comfy-Org/comfy-mcp), servidor MCP oficial, aberto e stdio, que deixa Claude Code / Claude Desktop / Cursor / ChatGPT conduzir o ComfyUI. Faz verificacao de hardware, recomenda e instala modelos sozinho, valida e corre workflows, e gera imagem, video, audio, 3D, upscale e remocao de fundo. Docs: https://docs.comfy.org/agent-tools/mcp e https://comfy.org/mcp/

DECISAO: **NAO ADOTAR.** Duas razoes independentes, qualquer uma delas chega.
1. HARDWARE (Regra C do batedor). O `comfy-mcp` local exige um ComfyUI a correr na maquina, com GPU (alvo 127.0.0.1:8188). O PC e um Acer Celeron N4500, 4 GB, sem GPU. O autor do video corre numa RTX 3050 de 8 GB e diz explicitamente que esta "no minimo". A unica variante que corre sem placa e a Comfy Cloud, e essa **exige subscricao paga de qualquer nivel** (creditos avulso nao chegam) — falha a regra do custo zero.
2. DESENHO. O Bora Studio ja faz o mesmo trabalho por outra via e melhor para este caso: kernels headless no Kaggle/Colab/Lightning, com Wan 2.2 I2V/S2V, relogio de 15 min e o Danilo a nao tocar em nada. O ComfyUI e uma GUI de nos; adota-lo era reintroduzir trabalho manual. Mesmo raciocinio que arquivou o VoiceBox a 04/08: o que interessa e o motor, nunca a janela.

NANO BANANA (o segundo achado da mesma mensagem): ja e dele — e o operador de imagem do Studio (Gemini/Nano Banana, F4 do prompt mestre). Existe tambem um servico terceiro "Nano Banana Video" com conector MCP para Claude/ChatGPT (https://nanobananavideo.com/mcp), mas gera por creditos e o uso comercial sem marca de agua e plano pago. REJEITADO pela regra do preco. Nota factual para nao repetir confusao: o Nano Banana em si NAO gera video — e modelo de imagem; quem gera video sao os modelos de video a jusante.

## O QUE FICA PARA FAZER — so isto, e e gratis

**UPSCALE EM DUAS PASSADAS COM SEGUNDA PASSADA DEDICADA AO ROSTO.** E a unica tecnica do video que vale dinheiro aqui, e nao precisa de ComfyUI nenhum: e a ordem das operacoes, nao a ferramenta. Primeira passada faz o upscale do fotograma inteiro; segunda passada reconstroi so a regiao da cara, que e onde o upscale global falha. No video, foi exatamente isto que levou o rosto de "zoado" a aceitavel.

ONDE ENTRA: fila de arte do Studio, ao lado dos despachos de imagem que ja existem. Ataca de frente uma queixa real e repetida do Danilo — rostos e arte fora do traco (avo Monica, Daniel, Rafinha lidos como fotorrealistas; Sussurrador a mudar de forma entre planos).

CONDICOES INEGOCIAVEIS quando isto for construido:
- Custo zero: corre nos kernels de GPU gratis que ja existem (Kaggle/Colab/Lightning) pela ponte agnostica, nunca em servico pago.
- Nao trocar de motor a meio do episodio (regra do Batedor) — isto ACRESCENTA uma etapa de pos-processamento, nao substitui o animador.
- Nitidez com mao leve: o proprio video mostrou o defeito de exagerar o "sharpen"; o Danilo ja reprovou textura artificial antes.
- Validar com defeito plantado antes de dar veto a qualquer fiscal novo que julgue o resultado, e validar em ecra grande (o telemovel ja escondeu um defeito uma vez).
- NAO comecar isto enquanto o Ep1 tiver bloqueantes abertos a espera de GPU.

ESTADO: registado, por executar. Nao foi criada ordem — o Danilo disse para ficar guardado para quando se mexer no Studio.
