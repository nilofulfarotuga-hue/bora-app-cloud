[MODELO: SONNET]

ORDEM FIXA — HISTÓRICO DO YOUTUBE PARA O RADAR (dispara às 01:45, Agendador de Tarefas "BoraRadarHistorico")

> Escrita 2026-09-28 (missão pc-fecho-2026-09-28, bloco P2). O radar das 02:00
> (`QG\radar-video\scripts\run_nightly.ps1`) lê o que esta ordem grava. Até 28/09 dependia de
> um zip do Takeout que ninguém voltou a exportar e entravam ZERO vídeos novos por noite.

Faz exactamente isto e nada mais. Não publica nada, não mexe em contas, não sai de sessões.

1. Ferramentas do Chrome: `list_connected_browsers` e `select_browser` com o deviceId do
   perfil PESSOAL `5b260cdd-9d4f-49d6-842b-ebfbfea69c75` (nunca pelo nome "Browser 1/2").
   Se não estiver na lista, abre o perfil com
   `"C:\Program Files\Google\Chrome\Application\chrome.exe" --profile-directory=Default https://www.youtube.com/feed/history?authuser=1`,
   espera 10 s e lista outra vez.
2. Separador novo (`tabs_create_mcp`) → `https://www.youtube.com/feed/history?authuser=1`.
3. Confirma com `javascript_tool` que `ytcfg.get('SESSION_INDEX')` devolve `"1"` (é a conta
   do histórico certo). Se não, regista `bloqueado` e pára.
4. Corre este JavaScript (lê `lockupViewModel` no `ytInitialData`; o antigo `videoRenderer`
   devolve 0) e descarrega o ficheiro no formato do Takeout:

```js
const hoje=new Date(); hoje.setHours(12,0,0,0);
const dias=['domingo','segunda-feira','terça-feira','quarta-feira','quinta-feira','sexta-feira','sábado'];
const meses={jan:0,fev:1,mar:2,abr:3,mai:4,jun:5,jul:6,ago:7,set:8,out:9,nov:10,dez:11};
function dataDe(s){const t=s.toLowerCase().trim(),d=new Date(hoje);if(t==='hoje')return d;
 if(t==='ontem'){d.setDate(d.getDate()-1);return d}const i=dias.indexOf(t);
 if(i>=0){let k=(hoje.getDay()-i+7)%7;if(k===0)k=7;d.setDate(d.getDate()-k);return d}
 const m=t.match(/(\d{1,2}) de (\w{3})\.?(?: de (\d{4}))?/);
 if(m){const y=m[3]?+m[3]:hoje.getFullYear();const r=new Date(y,meses[m[2]],+m[1],12);if(r>hoje)r.setFullYear(y-1);return r}return null}
const secs=ytInitialData.contents.twoColumnBrowseResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer.contents;
const tk=[];let i=0;
for(const s of secs){const isr=s.itemSectionRenderer;if(!isr)continue;
 const h=isr.header?.itemSectionHeaderRenderer?.title;const sec=h?.runs?.map(r=>r.text).join('')||h?.simpleText||'';
 const dia=dataDe(sec);
 for(const it of isr.contents||[]){const l=it.lockupViewModel;if(!l||l.contentType!=='LOCKUP_CONTENT_TYPE_VIDEO'||!dia)continue;
  const m=l.metadata?.lockupMetadataViewModel;const canal=m?.metadata?.contentMetadataViewModel?.metadataRows?.[0]?.metadataParts?.[0]?.text?.content||'';
  tk.push({header:'YouTube',title:'Watched '+(m?.title?.content||''),titleUrl:'https://www.youtube.com/watch?v='+l.contentId,
   subtitles:canal?[{name:canal}]:[],time:dia.toISOString().slice(0,10)+'T12:00:'+String(59-(i++%60)).padStart(2,'0')+'.000Z',
   products:['YouTube'],activityControls:['YouTube watch history'],fonte:'feed/history authuser=1 lockupViewModel'})}}
const nome='watch-history-'+new Date().toISOString().slice(0,10)+'.json';
const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(tk,null,1)],{type:'application/json'}));
a.download=nome;document.body.appendChild(a);a.click();({nome,entradas:tk.length})
```

