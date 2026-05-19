import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, X-Client-Info, Apikey",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function chunkText(text: string, maxTokens = 400): string[] {
  const paragraphs = text.split(/\n{2,}/);
  const chunks: string[] = [];
  let current = "";

  for (const para of paragraphs) {
    const trimmed = para.trim();
    if (!trimmed) continue;

    const estimatedTokens = (current + "\n\n" + trimmed).length / 4;
    if (estimatedTokens > maxTokens && current) {
      chunks.push(current.trim());
      current = trimmed;
    } else {
      current = current ? current + "\n\n" + trimmed : trimmed;
    }
  }
  if (current.trim()) {
    chunks.push(current.trim());
  }

  // If we got no chunks from paragraph splitting, split by sentences
  if (chunks.length === 0 && text.trim()) {
    const sentences = text.split(/(?<=[.!?])\s+/);
    let buf = "";
    for (const s of sentences) {
      if ((buf + " " + s).length / 4 > maxTokens && buf) {
        chunks.push(buf.trim());
        buf = s;
      } else {
        buf = buf ? buf + " " + s : s;
      }
    }
    if (buf.trim()) chunks.push(buf.trim());
  }

  return chunks;
}

async function generateEmbedding(text: string): Promise<number[]> {
  const model = new Supabase.ai.Session("gte-small");
  const output = await model.run(text, { mean_pool: true, normalize: true });
  return Array.from(output as Float32Array);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // User client for auth check
    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: "Not authenticated" }, 401);
    }

    // Service role client for DB writes (bypasses RLS)
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Check admin status
    const userEmail = userData.user.email?.toLowerCase() ?? "";
    const { data: adminRow } = await supabase
      .from("admin_users")
      .select("role,permissions")
      .eq("email", userEmail)
      .maybeSingle();

    if (!adminRow) {
      return json({ error: "Admin access required" }, 403);
    }

    const isSuper = adminRow.role === "super_admin";
    const canCreate =
      isSuper || (adminRow.permissions?.chatbot?.create === true);
    if (!canCreate) {
      return json({ error: "No permission to manage knowledge base" }, 403);
    }

    const contentType = req.headers.get("content-type") ?? "";

    if (contentType.includes("multipart/form-data")) {
      // File upload
      const formData = await req.formData();
      const file = formData.get("file") as File | null;
      const title = (formData.get("title") as string) ?? "";

      if (!file) return json({ error: "No file provided" }, 400);

      const maxSize = 10 * 1024 * 1024; // 10 MB
      if (file.size > maxSize) {
        return json({ error: "File too large (max 10 MB)" }, 400);
      }

      const allowedTypes = [
        "text/plain",
        "text/csv",
        "text/markdown",
        "application/json",
        "application/pdf",
      ];
      const ext = file.name.split(".").pop()?.toLowerCase() ?? "";
      const allowedExts = ["txt", "csv", "md", "json", "pdf"];

      if (!allowedTypes.includes(file.type) && !allowedExts.includes(ext)) {
        return json(
          { error: "Unsupported file type. Use: txt, csv, md, json, pdf" },
          400
        );
      }

      // Create document record
      const { data: doc, error: docErr } = await supabase
        .from("kb_documents")
        .insert({
          user_id: userData.user.id,
          title: title || file.name.replace(/\.[^/.]+$/, ""),
          file_name: file.name,
          file_type: ext || file.type,
          file_size: file.size,
          status: "processing",
        })
        .select()
        .single();

      if (docErr || !doc) {
        return json({ error: "Failed to create document record" }, 500);
      }

      // Extract text
      let text = "";
      try {
        if (ext === "pdf" || file.type === "application/pdf") {
          // For PDFs, read as text (basic extraction)
          const buffer = await file.arrayBuffer();
          const bytes = new Uint8Array(buffer);
          // Simple PDF text extraction: find text between stream markers
          const decoder = new TextDecoder("utf-8", { fatal: false });
          const raw = decoder.decode(bytes);
          // Extract readable text segments
          const textSegments: string[] = [];
          const streamRegex = /stream\r?\n([\s\S]*?)\r?\nendstream/g;
          let match;
          while ((match = streamRegex.exec(raw)) !== null) {
            const segment = match[1]
              .replace(/[^\x20-\x7E\n\r\t]/g, " ")
              .replace(/\s+/g, " ")
              .trim();
            if (segment.length > 20) textSegments.push(segment);
          }
          // Fallback: just extract any readable strings
          if (textSegments.length === 0) {
            text = raw
              .replace(/[^\x20-\x7E\n\r\t]/g, " ")
              .replace(/\s{3,}/g, "\n")
              .trim();
          } else {
            text = textSegments.join("\n\n");
          }
        } else {
          text = await file.text();
        }
      } catch {
        await supabase
          .from("kb_documents")
          .update({ status: "error", error_message: "Failed to extract text" })
          .eq("id", doc.id);
        return json({ error: "Failed to extract text from file" }, 500);
      }

      if (!text.trim()) {
        await supabase
          .from("kb_documents")
          .update({
            status: "error",
            error_message: "No readable text found in file",
          })
          .eq("id", doc.id);
        return json({ error: "No readable text found in file" }, 400);
      }

      // Chunk the text
      const chunks = chunkText(text);

      // Generate embeddings and insert chunks
      const chunkRows = [];
      for (let i = 0; i < chunks.length; i++) {
        const embedding = await generateEmbedding(chunks[i]);
        chunkRows.push({
          document_id: doc.id,
          source_table: "kb_documents",
          source_id: doc.id,
          title: `${doc.title} - chunk ${i + 1}`,
          content: chunks[i],
          metadata: { chunk_index: i, file_name: file.name },
          embedding: JSON.stringify(embedding),
        });
      }

      if (chunkRows.length > 0) {
        const { error: chunkErr } = await supabase
          .from("kb_chunks")
          .insert(chunkRows);

        if (chunkErr) {
          await supabase
            .from("kb_documents")
            .update({
              status: "error",
              error_message: `Failed to store chunks: ${chunkErr.message}`,
            })
            .eq("id", doc.id);
          return json({ error: "Failed to store document chunks" }, 500);
        }
      }

      // Mark as ready
      await supabase
        .from("kb_documents")
        .update({
          status: "ready",
          chunk_count: chunkRows.length,
          updated_at: new Date().toISOString(),
        })
        .eq("id", doc.id);

      return json({
        id: doc.id,
        title: doc.title,
        chunks: chunkRows.length,
        status: "ready",
      });
    } else if (contentType.includes("application/json")) {
      // Text paste upload
      const body = await req.json();
      const { title, content } = body;

      if (!content || !content.trim()) {
        return json({ error: "No content provided" }, 400);
      }

      if (content.length > 500000) {
        return json({ error: "Content too large (max 500K characters)" }, 400);
      }

      const { data: doc, error: docErr } = await supabase
        .from("kb_documents")
        .insert({
          user_id: userData.user.id,
          title: title || "Pasted content",
          file_name: "paste.txt",
          file_type: "txt",
          file_size: content.length,
          status: "processing",
        })
        .select()
        .single();

      if (docErr || !doc) {
        return json({ error: "Failed to create document record" }, 500);
      }

      const chunks = chunkText(content);
      const chunkRows = [];

      for (let i = 0; i < chunks.length; i++) {
        const embedding = await generateEmbedding(chunks[i]);
        chunkRows.push({
          document_id: doc.id,
          source_table: "kb_documents",
          source_id: doc.id,
          title: `${title || "Pasted content"} - chunk ${i + 1}`,
          content: chunks[i],
          metadata: { chunk_index: i },
          embedding: JSON.stringify(embedding),
        });
      }

      if (chunkRows.length > 0) {
        const { error: chunkErr } = await supabase
          .from("kb_chunks")
          .insert(chunkRows);

        if (chunkErr) {
          await supabase
            .from("kb_documents")
            .update({
              status: "error",
              error_message: `Failed to store chunks: ${chunkErr.message}`,
            })
            .eq("id", doc.id);
          return json({ error: "Failed to store document chunks" }, 500);
        }
      }

      await supabase
        .from("kb_documents")
        .update({
          status: "ready",
          chunk_count: chunkRows.length,
          updated_at: new Date().toISOString(),
        })
        .eq("id", doc.id);

      return json({
        id: doc.id,
        title: doc.title,
        chunks: chunkRows.length,
        status: "ready",
      });
    }

    return json({ error: "Invalid content type" }, 400);
  } catch (e) {
    return json({ error: (e as Error).message ?? "Unexpected error" }, 500);
  }
});
