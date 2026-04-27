# 22 Categorias Canónicas — Bora App

| # | Categoria | Exemplos | Precedência |
|---|-----------|----------|-------------|
| 1 | Frutas & Legumes | maçã, alface, tomate | média |
| 2 | Talho | frango, vitela, bife | média |
| 3 | Peixaria | bacalhau, salmão, camarão | média |
| 4 | Charcutaria & Queijos | fiambre, queijo, chouriço | **alta** (> Talho) |
| 5 | Padaria & Pastelaria | pão, bolo, croissant | média |
| 6 | Laticínios & Ovos | leite, iogurte, ovo, manteiga | média |
| 7 | Mercearia | arroz, massa, farinha, azeite | baixa (catch-all alimentar) |
| 8 | Congelados | pizza congelada, gelado, nuggets | **MÁXIMA** |
| 9 | Pronto a Comer | lasanha pronta, sushi, sandes | média |
| 10 | Bebidas | água, sumo, café, chá | baixa |
| 11 | Higiene Pessoal | champô, sabonete, pasta dentes | média |
| 12 | Higiene do Lar | detergente, lixívia, rolo cozinha | média |
| 13 | Animais | ração, comida gato/cão | **alta** (> Talho/Peixaria) |
| 14 | Bebé | fralda, biberão, papinha | **alta** (> Laticínios) |
| 15 | Bio & Saudável | orgânico, sem glúten, vegan | muito baixa (só se nada mais) |
| 16 | Fitness & Proteínas | whey, creatina, barra proteína | **alta** (> Saúde) |
| 17 | Saúde & Bem-Estar | vitamina, suplemento, paracetamol | baixa |
| 18 | Festa & Ocasiões | velas, balões, natal, páscoa | baixa |
| 19 | Snacks | bolachas, chips, pipocas | **alta** (> Mercearia) |
| 20 | Pequenos-Almoços | cereais, granola, mel, compota | **alta** (> Mercearia) |
| 21 | Conservas | atum lata, sardinhas conserva | **alta** (> Mercearia/Peixaria) |
| 22 | Vinhos & Espirituosas | vinho, cerveja, whisky, gin | **alta** (> Bebidas) |
| — | Outros | fallback quando nada mapeia | — |

## Regras de Precedência (ordem de verificação)

```
1. Congelados         (palavra "congelad" em qualquer lado → sempre esta)
2. Bebé               (fralda, biberão → ganha a Laticínios)
3. Animais            (ração, gato → ganha a Talho/Peixaria)
4. Vinhos & Espirituosas  (vinho, cerveja → ganha a Bebidas)
5. Fitness & Proteínas    (whey → ganha a Saúde)
6. Charcutaria & Queijos  (fiambre, queijo → ganha a Talho)
7. Conservas          (atum em lata → ganha a Mercearia/Peixaria)
8. Snacks             (bolacha → ganha a Mercearia)
9. Pequenos-Almoços   (cereais, mel → ganha a Mercearia/Padaria)
10. Padaria & Pastelaria
11. Peixaria
12. Talho
13. Laticínios & Ovos
14. Frutas & Legumes
15. Pronto a Comer
16. Mercearia
17. Bebidas
18. Saúde & Bem-Estar
19. Higiene Pessoal
20. Higiene do Lar
21. Festa & Ocasiões
22. Bio & Saudável    (último — só se nada mais mapear)
→ "Outros" se nenhuma keyword bater
```

## Confiança

- `confidence = 1.0` se keyword tem ≥5 chars (match exacto).
- `confidence = 0.7` se keyword tem <5 chars (match fraco).
- `confidence = 0.0` → "Outros".
- Produtos com `confidence < 0.7` entram em **modo interactivo** (perguntar ao Danilo).
