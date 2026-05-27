import { createClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

const supabase = createClient(supabaseUrl, serviceRoleKey);

interface UploadRequest {
  restaurantId: string;
  kind: string; // 'owner_doc' or 'activity_doc'
  fileBase64: string;
  contentType: string;
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      });
    }

    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" },
      });
    }

    const body = (await req.json()) as UploadRequest;

    if (!body.restaurantId || !body.kind || !body.fileBase64) {
      return new Response(
        JSON.stringify({ error: "restaurantId, kind, and fileBase64 required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Decode base64 to bytes
    const binaryString = atob(body.fileBase64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }

    // Generate unique filename
    const extension = body.contentType.split('/')[1] || 'jpg';
    const timestamp = Date.now();
    const filename = `${body.restaurantId}/${body.kind}-${timestamp}.${extension}`;

    // Upload to Supabase Storage (restaurant-assets bucket - public)
    const { data: uploadData, error: uploadError } = await supabase.storage
      .from('restaurant-assets')
      .upload(filename, bytes, {
        contentType: body.contentType,
        upsert: false,
      });

    if (uploadError) {
      console.error('Upload error:', uploadError);
      return new Response(
        JSON.stringify({ error: `Upload failed: ${uploadError.message}` }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Get public URL
    const { data: publicUrlData } = supabase.storage
      .from('restaurant-assets')
      .getPublicUrl(filename);

    return new Response(
      JSON.stringify({
        success: true,
        public_url: publicUrlData.publicUrl,
        path: filename,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: `Server error: ${error.message}` }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
