-- =============================================================================
-- (ทางเลือก Phase 2) Vector Similarity Search ด้วย pgvector
-- รันหลังจาก migrations/20261104000000_global_recipes.sql แล้วเท่านั้น
--
-- ใช้เมื่อการค้นหาด้วยชื่อ/วัตถุดิบ (trigram) ยังพลาดสูตรที่ "ความหมายเดียวกันแต่เขียนต่างกัน"
-- เช่น "กะเพราหมูกรอบ" กับ "ผัดกะเพราหมูสามชั้นทอด"
-- ต้องเรียก Gemini Embedding API ทั้งตอนบันทึกและตอนค้นหา (ถูกกว่าการให้ Gemini
-- สร้างสูตรใหม่หลายเท่า แต่ยังไม่ฟรี) — ตั้ง output dimensionality = 768 ให้ตรงกับคอลัมน์
-- ข้อความที่ใช้ทำ embedding แนะนำ: "<ชื่อสูตร>: <วัตถุดิบ1>, <วัตถุดิบ2>, ..."
-- =============================================================================

begin;

create extension if not exists vector with schema extensions;

alter table public.recipes
  add column if not exists embedding extensions.vector(768);

create index if not exists recipes_embedding_hnsw_idx
  on public.recipes using hnsw (embedding extensions.vector_cosine_ops);

-- ใส่ embedding ให้สูตร (เฉพาะคนที่ bookmark สูตรนั้นไว้ และสูตรยังไม่มี embedding)
create or replace function public.set_recipe_embedding(
  p_recipe_id  uuid,
  p_embedding  extensions.vector(768)
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  update public.recipes r
     set embedding = p_embedding
   where r.id = p_recipe_id
     and r.embedding is null
     and (r.created_by = auth.uid()
          or exists (select 1 from public.user_saved_recipes usr
                      where usr.recipe_id = r.id and usr.user_id = auth.uid()));
end;
$$;

-- ค้นหาสูตรที่ความหมายใกล้เคียง (cosine similarity: 1 = เหมือนกันมาก)
create or replace function public.match_recipes_by_embedding(
  p_embedding        extensions.vector(768),
  p_min_similarity   double precision default 0.85,
  p_limit            integer default 5
)
returns table (recipe_id uuid, recipe_name text, similarity double precision, recipe jsonb)
language sql
stable
set search_path = public, extensions
as $$
  select r.id,
         r.name,
         1 - (r.embedding <=> p_embedding),
         public.recipe_to_app_json(r.id)
    from public.recipes r
   where r.embedding is not null
     and 1 - (r.embedding <=> p_embedding) >= p_min_similarity
   order by r.embedding <=> p_embedding
   limit least(greatest(coalesce(p_limit, 5), 1), 20);
$$;

revoke all on function public.set_recipe_embedding(uuid, extensions.vector) from public, anon;
grant execute on function public.set_recipe_embedding(uuid, extensions.vector) to authenticated;
grant execute on function public.match_recipes_by_embedding(extensions.vector, double precision, integer)
  to anon, authenticated;

commit;
