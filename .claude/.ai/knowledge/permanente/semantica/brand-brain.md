---
id: brand-brain
tipo: semantica
origem: [missão noturna 2026-07-09 Fase 3 — DNA + business_rules + assets reais do repo]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: verificado-no-codigo
---

# 🧠 Brand Brain — a marca Bora numa página

> Fonte ÚNICA para qualquer peça de marketing. A skill `diretor-criativo` lê isto SEMPRE
> antes de criar. Números vêm de `business_rules.md` (precedência) — nunca inventar.

## Identidade visual
- **Verde Bora** `#16A34A` (cor dominante — o "B" do logo) · **Laranja** `#F97316`
  (acento; regra do design system: **1 elemento laranja por peça**, como nos ecrãs)
- **Fundo claro** `#F0F2EF` · texto escuro sobre claro
- **Fonte:** Inter (a mesma da app — `assets/fonts/Inter-VariableFont.ttf`)
- **Logo:** `assets/branding/bora_logo.png` (principal) · `assets/branding/bora_app_icon.png`
  (ícone; "B" verde + scooter laranja). NUNCA recriar/distorcer o logo em IA — usar o ficheiro.

## Tom de voz (PT-PT, obrigatório)
- Jovem, próximo, direto — **"da Guarda para a Guarda"**. Trata por "tu".
- Zero corporativês, zero cara de ChatGPT. Frases curtas. Específico vence genérico.
- Marketing público = **PT-PT** (admin = PT-BR, mas isso é interno).

## Região & posicionamento
- **Guarda, Portugal** (cidade + arredores). Serviço LOCAL — o estafeta é um vizinho.
- Concorrentes: Glovo, Uber Eats, Bolt. **NUNCA atacar diretamente** — posicionar
  local + justo: comissões mais baixas ao comércio local, ganhos claros a quem entrega.

## As 4 personas (dor → mensagem)
| Persona | Dor | Mensagem-chave |
|---|---|---|
| **Cliente** | apps a mais, taxas escondidas, nada chega à Guarda | Tudo numa app: comida, mercado, farmácia, favores, limpeza, viagens — na tua cidade |
| **Estafeta** | ganhos opacos, algoritmo distante | **€3,80 por entrega + €0,20/km**, flexibilidade total, recebes na hora de decidir |
| **Parceiro** | ~30% de comissão da concorrência | **10% de comissão** — fica com mais do teu trabalho, cliente local |
| **Motorista TVDE** | % por corrida come a margem | **Planos €40/€70/€132** (semanal/quinzenal/mensal) — sem percentagem por corrida |

## Serviços ativos (2026-07)
Delivery restaurantes (parceiros + não-parceiros) · Mercados (Continente, Lidl, Auchan,
Pingo Doce, Mercadona, Intermarché + Wells) · Favores/errands (€6 normal, €10 expresso) ·
Reservas de mesa (€3, devolvidos em desconto à chegada) · Limpeza doméstica (T0–T4, desde €35) ·
TVDE "Bora Motorista" (categoria por convite) · Wallet + Bora Tokens (3 tokens/€, 100=€0,50).

## Regras DURAS (quebrar = peça rejeitada)
1. **Nunca inventar preço, promo ou condição.** Só números do brand-brain/business_rules.
   Promo nova = proposta ao Danilo primeiro.
2. **Ganhos de estafeta/motorista:** sempre com disclaimer "valores ilustrativos; ganhos
   variam com procura e distância".
3. Tokens: nunca prometer "dinheiro grátis" — é desconto (máx 50% por pedido).
4. Fotos de produto reais NUNCA alteradas por IA.
5. Publicação SÓ via OAuth/API oficial (Postiz) e SÓ após aprovação do Danilo.

## Anti-slop (visual + prosa)
- Ferramentas: `.claude/skills/diretor-criativo/referencias/avoid-ai-design/` (visual;
  catálogo de tells P0/P1) + `stop-slop/` (prosa; regras + phrases.md).
- **Proibido:** travessão decorativo (—), gradiente roxo/azul-índigo, glassmorphism
  reflexo, texto-gradiente, emoji em cada frase, "Eleva a tua experiência", listas de 3
  metronómicas, corporativês traduzido do inglês.
- **Obrigatório:** verde #16A34A dominante, UMA peça laranja de acento, Inter, fotografia
  real ou ilustração com intenção (nunca stock genérico de IA), CTA concreto ("Pede já na
  app Bora", "Candidata-te em 2 min").
