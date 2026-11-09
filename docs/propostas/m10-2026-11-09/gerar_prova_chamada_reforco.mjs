// Gera prova_chamada_reforco.sql a partir da migração e do modelo.
// Uso: node docs/propostas/m10-2026-11-09/gerar_prova_chamada_reforco.mjs
// Na prova, os gatilhos vão para clones temporários (sem pg_net) e o cron sai.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const raiz = join(aqui, '..', '..', '..');
const mig = readFileSync(join(raiz, 'supabase/migrations/20261109010134_m10_chamada_de_reforco.sql'), 'utf8')
  .replace(/\r\n/g, '\n');
const modelo = readFileSync(join(aqui, 'prova_chamada_reforco.modelo.sql'), 'utf8').replace(/\r\n/g, '\n');

const ini = mig.indexOf('-- [CRON-INICIO]');
const fim = mig.indexOf('-- [CRON-FIM]');
if (ini < 0 || fim < ini) throw new Error('marcas do cron em falta');
let prova = mig.slice(0, ini) + '-- [cron retirado na prova]\n' + mig.slice(fim + '-- [CRON-FIM]\n'.length);

const trocas = { orders: 4, tvde_rides: 4, tvde_ride_events: 2 };
for (const [t, esperado] of Object.entries(trocas)) {
  const re = new RegExp(`ON public\\.${t}\\b`, 'g');
  const n = (prova.match(re) || []).length;
  if (n !== esperado) throw new Error(`ON public.${t}: ${n} (esperado ${esperado})`);
  prova = prova.replace(re, `ON pg_temp._${t}_clone`);
}
if (prova.includes('$mig_m10_20261109$') || prova.includes('$prova$')) throw new Error('etiqueta $ em conflito');
if (/cron\.(schedule|unschedule)/.test(prova)) throw new Error('cron ficou na prova');

const saida = modelo.replace('__MIGRACAO__', () => prova);
writeFileSync(join(aqui, 'prova_chamada_reforco.sql'), saida, 'utf8');
console.log('md5(v_mig)=' + createHash('md5').update(prova, 'utf8').digest('hex'),
            'bytes_mig=' + Buffer.byteLength(prova), 'bytes_prova=' + Buffer.byteLength(saida));
