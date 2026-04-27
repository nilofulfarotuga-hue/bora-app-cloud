-- Batch 8/8 — 11 rows
UPDATE products p SET
  taxonomy_section = v.c,
  needs_review = v.r
FROM jsonb_to_recordset('[{"id":"prod_0934","c":"Bebidas","r":false},{"id":"prod_0936","c":"Bebidas","r":false},{"id":"prod_0939","c":"Outros","r":true},{"id":"prod_0940","c":"Frutas & Legumes","r":false},{"id":"prod_0941","c":"Peixaria","r":false},{"id":"prod_0942","c":"Outros","r":true},{"id":"prod_0943","c":"Pequenos-Almoços","r":false},{"id":"prod_0946","c":"Outros","r":true},{"id":"prod_0948","c":"Frutas & Legumes","r":false},{"id":"prod_0949","c":"Frutas & Legumes","r":false},{"id":"prod_0957","c":"Congelados","r":false}]'::jsonb)
  AS v(id text, c text, r boolean)
WHERE p.id = v.id;