5. Move o ficheiro de `C:\Users\danil\Downloads\` para
   `C:\Users\danil\Desktop\QG\radar-video\historico\` (mesmo nome) e confirma que tem > 0
   entradas lendo-o de volta. Fecha o separador que abriste.
5b. SUGESTÕES DA PÁGINA INICIAL (desde 04/10, pedido do Danilo: "o YouTube já sabe os vídeos
   de que eu gosto, procura nas sugestões"). No mesmo perfil pessoal, separador novo →
   `https://www.youtube.com/?authuser=1`. Confirma `ytcfg.get('SESSION_INDEX')` = `"1"`.
   Corre este JavaScript (desce a página 6 vezes para carregar mais sugestões e grava no
   mesmo formato do Takeout, para o `radar_crescimento.py historico` ler sem mudar nada):

```js
for(let k=0;k<6;k++){window.scrollTo(0,document.documentElement.scrollHeight);await new Promise(r=>setTimeout(r,1800));}
const vistos=new Set(),tk=[];const agora=new Date();agora.setHours(12,0,0,0);
for(const a of document.querySelectorAll('a[href*="/watch?v="]')){
 const m=a.href.match(/[?&]v=([\w-]{11})/);if(!m||vistos.has(m[1]))continue;
 const box=a.closest('ytd-rich-item-renderer,yt-lockup-view-model,ytd-video-renderer,ytd-compact-video-renderer');if(!box)continue;
 const t=[box.querySelector('#video-title,.yt-lockup-metadata-view-model__title,h3')?.textContent,a.getAttribute('title'),a.getAttribute('aria-label')]
  .map(s=>(s||'').replace(/\s+/g,' ').trim()).find(s=>s.length>=8);
 if(!t)continue;
 const canal=(box.querySelector('ytd-channel-name a,a[href^="/@"]')?.textContent||'').replace(/\s+/g,' ').trim();
 vistos.add(m[1]);
 tk.push({header:'YouTube',title:t.slice(0,200),titleUrl:'https://www.youtube.com/watch?v='+m[1],subtitles:canal?[{name:canal}]:[],
  time:agora.toISOString(),products:['YouTube'],activityControls:['YouTube home feed'],fonte:'home authuser=1 sugestoes'});}
const nome='recomendados-'+new Date().toISOString().slice(0,10)+'.json';
const b=document.createElement('a');b.href=URL.createObjectURL(new Blob([JSON.stringify(tk,null,1)],{type:'application/json'}));
b.download=nome;document.body.appendChild(b);b.click();({nome,entradas:tk.length})
```

   Se devolver 0 entradas, a página mudou de estrutura: vê como estão feitos os blocos de
   vídeo, ajusta o seletor, e reescreve AQUI nesta ordem o JavaScript que funcionou (para a
   noite seguinte não falhar igual). Os Shorts (`/shorts/`) ficam de fora de propósito.
   Move `recomendados-AAAA-MM-DD.json` de `C:\Users\danil\Downloads\` para a mesma pasta
   `historico\`, confirma que tem > 0 entradas lendo-o de volta e fecha o separador.
   Se o passo 5b falhar, o passo 4/5 (histórico) continua a valer: regista a falha e segue.

6. Linha no `e2e_log` (Supabase `ojykpzwqrtusfeakzrna`): `fluxo='radar-historico'`,
   `passo='0145'`, `estado='ok'` (ou `falhou`/`bloqueado` com o motivo real), e no
   `detalhe` o nome dos ficheiros e o número de entradas de cada um (histórico e sugestões).

O radar das 02:00 faz o resto sozinho: B1 lê a pasta `historico\` e o
`radar_crescimento.py historico` põe os vídeos do tema na tabela `radar_videos`.
