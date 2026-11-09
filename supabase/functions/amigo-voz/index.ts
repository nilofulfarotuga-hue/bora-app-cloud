// amigo-voz — a voz do servidor do Amigo (missão missao-pendencias-2026-11-09, bloco I).
//
// Porquê: o Amigo fala com a voz do aparelho; o Safari do iPhone nem sempre tem voz pt-PT e o
// Amigo ficava mudo. Nesse caso a app pede aqui o áudio da frase.
//
// POST { texto, velocidade? }  (só utilizadores com sessão; verify_jwt = true e confirmação no Auth)
//   → 200 { ok: true, audio_base64, formato: 'mp3', origem: 'cache' | 'google', voz, caracteres }
//   → 200 { ok: false, usar_aparelho: true, motivo }   desligado, teto, limite_utilizador, sem_chave,
//                                                      erro_google, erro_base, texto_invalido
//   → 401 { ok: false, usar_aparelho: true, motivo: 'sem_sessao' }
//
// Google Cloud Text-to-Speech (REST text:synthesize), SEMPRE pt-PT: a voz vem do painel
// (amigo_voz_nome, padrão pt-PT-Standard-E, feminina, a do maior grátis). Segredo:
// GOOGLE_TTS_API_KEY (sem ele responde "sem_chave" e a app fica com a voz do aparelho/legenda).
// Cache: bucket privado amigo-voz, chave = sha256(voz|velocidade|texto). Teto diário e limite por
// cliente: amigo_voz_reservar (platform_settings amigo_voz_teto_dia / amigo_voz_teto_utilizador_dia).
// Interruptor: amigo_voz_servidor_ativo (false até se pôr a chave). Consumo: amigo_voz_consumo.
// A decisão está em logica.ts (testada em logica_test.ts).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders } from '../_shared/cors.ts';
import { utilizadorDoPedido } from '../_shared/chaves.ts';
import { secretKey } from '../_shared/keys.ts';
import { BUCKET, chamarGoogle, definicoesDe, type TipoContagem, tratar, usarAparelho } from './logica.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';

function json(corpo: unknown, estado = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status: estado,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, usar_aparelho: true, motivo: 'metodo' }, 405);

  let corpo: unknown = null;
  try {
    corpo = await req.json();
  } catch {
    corpo = null;
  }

  const chaveServidor = secretKey();
  if (!SUPABASE_URL || !chaveServidor) {
    const r = usarAparelho('erro_base');
    return json(r.corpo, r.estado);
  }
  const admin = createClient(SUPABASE_URL, chaveServidor, { auth: { persistSession: false } });

  const r = await tratar(corpo, {
    utilizador: async () => (await utilizadorDoPedido(req))?.id ?? null,
    definicoes: async () => {
      const { data, error } = await admin
        .from('platform_settings')
        .select('key, value')
        .in('key', ['amigo_voz_servidor_ativo', 'amigo_voz_nome']);
      if (error) throw new Error(error.message);
      return definicoesDe(data as Array<{ key: string; value: unknown }>);
    },
    chaveGoogle: () => Deno.env.get('GOOGLE_TTS_API_KEY') || null,
    cacheLer: async (caminho) => {
      const { data, error } = await admin.storage.from(BUCKET).download(caminho);
      if (error || !data) return null; // não existe (ainda)
      return new Uint8Array(await data.arrayBuffer());
    },
    cacheGravar: async (caminho, mp3) => {
      const { error } = await admin.storage.from(BUCKET).upload(caminho, mp3, {
        contentType: 'audio/mpeg',
        upsert: true,
      });
      if (error) throw new Error(error.message);
    },
    reservar: async (userId, caracteres) => {
      const { data, error } = await admin.rpc('amigo_voz_reservar', {
        p_user_id: userId,
        p_caracteres: caracteres,
      });
      if (error) throw new Error(error.message);
      return data as { ok: boolean; motivo?: string };
    },
    contar: async (userId, caracteres, tipo: TipoContagem) => {
      const { error } = await admin.rpc('amigo_voz_contar', {
        p_user_id: userId,
        p_caracteres: caracteres,
        p_tipo: tipo,
      });
      if (error) throw new Error(error.message);
    },
    google: (pedido, chave) => chamarGoogle(pedido, chave),
    registo: (m) => console.warn(`[amigo-voz] ${m}`),
  });

  if (r.corpo.ok === true) {
    console.log(`[amigo-voz] ${r.corpo.origem} ${r.corpo.caracteres} caracteres (${r.corpo.voz})`);
  } else {
    console.log(`[amigo-voz] usar o aparelho: ${r.corpo.motivo}`);
  }
  return json(r.corpo, r.estado);
});
