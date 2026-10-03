# 🧭 NORTE — Estratégia do trimestre (Bora App)

> **Para quê:** este é o ficheiro que o Robô B (Claude Code / Sócio-AI) lê no arranque para
> saber **o que "ganhar" significa** este trimestre. Sem isto, qualquer ideia minha é chute.
> Com isto, é diagnóstico alinhado com o que **tu** queres.
>
> **Regra:** eu (Robô B) **não invento** as metas — só preparei a estrutura. As 5 linhas
> `<<DANILO PREENCHE>>` são tuas. Escreve em linguagem simples; 1 frase por linha chega.
>
> Atualizado por: _(deixa em branco — eu marco a data quando o leres comigo)_

---

## 1. Missão do trimestre (a frase única que orienta tudo)
> Exemplo do formato (não é a tua meta): "Chegar a 30 pedidos/dia na Guarda com serviço fiável."

**<<DANILO PREENCHE — missão do trimestre>>**

---

## 2. Os KPIs que importam (a régua) — no máximo 3 a 5
> Para cada um: **nome do número + meta + até quando**. Eu já tenho as views para medir
> (`v_kpis_diarios`, `v_funil_checkout`, `v_drivers_online_agora`).

| # | KPI | Onde eu leio | Meta (tu escreves) |
|---|---|---|---|
| 1 | Pedidos entregues / dia | `v_kpis_diarios.pedidos_entregues` | **<<DANILO PREENCHE — meta KPI 1>>** |
| 2 | GMV / semana | `v_kpis_diarios.gmv_eur` | **<<DANILO PREENCHE — meta KPI 2>>** |
| 3 | Taxa de conversão do checkout | `v_funil_checkout.taxa_conversao_pct` | **<<DANILO PREENCHE — meta KPI 3>>** |

---

## 3. Restrições (o que NÃO fazer / guerras que não compramos)
> Orçamento, limites, coisas fora de âmbito. Ajuda-me a não gastar esforço no sítio errado.

**<<DANILO PREENCHE — restrições e o que não fazer>>**

---

## 4. Cliente-alvo e proposta de valor (vs Glovo / Uber Eats / Bolt)
> Quem servimos primeiro e porque nos escolhem. (Tenho o agente `pesquisa-concorrencia`
> para o benchmark — mas a escolha estratégica é tua.)

**<<DANILO PREENCHE — cliente-alvo + porque nos escolhem>>**

---

## 5. Como saberei que o trimestre correu bem (a definição de vitória)
> Uma frase. No fim do trimestre, olho para isto e digo "sim" ou "não".

_(deriva das metas de cima — preenche depois de teres o ponto 2.)_

---

### Notas para o Robô B (não apagar)
- Ler este ficheiro **no arranque** de cada sessão de trabalho estratégico.
- Enquanto houver linhas `<<DANILO PREENCHE>>`, tratar as metas como **desconhecidas** e
  **não fabricar números** — pedir ao Danilo para preencher antes de prometer movimento de KPI.
- Quando estiver preenchido, cruzar com `v_kpis_diarios` no Pulso Diário (skill `daily-pulse`).
