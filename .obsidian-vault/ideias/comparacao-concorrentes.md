# Comparação com Concorrentes — Uber Eats · iFood · Glovo

> Análise de onde a Bora se diferencia e onde pode aprender. Fontes: research web Abril 2026.

---

## Posicionamento Actual da Bora

| Dimensão | Bora | Uber Eats | iFood | Glovo |
|----------|------|-----------|-------|-------|
| Mercado | Portugal local | Global | Brasil + PT | Sul Europa |
| Tipos de serviço | Restaurantes + Supermercado + Envio Pacotes + Carregar Compras | Restaurantes + Grocery | Restaurantes + Mercado | Multi-categoria |
| Pagamentos PT | Stripe + MBWay* + Cash | Cartão + Paypal | Cartão + Pix | Cartão + Apple/Google Pay |
| Driver próprio | ✅ Sim | ❌ Freelance | ❌ Freelance | ✅/❌ Misto |
| Reservas de mesa | ✅ Sim | ❌ | ❌ | ❌ |
| Personalização AI | ❌ Não ainda | ✅ | ✅ Avançado | ✅ |

*MBWay ainda em desenvolvimento

---

## O que a Bora pode copiar já (baixo esforço)

### Do Uber Eats
1. **Tags de avaliação** — "Rápido", "Simpático", "Embalagem boa" (1-2 dias de dev)
2. **Foto do driver no tracking** — o modelo já tem o campo, só falta ligar ao UI
3. **"Pedir de novo"** — secção home com os últimos restaurantes do cliente

### Do iFood
1. **Separar avaliação driver / restaurante** — mais útil que uma nota só
2. **Delay de 15 min antes de pedir avaliação** — melhor taxa de resposta
3. **Resumo nocturno para parceiros** — notificação simples com o dia em números

### Do Glovo
1. **Flash Deals** — botão no dashboard do parceiro para criar promoção rápida com desconto e duração
2. **Toggle on/off por produto** — na lista de produtos, sem entrar em cada um
3. **Preview de tempo de entrega antes de entrar** — mostrar "~20 min" na lista de restaurantes

---

## O que a Bora já tem que os outros NÃO têm

### Diferenciais únicos
1. **Reservas de mesa integradas** — Uber Eats, iFood e Glovo não têm isto. É um diferencial real.
2. **"Carregar compras"** — serviço de acompanhamento de compras físicas no supermercado. Nenhum concorrente tem.
3. **"Enviar Pacote"** — courier integrado. A Glovo tem mas é o core deles, não um add-on.
4. **Operação local** — conhecimento profundo da cidade, drivers locais = entregas mais rápidas
5. **Contacto directo com o driver** — chat em tempo real integrado

### Como explorar estes diferenciais no marketing
- "A única app que reserva a mesa E entrega em casa"
- "O driver local que conhece a cidade"
- "Paga em MBWay, como sempre fizeste"

---

## Tendências 2024-2025 que a Bora devia acompanhar

### AI e Personalização
- **iFood**: IA de voz — cliente faz pedido por voz em 1 minuto
- **Glovo**: IA de recomendação de presentes ("o que oferecer à namorada?")
- **Para a Bora**: a curto prazo, bastam recomendações baseadas em histórico ("costumas pedir X às sextas")

### Google Pay / Apple Pay
- Todos os concorrentes têm. A Bora usa Stripe que suporta nativamente.
- **Esforço baixo, impacto alto** no checkout (especialmente mobile)

### Sustainability
- **Glovo**: opção "sem talheres descartáveis"
- **Para a Bora**: checkbox simples "sem embalagem extra" no checkout

### Subscrições / Passe
- **Uber Eats One**: entrega grátis por mês
- **iFood**: clube de benefícios
- **Para a Bora**: "Bora Pass" — entrega grátis ilimitada por X€/mês (quando tiver volume)

---

## Análise de Pontos Fracos vs Concorrentes

| Ponto Fraco | Impacto | Solução |
|-------------|---------|---------|
| Sem Google/Apple Pay | Alto — abandono no checkout | Activar via Stripe (2-3 dias) |
| Sem notificações push a funcionar | Alto — cliente não sabe o estado | Bug-003 já identificado |
| Sem ratings persistentes | Médio — sem dados de qualidade | Bug-018 já identificado |
| Cancelamento não implementado | Médio — má UX | Bug-017 já identificado |
| Sem histórico de pagamentos | Baixo | Feature futura |
