// Verificação independente das fotos: para uma amostra ao acaso (ou todas com "todas"), pede o URL público
// sem cache e compara tamanho, primeiros bytes e md5 com a cópia descarregada da Glovo (pasta temporária).
// Uso: node verificar_fotos.mjs [n=40|todas]
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";
const HERE = path.dirname(fileURLToPath(import.meta.url));
const FOTOS = "C:/Users/danil/AppData/Local/Temp/farmacias-fotos";
const arg = process.argv[2] || "40";
const md5 = (b) => crypto.createHash("md5").update(b).digest("hex");
const res = { ok: 0, falha: [] };
for (const loja of ["farmacia-se-guarda", "farmacia-teixeira-guarda"]) {
  const itens = JSON.parse(fs.readFileSync(path.join(HERE, `${loja}.json`), "utf8"));
  let amostra = itens;
  if (arg !== "todas") {
    const n = Number(arg);
    amostra = [...itens].sort(() => Math.random() - 0.5).slice(0, n);
  }
  let i = 0;
  await Promise.all(Array.from({ length: 4 }, async () => {
    while (i < amostra.length) {
      const it = amostra[i++];
      const ext = it.photo_url ? it.photo_url.split(".").pop() : "";
      const local = path.join(FOTOS, loja, `${it.id}.${ext}`);
      try {
        const r = await fetch(it.photo_url + "?chk=" + Date.now(), { headers: { "Cache-Control": "no-cache" } });
        const b = Buffer.from(await r.arrayBuffer());
        const l = fs.readFileSync(local);
        const head = b.subarray(0, 3).toString("hex");
        const ok = r.status === 200 && b.length === l.length && md5(b) === md5(l) && b.length === it.photo_bytes && head === "ffd8ff" === (it.photo_type === "image/jpeg");
        if (ok) res.ok++; else res.falha.push({ id: it.id, status: r.status, bytes: b.length, esperado: it.photo_bytes, head });
      } catch (e) { res.falha.push({ id: it.id, erro: e.message }); }
    }
  }));
}
console.log(JSON.stringify({ verificadas: res.ok + res.falha.length, ok: res.ok, falhas: res.falha.slice(0, 20), n_falhas: res.falha.length }));
