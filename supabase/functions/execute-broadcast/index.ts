// execute-broadcast v7 — 2026-09-23 (ronda-fecho D3): comunicação comercial só a
// quem deu opt-in separado (push_broadcasts.only_marketing_opt_in -> users.marketing_opt_in).
// v2..v6 viviam só no servidor (sem fonte no repo); este ficheiro é a fonte a partir de agora.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const SUPABASE_URL=Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const FB_PROJECT=Deno.env.get('FIREBASE_PROJECT_ID')!;
const FB_SA=Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!;
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};

Deno.serve(async(req)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  const sb=createClient(SUPABASE_URL,SERVICE_KEY,{auth:{autoRefreshToken:false,persistSession:false}});
  const body=await req.json().catch(()=>({}));
  const broadcastId:string|null=body?.broadcast_id??null;
  let query=sb.from('push_broadcasts').select('*').eq('status','pending');
  if(broadcastId)query=query.eq('id',broadcastId);
  const{data:broadcasts,error:bErr}=await query;
  if(bErr)return new Response(JSON.stringify({ok:false,error:bErr.message}),{status:500,headers:{...cors,'content-type':'application/json'}});
  if(!broadcasts?.length)return new Response(JSON.stringify({ok:true,message:'no pending broadcasts'}),{headers:{...cors,'content-type':'application/json'}});
  let accessToken:string;
  try{const sa=JSON.parse(FB_SA);accessToken=await getFirebaseToken(sa);}
  catch(e){return new Response(JSON.stringify({ok:false,error:`firebase auth: ${e}`}),{status:500,headers:{...cors,'content-type':'application/json'}});}
  const results=[];
  for(const broadcast of broadcasts){
    await sb.from('push_broadcasts').update({status:'sending'}).eq('id',broadcast.id);
    const onlyOptIn=broadcast.only_marketing_opt_in===true;
    const tokens=await getTokens(sb,broadcast.segment,onlyOptIn);
    console.log(`[execute-broadcast] id=${broadcast.id} segment=${broadcast.segment} only_opt_in=${onlyOptIn} tokens=${tokens.length}`);
    if(tokens.length===0){
      await sb.from('push_broadcasts').update({status:'completed',sent_count:0}).eq('id',broadcast.id);
      results.push({broadcast_id:broadcast.id,sent:0,failed:0});continue;
    }
    let sent=0,failed=0;
    const BATCH=50;
    for(let i=0;i<tokens.length;i+=BATCH){
      const batch=tokens.slice(i,i+BATCH);
      const res=await Promise.allSettled(batch.map(t=>sendFcm(accessToken,t.fcm_token,broadcast.title,broadcast.body,broadcast.segment)));
      for(const r of res){if(r.status==='fulfilled'&&r.value.ok)sent++;else failed++;}
    }
    await sb.from('push_broadcasts').update({status:'completed',sent_count:sent,failed_count:failed,completed_at:new Date().toISOString()}).eq('id',broadcast.id);
    console.log(`[execute-broadcast] done id=${broadcast.id} sent=${sent} failed=${failed}`);
    results.push({broadcast_id:broadcast.id,sent,failed});
  }
  return new Response(JSON.stringify({ok:true,results}),{headers:{...cors,'content-type':'application/json'}});
});

// D3 (2026-09-23): com onlyOptIn só entram aparelhos de utilizadores com
// users.marketing_opt_in = true (parceiros pelo dono da loja: restaurants.user_id).
async function getTokens(sb:any,segment:string,onlyOptIn:boolean):Promise<{fcm_token:string}[]>{
  let optIn:Set<string>|null=null;
  if(onlyOptIn){
    const{data}=await sb.from('users').select('id').eq('marketing_opt_in',true);
    optIn=new Set((data??[]).map((u:any)=>String(u.id)));
  }
  const soOptIn=(rows:any[],key:string)=>onlyOptIn?rows.filter((r:any)=>optIn!.has(String(r[key]))):rows;
  const clients=async()=>{const{data}=await sb.from('client_push_tokens').select('fcm_token,user_id').eq('active',true);return soOptIn(data??[],'user_id');};
  const drivers=async()=>{const{data}=await sb.from('driver_push_tokens').select('fcm_token,user_id').eq('active',true);return soOptIn(data??[],'user_id');};
  const partners=async()=>{
    const{data}=await sb.from('partner_push_tokens').select('fcm_token,partner_id').eq('active',true);
    if(!onlyOptIn)return data??[];
    if(optIn!.size===0)return[];
    const{data:rs}=await sb.from('restaurants').select('id,user_id').in('user_id',[...optIn!]);
    const ok=new Set((rs??[]).map((r:any)=>String(r.id)));
    return(data??[]).filter((t:any)=>ok.has(String(t.partner_id)));
  };
  if(segment==='all'){
    const[c,d,p]=await Promise.all([clients(),drivers(),partners()]);
    return[...c,...d,...p];
  }
  if(segment==='clients')return await clients();
  if(segment==='drivers')return await drivers();
  if(segment==='partners')return await partners();
  return[];
}

async function sendFcm(accessToken:string,fcmToken:string,title:string,body:string,segment:string):Promise<{ok:boolean}>{
  const url=`https://fcm.googleapis.com/v1/projects/${FB_PROJECT}/messages:send`;
  const msg={message:{token:fcmToken,notification:{title,body},data:{type:'admin_broadcast',segment},android:{priority:'high',notification:{channel_id:'bora_general',sound:'default'}},apns:{headers:{'apns-priority':'10'},payload:{aps:{sound:'default'}}}}};
  try{
    const res=await fetch(url,{method:'POST',headers:{'Authorization':`Bearer ${accessToken}`,'Content-Type':'application/json'},body:JSON.stringify(msg)});
    if(!res.ok){const t=await res.text();console.error(`[execute-broadcast] FCM error ${res.status}: ${t.slice(0,200)}`);}
    return{ok:res.ok};
  }catch{return{ok:false};}
}

async function getFirebaseToken(sa:any):Promise<string>{
  const now=Math.floor(Date.now()/1000);
  const b64u=(s:string)=>btoa(unescape(encodeURIComponent(s))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'');
  const b64uB=(b:Uint8Array)=>btoa(String.fromCharCode(...b)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'');
  const sigIn=`${b64u(JSON.stringify({alg:'RS256',typ:'JWT'}))}.${b64u(JSON.stringify({iss:sa.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',exp:now+3600,iat:now}))}`;
  const kb=Uint8Array.from(atob(sa.private_key.replace(/-----[^-]+-----/g,'').replace(/\s/g,'')),c=>c.charCodeAt(0));
  const key=await crypto.subtle.importKey('pkcs8',kb,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const sig=b64uB(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(sigIn))));
  const res=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:`${sigIn}.${sig}`})});
  const data=await res.json();
  if(!data.access_token)throw new Error(JSON.stringify(data));
  return data.access_token;
}
