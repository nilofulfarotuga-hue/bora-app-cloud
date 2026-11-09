// Talões no Google Drive da Bora — autorização (adendo 2 da M11, 09/11/2026).
//
// Uso: node tool/drive/autorizar_drive_taloes.mjs <client_secret_....json>
//
// 1. Lê o cliente OAuth "Bora Talões" (app para computador, projeto do Gemini) do JSON que a consola
//    Google deu. Nada disto vai para o repositório.
// 2. Abre um porto local (127.0.0.1) e escreve o endereço da autorização (só drive.file, com PKCE).
//    O Danilo carrega em "Permitir" com a conta boraappbora.
// 3. Troca o código pelo refresh token, cria a pasta "Talões" no Drive da Bora (tem de ser a própria
//    app a criá-la: com drive.file só se vê o que a app criou).
// 4. Guarda os 4 valores no cofre do Windows (PasswordVault, recurso "Bora.DriveTaloes"), cifrado na
//    conta do Windows. NUNCA os escreve no ecrã, em ficheiros, no repositório nem no e2e_log.
// O passo seguinte (gravar os segredos no Supabase) é tool/drive/gravar_segredos_drive.mjs, que a trava
// barra nesta sessão (segredos de produção).
import { readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { randomBytes, createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ficheiro = process.argv[2];
if (!ficheiro) { console.error('uso: node autorizar_drive_taloes.mjs <client_secret.json>'); process.exit(2); }
const c = JSON.parse(readFileSync(ficheiro, 'utf8')).installed;
if (!c?.client_id || !c?.client_secret) { console.error('JSON sem "installed" (tem de ser app para computador)'); process.exit(2); }

const b64 = (b) => b.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const verificador = b64(randomBytes(48));
const desafio = b64(createHash('sha256').update(verificador).digest());
const estado = b64(randomBytes(16));

function guardarNoCofre(valores) {
  const ps = `$j = [Console]::In.ReadToEnd() | ConvertFrom-Json
[void][Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
$v = New-Object Windows.Security.Credentials.PasswordVault
foreach ($p in $j.PSObject.Properties) {
  try { $old = $v.Retrieve('Bora.DriveTaloes', $p.Name); $v.Remove($old) } catch {}
  $v.Add((New-Object Windows.Security.Credentials.PasswordCredential('Bora.DriveTaloes', $p.Name, [string]$p.Value)))
}
'ok'`;
  const r = spawnSync('powershell', ['-NoProfile', '-Command', ps], { input: JSON.stringify(valores), encoding: 'utf8' });
  return (r.stdout || '').trim() === 'ok';
}

const servidor = createServer(async (req, res) => {
  const u = new URL(req.url, 'http://127.0.0.1');
  if (!u.searchParams.get('code') && !u.searchParams.get('error')) { res.writeHead(404); res.end(); return; }
  const fim = (msg, ok) => {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(`<html><body style="font-family:sans-serif;padding:40px;background:#f0fdf4"><h2 style="color:${ok ? '#15803d' : '#b91c1c'}">${msg}</h2><p>Já podes fechar esta página.</p></body></html>`);
  };
  try {
    if (u.searchParams.get('error')) throw new Error(`Google recusou: ${u.searchParams.get('error')}`);
    if (u.searchParams.get('state') !== estado) throw new Error('estado não bate certo');
    const porto = servidor.address().port;
    const tk = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code: u.searchParams.get('code'), client_id: c.client_id, client_secret: c.client_secret,
        redirect_uri: `http://127.0.0.1:${porto}`, grant_type: 'authorization_code', code_verifier: verificador,
      }),
    });
    const t = await tk.json();
    if (!tk.ok || !t.refresh_token) throw new Error(`troca do código falhou: ${tk.status} ${t.error ?? ''}`);
    const auth = { Authorization: `Bearer ${t.access_token}` };
    const q = encodeURIComponent(`name='Talões' and mimeType='application/vnd.google-apps.folder' and trashed=false`);
    let pasta = (await (await fetch(`https://www.googleapis.com/drive/v3/files?q=${q}&fields=files(id)`, { headers: auth })).json()).files?.[0]?.id;
    if (!pasta) {
      const cr = await fetch('https://www.googleapis.com/drive/v3/files?fields=id', {
        method: 'POST', headers: { ...auth, 'content-type': 'application/json' },
        body: JSON.stringify({ name: 'Talões', mimeType: 'application/vnd.google-apps.folder', description: 'Cópia diária dos talões das compras dos estafetas (Bora)' }),
      });
      pasta = (await cr.json()).id;
      if (!cr.ok || !pasta) throw new Error(`criar a pasta falhou: ${cr.status}`);
    }
    const quem = await (await fetch('https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)', { headers: auth })).json();
    const ok = guardarNoCofre({
      GOOGLE_DRIVE_CLIENT_ID: c.client_id, GOOGLE_DRIVE_CLIENT_SECRET: c.client_secret,
      GOOGLE_DRIVE_REFRESH_TOKEN: t.refresh_token, GOOGLE_DRIVE_PASTA_TALOES: pasta,
    });
    console.log(`OK conta=${quem?.user?.emailAddress ?? '?'} pasta=${pasta.slice(0, 6)}… token=${t.refresh_token.length} letras ambito=${t.scope} cofre=${ok ? 'guardado' : 'FALHOU'}`);
    fim(ok ? 'Pronto! O Drive da Bora está autorizado para os talões.' : 'Autorizado, mas não consegui guardar no cofre do Windows.', ok);
  } catch (e) {
    console.log(`ERRO ${e.message}`);
    fim(`Não deu: ${e.message}`, false);
  } finally {
    setTimeout(() => process.exit(0), 500);
  }
});

servidor.listen(0, '127.0.0.1', () => {
  const porto = servidor.address().port;
  const url = 'https://accounts.google.com/o/oauth2/v2/auth?' + new URLSearchParams({
    client_id: c.client_id, redirect_uri: `http://127.0.0.1:${porto}`, response_type: 'code',
    scope: 'https://www.googleapis.com/auth/drive.file', access_type: 'offline', prompt: 'consent',
    login_hint: 'boraappbora@gmail.com', code_challenge: desafio, code_challenge_method: 'S256', state: estado,
  });
  writeFileSync(join(tmpdir(), 'bora-drive-autorizacao-url.txt'), url);
  console.log(`A ESPERA em http://127.0.0.1:${porto} (endereço da autorização em ${join(tmpdir(), 'bora-drive-autorizacao-url.txt')})`);
});
setTimeout(() => { console.log('ERRO ninguém autorizou em 15 minutos'); process.exit(1); }, 15 * 60 * 1000);
