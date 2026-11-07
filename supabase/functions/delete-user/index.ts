// ลบบัญชีของผู้ใช้ที่เรียกฟังก์ชันนี้ พร้อมข้อมูลทั้งหมดของบัญชีนั้น
// ระบุตัวผู้ใช้จาก JWT เท่านั้น จึงลบบัญชีของคนอื่นไม่ได้
// (SUPABASE_URL และ SUPABASE_SERVICE_ROLE_KEY มีให้อัตโนมัติบน Supabase)
//
// deploy: supabase functions deploy delete-user
// ต้องรัน supabase/sql/delete_user_data.sql ก่อน (ฟังก์ชันลบข้อมูลในตาราง)
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

// ที่เก็บรูปของผู้ใช้ทุกที่ (ไฟล์อยู่ที่ <bucket>/<user id>/<ชื่อไฟล์>)
// - recipe-images: รูปเมนูที่แนบตอนเขียนสูตรเอง (lib/services/recipe_repository.dart)
// - fridge-images: รูปวัตถุดิบตอนสแกนเข้าตู้ (lib/services/fridge_images.dart)
// - recipe-scan-images: รูปสูตรที่สแกน (lib/services/fridge_images.dart)
// เดิมลบแค่ recipe-images รูปวัตถุดิบและรูปสูตรที่สแกนเลยค้างอยู่
const IMAGE_BUCKETS = ["recipe-images", "fridge-images", "recipe-scan-images"];

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ลบรูปทุกไฟล์ในโฟลเดอร์ของผู้ใช้ใน bucket หนึ่ง (list ได้ทีละหน้า วนจนกว่าจะไม่เหลือ)
async function deleteUserImages(
  admin: SupabaseClient,
  bucketName: string,
  userId: string,
) {
  const bucket = admin.storage.from(bucketName);

  while (true) {
    const { data: files, error } = await bucket.list(userId, { limit: 100 });
    if (error) {
      // แอปยังใช้งานได้แม้ไม่มี bucket นี้ กรณีนั้นถือว่าไม่มีรูปให้ลบ
      if (/bucket not found/i.test(error.message)) return;
      throw error;
    }
    if (!files || files.length === 0) return;

    const { error: removeError } = await bucket.remove(
      files.map((file) => `${userId}/${file.name}`),
    );
    if (removeError) throw removeError;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) {
    return json(401, { error: "Unauthorized" });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: { user }, error: userError } = await admin.auth.getUser(token);
  if (userError || !user) {
    return json(401, { error: "Unauthorized" });
  }

  try {
    // ลบข้อมูลในตารางก่อน (สำเร็จหรือยกเลิกทั้งหมดในครั้งเดียว) เพื่อไม่ให้เสียรูปไปฟรีถ้าขั้นนี้พลาด
    // ลบ auth user เป็นขั้นสุดท้าย ถ้าขั้นก่อนหน้าพลาด ผู้ใช้ยัง login กลับมาลองใหม่ได้
    const { error: rowsError } = await admin.rpc("delete_user_data", {
      target_user: user.id,
    });
    if (rowsError) throw rowsError;

    for (const bucketName of IMAGE_BUCKETS) {
      await deleteUserImages(admin, bucketName, user.id);
    }

    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) throw error;

    return json(200, { success: true });
  } catch (error) {
    console.error("delete-user failed", user.id, error);
    return json(500, { error: "Delete account failed" });
  }
});
