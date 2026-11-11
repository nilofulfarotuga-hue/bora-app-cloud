// Gera os remendos da migração 01 a partir das definições REAIS da produção (defs/*.sql).
// Cada âncora tem de aparecer exatamente 1 vez (espaços em branco contam como \s+).
import { readFileSync, writeFileSync } from 'node:fs';
const F = (n) => readFileSync(n + '.sql', 'utf8').replace(/\r\n/g, '\n');
const ESC = `not (r.id = any (public.lojas_escondidas_para_mim()))`;
const reEsc = (t) => t.trim().split(/\s+/).map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('\\s+');
function patch(nome, pares) {
  let s = F(nome);
  for (const [de, extra] of pares) {
    const re = new RegExp(reEsc(de), 'g');
    const m = s.match(re);
    if (!m || m.length !== 1) throw new Error(`${nome}: âncora encontrada ${m ? m.length : 0} vezes: ${de.slice(0, 70)}`);
    s = s.replace(re, (txt) => txt + '\n      ' + extra);
  }
  return `-- ${nome}: corpo copiado da produção a 11/11/2026 (pg_get_functiondef) + filtro das lojas escondidas (farmácias)\n` + s.trim() + '\n';
}
const partes = [];
partes.push(patch('cliente_pesquisar', [
  ["where r.approval_status='approved' and coalesce(r.is_active_admin,true)", 'and ' + ESC],
  ['join restaurants r on r.id = pp.restaurant_id', 'where ' + ESC],
]));
partes.push(patch('home_mais_pedidos', [
  ["and coalesce(r.coming_soon,false)=false and r.category in ('restaurant','festas')", 'and ' + ESC],
]));
partes.push(patch('home_pede_outra_vez', [
  ["and r.approval_status='approved' and coalesce(r.is_online,true)", 'and ' + ESC],
]));
partes.push(patch('search_businesses', [
  ['WHERE r.is_active_admin = true', 'AND ' + ESC],
]));
partes.push(patch('agent_search_products', [
  ["SELECT r.id INTO v_loja FROM public.restaurants r WHERE r.approval_status = 'approved' AND COALESCE(r.is_active_admin, false)", 'AND ' + ESC],
]));
partes.push(patch('agent_get_store_info', [
  ["LEFT JOIN LATERAL (SELECT public.is_partner_open(r.id) v) st ON true WHERE r.approval_status = 'approved' AND COALESCE(r.is_active_admin, false)", 'AND ' + ESC],
]));
partes.push(patch('store_active_promotions', [
  ['where p.restaurant_id = p_restaurant_id', 'and not (p.restaurant_id = any (public.lojas_escondidas_para_mim()))'],
]));
partes.push(patch('social_lojas_permitidas', [
  ["and coalesce(r.is_active_admin, true) = true and r.approval_status = 'approved'", 'and not coalesce(r.so_lista_permissao, false) -- os robôs das redes nunca mostram lojas escondidas'],
]));
const view = readFileSync('assistant_lojas_view.sql', 'utf8').trim().replace(/;$/, '');
const vAnc = "AND id !~~ 'demo-%'::text";
if (view.split(vAnc).length !== 2) throw new Error('âncora da vista');
const view2 = view.replace(vAnc, vAnc + ' AND NOT COALESCE(so_lista_permissao, false)');
partes.push(`-- assistant_lojas: definição da produção a 11/11/2026 + o Amigo nunca mostra lojas escondidas\ncreate or replace view public.assistant_lojas with (security_invoker = true) as\n${view2};\n`);
writeFileSync('patches01.sql', partes.join('\n'));
console.log('ok', partes.length, 'blocos');
