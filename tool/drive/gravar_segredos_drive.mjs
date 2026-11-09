// Talões no Google Drive da Bora — gravar os 4 segredos no Supabase (adendo 2 da M11, 09/11/2026).
//
// Corre DEPOIS de tool/drive/autorizar_drive_taloes.mjs (que guardou os valores no cofre do Windows,
// recurso "Bora.DriveTaloes"). Lê-os do cofre e chama `supabase secrets set` sem os mostrar.
// A trava do modo automático barra este passo (segredos de produção): corre-o uma sessão com a trava
// aberta para esta missão, ou o Danilo com um duplo clique num terminal.
//
// Uso: node tool/drive/gravar_segredos_drive.mjs
// Depois (pelo MCP do Supabase ou pelo painel):
//   update platform_settings set value='true'::jsonb, updated_at=now() where key='taloes_copia_drive_ativa';
//   e correr a Edge taloes-copia-diaria uma vez; o ficheiro de hoje tem de aparecer na pasta "Talões".
import { spawnSync } from 'node:child_process';

const NOMES = ['GOOGLE_DRIVE_CLIENT_ID', 'GOOGLE_DRIVE_CLIENT_SECRET', 'GOOGLE_DRIVE_REFRESH_TOKEN', 'GOOGLE_DRIVE_PASTA_TALOES'];
const ps = `[void][Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
$v = New-Object Windows.Security.Credentials.PasswordVault
$o = @{}
foreach ($n in @('${NOMES.join("','")}')) { $c = $v.Retrieve('Bora.DriveTaloes', $n); $c.RetrievePassword(); $o[$n] = $c.Password }
$o | ConvertTo-Json -Compress`;
const r = spawnSync('powershell', ['-NoProfile', '-Command', ps], { encoding: 'utf8' });
let valores;
try { valores = JSON.parse(r.stdout); } catch { console.error('Não encontrei os valores no cofre do Windows (corre primeiro autorizar_drive_taloes.mjs).'); process.exit(1); }
for (const n of NOMES) if (!valores[n]) { console.error(`Falta ${n} no cofre.`); process.exit(1); }

const s = spawnSync('npx', ['--no-install', 'supabase', 'secrets', 'set', '--yes', '--project-ref', 'ojykpzwqrtusfeakzrna',
  ...NOMES.map((n) => `${n}=${valores[n]}`)], { encoding: 'utf8', shell: process.platform === 'win32' });
console.log(s.status === 0 ? `OK: gravados ${NOMES.join(', ')}` : `FALHOU (código ${s.status}): ${(s.stderr || '').split('\n')[0]}`);
process.exit(s.status ?? 1);
