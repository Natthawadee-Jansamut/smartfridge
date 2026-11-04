-- =============================================================================
-- SmartFridge.AI — Master Recipes (คลังสูตรอาหารกลาง เพื่อลดการเรียก Gemini)
-- ขั้นที่ 1: EXPAND + MIGRATE  (รันได้ทันที แอปเวอร์ชันปัจจุบันยังทำงานเหมือนเดิม)
--
-- ตารางใหม่
--   ingredients          วัตถุดิบกลาง (1 ชื่อมาตรฐาน = 1 แถว)
--   ingredient_aliases   ชื่อเรียกอื่นของวัตถุดิบเดียวกัน (ไข่ -> ไข่ไก่)
--   recipes              สูตรกลาง (ทุกคนอ่านได้ถ้า is_public)
--   recipe_ingredients   ส่วนผสมของแต่ละสูตร (M:N recipes <-> ingredients)
--   user_saved_recipes   สูตรที่ผู้ใช้ Bookmark + ส่วนที่แก้เป็นของตัวเอง
--   ai_request_logs      Log การเรียก AI ทุกครั้ง (cache_hit / gemini) ใช้วัดผลประหยัด token
--
-- ตารางเดิมที่เพิ่มคอลัมน์ (nullable ทั้งหมด ไม่กระทบโค้ดเดิม)
--   fridge_items.ingredient_id   (เติมให้อัตโนมัติด้วย trigger จากชื่อ)
--   weekly_meals.recipe_id       (มื้อนี้ใช้สูตรกลางไหน)
--   weekly_meals.user_id         (ให้ RLS / query ไม่ต้อง join ผ่าน meal_plans)
--
-- ไม่แก้: profiles, meal_plans และไม่ลบ/เปลี่ยนชื่อ scanned_recipes ในขั้นนี้
-- (ขั้นที่ 2 อยู่ใน 20261104000100_contract_legacy_recipes.sql — รันหลังแอปเวอร์ชันใหม่)
--
-- รันทั้งไฟล์ใน Supabase SQL Editor ได้เลย ทำใน transaction เดียว ถ้า error จะไม่ค้างครึ่งๆ
-- =============================================================================

begin;

create extension if not exists pg_trgm with schema extensions;

-- schema ที่ PostgREST ไม่เปิดเป็น API — ฟังก์ชันภายในที่ client เรียกตรงไม่ได้
create schema if not exists private;

-- =============================================================================
-- 1) Helper functions (ไม่อ้างถึงตาราง)
-- =============================================================================

-- ทำข้อความให้เป็นมาตรฐานก่อนเทียบ: " ผัด กะเพรา-หมู " -> "ผัดกะเพราหมู"
--   NFKC (รวมรูปตัวอักษรที่หน้าตาเหมือนกัน เช่น ำ กับ ํ+า) -> ตัวพิมพ์เล็ก
--   -> ตัดช่องว่างและเครื่องหมายทั้งหมด (ภาษาไทยเว้นวรรคไม่สม่ำเสมอ)
create or replace function public.normalize_text(p text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select nullif(
    -- NFKC ต้องเป็น keyword ไม่ใช่ string ('NFKC') ตาม syntax ของ normalize()
    regexp_replace(lower(normalize(coalesce(p, ''), NFKC)), '[[:space:][:punct:]]+', '', 'g'),
    ''
  );
$$;

-- เวลาทำเป็นนาที: "45 นาที", "1 ชั่วโมง 30 นาที", "1.5 ชม." (ตรงกับ RecipeRepository.minutesOf)
create or replace function public.parse_minutes(p text)
returns integer
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case when m between 0 and 1440 then round(m)::integer end
  from (
    select case
      when p is null then null
      when p ~ '\d+(\.\d+)?\s*(ชั่วโมง|ชม)' or p ~ '\d+\s*(นาที|น\.)' then
        coalesce(substring(p from '(\d+(?:\.\d+)?)\s*(?:ชั่วโมง|ชม)')::numeric, 0) * 60
        + coalesce(substring(p from '(\d+)\s*(?:นาที|น\.)')::numeric, 0)
      else substring(p from '(\d+(?:\.\d+)?)')::numeric
    end as m
  ) t;
$$;

-- ตัวเลขนำหน้าข้อความ: "2" -> 2, "1/2 ช้อนชา" -> 0.5, "450 kcal" -> 450, "เล็กน้อย" -> null
create or replace function private.parse_qty(p text)
returns numeric
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p ~ '^\s*\d+(\.\d+)?\s*/\s*\d+(\.\d+)?' then
      case when substring(p from '^\s*\d+(?:\.\d+)?\s*/\s*(\d+(?:\.\d+)?)')::numeric > 0 then
        substring(p from '^\s*(\d+(?:\.\d+)?)')::numeric
        / substring(p from '^\s*\d+(?:\.\d+)?\s*/\s*(\d+(?:\.\d+)?)')::numeric
      end
    when p ~ '^\s*\d+(\.\d+)?' then
      substring(p from '^\s*(\d+(?:\.\d+)?)')::numeric
  end;
$$;

-- หน่วยที่เหลือหลังตัดตัวเลขนำหน้า: "1 ชิ้น" -> "ชิ้น", "เล็กน้อย" -> "เล็กน้อย"
create or replace function private.parse_unit(p text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select nullif(btrim(regexp_replace(coalesce(p, ''), '^\s*\d+(\.\d+)?(\s*/\s*\d+(\.\d+)?)?\s*', '')), '');
$$;

-- รับค่าที่ "ควรเป็น array" จากหลายแหล่ง: array -> ใช้เลย, ข้อความ JSON -> parse,
-- ข้อความธรรมดา (เช่น steps ของ weekly_meals "1. ...\n2. ...") -> แยกทีละบรรทัด
create or replace function private.as_json_array(p jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v jsonb;
begin
  if p is null or jsonb_typeof(p) = 'null' then
    return '[]'::jsonb;
  end if;
  if jsonb_typeof(p) = 'array' then
    return p;
  end if;
  if jsonb_typeof(p) = 'string' then
    begin
      v := (p #>> '{}')::jsonb;
    exception when others then
      v := null;
    end;
    if v is not null and jsonb_typeof(v) = 'array' then
      return v;
    end if;
    return coalesce(
      (select jsonb_agg(to_jsonb(btrim(t.line)) order by t.ord)
         from regexp_split_to_table(p #>> '{}', '\r?\n') with ordinality as t(line, ord)
        where btrim(t.line) <> ''),
      '[]'::jsonb);
  end if;
  return '[]'::jsonb;
end;
$$;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- =============================================================================
-- 2) ตารางใหม่
-- =============================================================================

create table if not exists public.ingredients (
  id            bigint generated always as identity primary key,
  name          text not null check (char_length(btrim(name)) between 1 and 100),
  name_key      text generated always as (public.normalize_text(name)) stored,
  category      text,
  -- ของพื้นฐานที่แทบทุกบ้านมี (เกลือ น้ำปลา น้ำมัน ...) ไม่นับเป็น "วัตถุดิบที่ขาด"
  is_staple     boolean not null default false,
  default_unit  text,
  fridge_days   integer check (fridge_days >= 0),
  freezer_days  integer check (freezer_days >= 0),
  created_at    timestamptz not null default now()
);

create table if not exists public.ingredient_aliases (
  id             bigint generated always as identity primary key,
  alias          text not null check (char_length(btrim(alias)) between 1 and 100),
  alias_key      text generated always as (public.normalize_text(alias)) stored,
  ingredient_id  bigint not null references public.ingredients (id) on delete cascade
);

create table if not exists public.recipes (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null check (char_length(btrim(name)) between 1 and 200),
  name_key              text generated always as (public.normalize_text(name)) stored,
  time_text             text,
  time_minutes          integer check (time_minutes between 0 and 1440),
  servings_text         text,
  instructions          jsonb not null default '[]'::jsonb
                        check (jsonb_typeof(instructions) = 'array'),
  ai_step_indexes       integer[] not null default '{}',
  calories_per_serving  numeric check (calories_per_serving between 0 and 10000),
  protein_per_serving   numeric check (protein_per_serving between 0 and 1000),
  diet_tags             text[] not null default '{}',
  image_url             text,
  -- sha256 ของไฟล์รูปที่สแกน (รูปเดียวกันเป๊ะ = ไม่ต้องส่ง Gemini ซ้ำ)
  image_hash            text,
  source                text not null check (source in ('ai_generated', 'scanned', 'manual')),
  -- md5 ของ id วัตถุดิบ (เรียงแล้ว) ใช้กันสูตรซ้ำ
  ingredient_signature  text not null,
  -- id วัตถุดิบทั้งหมดของสูตร (trigger ดูแลให้ตรงกับ recipe_ingredients) ใช้คัดสูตรเร็วๆ ด้วย &&
  ingredient_ids        bigint[] not null default '{}',
  is_public             boolean not null default true,
  created_by            uuid default auth.uid() references auth.users (id) on delete set null,
  use_count             integer not null default 1,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table if not exists public.recipe_ingredients (
  recipe_id      uuid not null references public.recipes (id) on delete cascade,
  sort_order     smallint not null,
  ingredient_id  bigint not null references public.ingredients (id),
  display_name   text not null,      -- ชื่อตามที่สูตรเขียน (ใช้แสดงผล)
  quantity       numeric check (quantity >= 0),
  unit           text,
  is_main        boolean not null default false,
  primary key (recipe_id, sort_order)
);

create table if not exists public.user_saved_recipes (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  recipe_id    uuid not null references public.recipes (id) on delete cascade,
  -- ผู้ใช้แก้สูตรของตัวเอง (รูปแบบเดียวกับ JSON สูตรในแอป) — ไม่กระทบสูตรกลาง
  overrides    jsonb check (overrides is null or jsonb_typeof(overrides) = 'object'),
  is_favorite  boolean not null default false,
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (user_id, recipe_id)
);

create table if not exists public.ai_request_logs (
  id             bigint generated always as identity primary key,
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  recipe_id      uuid references public.recipes (id) on delete set null,
  event_type     text not null
                 check (event_type in ('scan_recipe', 'generate_menu', 'meal_plan', 'scan_ingredient')),
  result         text not null
                 check (result in ('cache_hit', 'gemini', 'not_recipe', 'failed')),
  image_hash     text,
  model          text,
  prompt_tokens  integer check (prompt_tokens >= 0),
  output_tokens  integer check (output_tokens >= 0),
  created_at     timestamptz not null default now()
);

-- =============================================================================
-- 3) เพิ่มคอลัมน์ในตารางเดิม (nullable — โค้ดแอปเดิมไม่ต้องแก้)
-- =============================================================================

alter table public.fridge_items
  add column if not exists ingredient_id bigint references public.ingredients (id) on delete set null;

alter table public.weekly_meals
  add column if not exists recipe_id uuid references public.recipes (id) on delete set null;

-- default auth.uid(): แอปเวอร์ชันเดิมที่ insert โดยไม่ส่ง user_id ก็ได้ค่าให้อัตโนมัติ
alter table public.weekly_meals
  add column if not exists user_id uuid default auth.uid() references auth.users (id) on delete cascade;

-- จำว่าแถวไหนย้ายเข้าตารางกลางแล้ว (รัน migrate ซ้ำจะทำเฉพาะแถวใหม่)
alter table public.scanned_recipes
  add column if not exists global_recipe_id uuid references public.recipes (id) on delete set null;

-- =============================================================================
-- 4) Indexes
-- =============================================================================

create unique index if not exists ingredients_name_key_uidx on public.ingredients (name_key);
create index if not exists ingredients_name_key_trgm_idx
  on public.ingredients using gin (name_key extensions.gin_trgm_ops);

create unique index if not exists ingredient_aliases_alias_key_uidx on public.ingredient_aliases (alias_key);
create index if not exists ingredient_aliases_ingredient_idx on public.ingredient_aliases (ingredient_id);

-- ชื่อสูตร: exact / LIKE '%..%' / similarity ใช้ index นี้ได้ทั้งหมด
create index if not exists recipes_name_key_trgm_idx
  on public.recipes using gin (name_key extensions.gin_trgm_ops);
-- คัดสูตรที่ใช้ของในตู้เย็นอย่างน้อย 1 ชนิด (ingredient_ids && array)
create index if not exists recipes_ingredient_ids_gin_idx on public.recipes using gin (ingredient_ids);
create index if not exists recipes_diet_tags_gin_idx on public.recipes using gin (diet_tags);
create index if not exists recipes_time_minutes_idx on public.recipes (time_minutes);
create index if not exists recipes_calories_idx on public.recipes (calories_per_serving);
create index if not exists recipes_created_by_idx on public.recipes (created_by, created_at);
-- กันสูตรสาธารณะซ้ำ / รูปซ้ำ (สูตรส่วนตัวของแต่ละคนซ้ำกันได้)
create unique index if not exists recipes_public_dedup_uidx
  on public.recipes (name_key, ingredient_signature) where is_public;
create unique index if not exists recipes_public_image_hash_uidx
  on public.recipes (image_hash) where is_public and image_hash is not null;

create index if not exists recipe_ingredients_ingredient_idx
  on public.recipe_ingredients (ingredient_id, recipe_id);

create index if not exists user_saved_recipes_recipe_idx on public.user_saved_recipes (recipe_id);

create index if not exists ai_request_logs_user_created_idx
  on public.ai_request_logs (user_id, created_at desc);
create index if not exists ai_request_logs_recipe_idx on public.ai_request_logs (recipe_id);

create index if not exists fridge_items_ingredient_idx on public.fridge_items (ingredient_id);
create index if not exists weekly_meals_user_idx on public.weekly_meals (user_id);
create index if not exists weekly_meals_recipe_idx on public.weekly_meals (recipe_id);

-- =============================================================================
-- 5) Functions ที่อ้างถึงตาราง
-- =============================================================================

-- ชื่อวัตถุดิบ -> id วัตถุดิบกลาง (ชื่อตรง หรือชื่อเรียกอื่นใน ingredient_aliases)
create or replace function public.resolve_ingredient_id(p_name text)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select i.id from public.ingredients i where i.name_key = s.k),
    (select a.ingredient_id from public.ingredient_aliases a where a.alias_key = s.k))
  from (select public.normalize_text(p_name) as k) s;
$$;

-- สูตรกลาง -> JSON รูปแบบเดียวกับที่ Gemini ตอบ / scanned_recipes
-- หน้าจอเดิมในแอปจึงเอาไปแสดงได้ทันที
create or replace function public.recipe_to_app_json(p_recipe_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'global_recipe_id', r.id,
    'recipe_name', r.name,
    'time', r.time_text,
    'time_minutes', r.time_minutes,
    'servings', r.servings_text,
    'calories_per_serving', r.calories_per_serving,
    'protein_per_serving', r.protein_per_serving,
    'diet_tags', to_jsonb(r.diet_tags),
    'ingredients_used', coalesce(
      (select jsonb_agg(ri.display_name order by ri.sort_order)
         from public.recipe_ingredients ri
        where ri.recipe_id = r.id and ri.is_main),
      (select jsonb_agg(ri.display_name order by ri.sort_order)
         from public.recipe_ingredients ri
        where ri.recipe_id = r.id),
      '[]'::jsonb),
    'detailed_ingredients', coalesce(
      (select jsonb_agg(jsonb_build_object(
                'name', ri.display_name,
                'use_quantity', ri.quantity,
                'unit', ri.unit) order by ri.sort_order)
         from public.recipe_ingredients ri
        where ri.recipe_id = r.id),
      '[]'::jsonb),
    'instructions', r.instructions,
    'ai_step_indexes', to_jsonb(r.ai_step_indexes),
    'image_url', r.image_url,
    'source', r.source
  )
  from public.recipes r
  where r.id = p_recipe_id;
$$;

-- -----------------------------------------------------------------------------
-- บันทึกสูตรเข้าตารางกลาง (ภายใน — client เรียกตรงไม่ได้)
-- รับ JSON ได้ทั้ง 2 รูปแบบที่แอปใช้อยู่:
--   สูตรอาหาร:  { recipe_name, time, servings, ingredients_used[],
--                detailed_ingredients[{name, use_quantity, unit}],
--                instructions[ "ข้อความ" | {text, ai_generated} ], ai_step_indexes[], image_url }
--   แพลนอาหาร: { food_name, calories, protein, ingredients[{name, quantity: "1 ชิ้น"}],
--                steps: "1. ...\n2. ..." | [..] }
-- ถ้ามีสูตรเดิมที่ชื่อ + วัตถุดิบตรงกันอยู่แล้ว จะคืน id เดิม (ไม่สร้างซ้ำ)
-- -----------------------------------------------------------------------------
create or replace function private.upsert_global_recipe(
  p_recipe      jsonb,
  p_source      text,
  p_created_by  uuid,
  p_image_hash  text default null,
  p_is_public   boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name       text := btrim(coalesce(p_recipe ->> 'recipe_name', p_recipe ->> 'food_name', ''));
  v_name_key   text := public.normalize_text(coalesce(p_recipe ->> 'recipe_name', p_recipe ->> 'food_name'));
  v_items      jsonb := private.as_json_array(
                          coalesce(nullif(p_recipe -> 'detailed_ingredients', 'null'::jsonb),
                                   p_recipe -> 'ingredients'));
  v_steps_raw  jsonb := private.as_json_array(
                          coalesce(nullif(p_recipe -> 'instructions', 'null'::jsonb),
                                   p_recipe -> 'steps'));
  v_used       jsonb := private.as_json_array(p_recipe -> 'ingredients_used');
  v_steps      jsonb;
  v_ai_steps   integer[];
  v_diet_tags  text[];
  v_calories   numeric;
  v_protein    numeric;
  v_signature  text;
  v_recipe_id  uuid;
begin
  -- ---- validate
  if p_source not in ('ai_generated', 'scanned', 'manual') then
    raise exception 'invalid source: %', p_source using errcode = '22023';
  end if;
  if v_name_key is null or char_length(v_name) > 200 then
    raise exception 'invalid recipe name' using errcode = '22023';
  end if;

  -- สูตรเก่าบางสูตรมีแค่ ingredients_used (รายชื่อ) ไม่มีรายละเอียด -> ใช้รายชื่อแทน
  if jsonb_array_length(v_items) = 0 and jsonb_array_length(v_used) > 0 then
    select coalesce(jsonb_agg(jsonb_build_object('name', u)), '[]'::jsonb)
      into v_items
      from jsonb_array_elements_text(v_used) u;
  end if;

  if jsonb_array_length(v_items) = 0 or jsonb_array_length(v_items) > 60 then
    raise exception 'ingredients must have 1-60 items' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(v_items) e
             where char_length(btrim(e ->> 'name')) > 100) then
    raise exception 'ingredient name too long' using errcode = '22023';
  end if;
  if jsonb_array_length(v_steps_raw) > 60 then
    raise exception 'instructions must have at most 60 steps' using errcode = '22023';
  end if;

  -- ---- instructions -> ["ข้อความ"] (ตัดเลขข้อ "1." ออก เหมือน RecipeRepository.stepTextsOf)
  select coalesce(jsonb_agg(to_jsonb(left(t.txt, 2000)) order by t.ord), '[]'::jsonb)
    into v_steps
    from (
      select ord,
             btrim(regexp_replace(
               case when jsonb_typeof(s) = 'object' then s ->> 'text' else s #>> '{}' end,
               '^\s*\d+\s*[\.\)]\s*', '')) as txt
        from jsonb_array_elements(v_steps_raw) with ordinality as x(s, ord)
    ) t
   where t.txt <> '';

  select coalesce(array_agg(distinct i order by i), '{}')
    into v_ai_steps
    from (
      select x::integer as i
        from jsonb_array_elements_text(private.as_json_array(p_recipe -> 'ai_step_indexes')) as x
       where x ~ '^\d{1,2}$'
      union
      select (ord - 1)::integer
        from jsonb_array_elements(v_steps_raw) with ordinality as y(s, ord)
       where jsonb_typeof(s) = 'object' and s ->> 'ai_generated' = 'true'
    ) z;

  -- ---- โภชนาการ / ประเภทอาหาร
  v_calories := private.parse_qty(coalesce(p_recipe ->> 'calories_per_serving', p_recipe ->> 'calories'));
  if v_calories > 10000 then v_calories := null; end if;
  v_protein := private.parse_qty(coalesce(p_recipe ->> 'protein_per_serving', p_recipe ->> 'protein'));
  if v_protein > 1000 then v_protein := null; end if;

  select coalesce(array_agg(distinct lower(btrim(t))), '{}')
    into v_diet_tags
    from jsonb_array_elements_text(private.as_json_array(p_recipe -> 'diet_tags')) t
   where btrim(t) <> '' and char_length(t) <= 50;

  -- ---- วัตถุดิบใหม่ที่ยังไม่มีในระบบ (ชื่อที่เป็น alias อยู่แล้วไม่ต้องสร้าง)
  insert into public.ingredients (name)
  select distinct on (s.k) s.nm
    from (select left(btrim(e ->> 'name'), 100) as nm,
                 public.normalize_text(e ->> 'name') as k
            from jsonb_array_elements(v_items) e) s
   where s.k is not null
     and not exists (select 1 from public.ingredient_aliases a where a.alias_key = s.k)
  on conflict (name_key) do nothing;

  -- ---- ลายเซ็นวัตถุดิบจาก id มาตรฐาน ("ไข่" กับ "ไข่ไก่" ที่เป็น alias กัน = ชุดเดียวกัน)
  select md5(string_agg(s.id::text, ',' order by s.id))
    into v_signature
    from (select distinct public.resolve_ingredient_id(e ->> 'name') as id
            from jsonb_array_elements(v_items) e) s
   where s.id is not null;
  if v_signature is null then
    raise exception 'ingredients has no valid name' using errcode = '22023';
  end if;

  -- ---- มีสูตรนี้อยู่แล้ว? (สูตรสาธารณะ หรือสูตรส่วนตัวของคนเดียวกัน)
  select r.id into v_recipe_id
    from public.recipes r
   where (r.is_public or r.created_by = p_created_by)
     and ((r.name_key = v_name_key and r.ingredient_signature = v_signature)
          or (p_image_hash is not null and r.image_hash = p_image_hash))
   order by r.is_public desc, r.use_count desc
   limit 1;

  if v_recipe_id is null then
    insert into public.recipes (
      name, time_text, time_minutes, servings_text, instructions, ai_step_indexes,
      calories_per_serving, protein_per_serving, diet_tags, image_url, image_hash,
      source, ingredient_signature, is_public, created_by)
    values (
      v_name,
      nullif(btrim(p_recipe ->> 'time'), ''),
      coalesce(
        -- CASE ซ้อน: cast หลังตรวจรูปแบบแล้วเท่านั้น (AND ไม่รับประกันลำดับการคำนวณ)
        case when p_recipe ->> 'time_minutes' ~ '^\d{1,4}$' then
          case when (p_recipe ->> 'time_minutes')::integer <= 1440
               then (p_recipe ->> 'time_minutes')::integer end
        end,
        public.parse_minutes(p_recipe ->> 'time')),
      nullif(btrim(p_recipe ->> 'servings'), ''),
      v_steps,
      v_ai_steps,
      v_calories,
      v_protein,
      v_diet_tags,
      nullif(btrim(p_recipe ->> 'image_url'), ''),
      nullif(btrim(p_image_hash), ''),
      p_source,
      v_signature,
      p_is_public,
      p_created_by)
    -- มีคนบันทึกสูตรเดียวกันพร้อมกันพอดี -> unique index กันไว้ แล้วไปใช้แถวของเขาแทน
    on conflict do nothing
    returning id into v_recipe_id;

    if v_recipe_id is not null then
      insert into public.recipe_ingredients (
        recipe_id, sort_order, ingredient_id, display_name, quantity, unit, is_main)
      select v_recipe_id,
             (t.ord - 1)::smallint,
             t.iid,
             left(btrim(t.e ->> 'name'), 100),
             case
               when jsonb_typeof(t.e -> 'use_quantity') = 'number' then
                 case when (t.e ->> 'use_quantity')::numeric >= 0
                      then (t.e ->> 'use_quantity')::numeric end
               when t.e ? 'use_quantity' then private.parse_qty(t.e ->> 'use_quantity')
               else private.parse_qty(t.e ->> 'quantity')
             end,
             coalesce(
               nullif(btrim(t.e ->> 'unit'), ''),
               case when not (t.e ? 'use_quantity') then private.parse_unit(t.e ->> 'quantity') end),
             exists (select 1 from jsonb_array_elements_text(v_used) u
                      where public.resolve_ingredient_id(u) = t.iid)
        from (select x.e, x.ord, public.resolve_ingredient_id(x.e ->> 'name') as iid
                from jsonb_array_elements(v_items) with ordinality as x(e, ord)) t
       where t.iid is not null;

      return v_recipe_id;
    end if;

    select r.id into v_recipe_id
      from public.recipes r
     where r.is_public
       and ((r.name_key = v_name_key and r.ingredient_signature = v_signature)
            or (p_image_hash is not null and r.image_hash = p_image_hash))
     limit 1;
  end if;

  -- ใช้สูตรเดิม -> นับว่ามีคนใช้เพิ่ม (ใช้จัดอันดับผลค้นหา)
  update public.recipes set use_count = use_count + 1 where id = v_recipe_id;
  return v_recipe_id;
end;
$$;

-- =============================================================================
-- 6) Triggers
-- =============================================================================

drop trigger if exists recipes_set_updated_at on public.recipes;
create trigger recipes_set_updated_at
  before update on public.recipes
  for each row execute function private.set_updated_at();

drop trigger if exists user_saved_recipes_set_updated_at on public.user_saved_recipes;
create trigger user_saved_recipes_set_updated_at
  before update on public.user_saved_recipes
  for each row execute function private.set_updated_at();

-- recipes.ingredient_ids ให้ตรงกับ recipe_ingredients เสมอ
create or replace function private.refresh_recipe_ingredient_ids()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  for v_id in
    select distinct x
      from (values (case when tg_op <> 'INSERT' then old.recipe_id end),
                   (case when tg_op <> 'DELETE' then new.recipe_id end)) as t(x)
     where x is not null
  loop
    update public.recipes r
       set ingredient_ids = coalesce(
             (select array_agg(distinct ri.ingredient_id order by ri.ingredient_id)
                from public.recipe_ingredients ri
               where ri.recipe_id = v_id),
             '{}')
     where r.id = v_id;
  end loop;
  return null;
end;
$$;

drop trigger if exists recipe_ingredients_refresh_ids on public.recipe_ingredients;
create trigger recipe_ingredients_refresh_ids
  after insert or update or delete on public.recipe_ingredients
  for each row execute function private.refresh_recipe_ingredient_ids();

-- fridge_items.ingredient_id เติมให้อัตโนมัติจากชื่อ (แอปเดิมไม่ต้องแก้)
-- เทียบแบบตรงชื่อ/alias เท่านั้น ไม่เดา เพื่อไม่ให้ผูกผิดวัตถุดิบ
create or replace function private.fridge_items_resolve_ingredient()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.ingredient_id is null then
      new.ingredient_id := public.resolve_ingredient_id(new.name);
    end if;
  elsif new.name is distinct from old.name then
    new.ingredient_id := public.resolve_ingredient_id(new.name);
  end if;
  return new;
end;
$$;

drop trigger if exists fridge_items_resolve_ingredient on public.fridge_items;
create trigger fridge_items_resolve_ingredient
  before insert or update on public.fridge_items
  for each row execute function private.fridge_items_resolve_ingredient();

-- =============================================================================
-- 7) RPC ที่ Flutter เรียก (supabase.rpc(...))
-- =============================================================================

-- 7.1 บันทึกสูตรเข้าตารางกลาง คืน recipe_id
--     p_bookmark = true  -> เพิ่มเข้า user_saved_recipes ด้วย (ผู้ใช้กด "บันทึก")
--     p_bookmark = false -> เก็บเข้า cache อย่างเดียว (เช่น เมนูที่ AI เสนอแต่ยังไม่ได้กดบันทึก)
create or replace function public.save_recipe(
  p_recipe      jsonb,
  p_source      text,
  p_image_hash  text default null,
  p_is_public   boolean default true,
  p_bookmark    boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_recipe_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- กันสแปมตารางกลาง: สร้างสูตรใหม่ได้ไม่เกิน 300 สูตรต่อผู้ใช้ต่อวัน
  if (select count(*) from public.recipes r
       where r.created_by = v_uid and r.created_at > now() - interval '1 day') >= 300 then
    raise exception 'daily recipe limit reached' using errcode = '54000';
  end if;

  v_recipe_id := private.upsert_global_recipe(p_recipe, p_source, v_uid, p_image_hash, p_is_public);

  if p_bookmark then
    insert into public.user_saved_recipes (user_id, recipe_id)
    values (v_uid, v_recipe_id)
    on conflict (user_id, recipe_id) do nothing;
  end if;

  return v_recipe_id;
end;
$$;

-- 7.2 หา cache จากรูปที่เคยสแกน (sha256 ของไฟล์รูป)
create or replace function public.find_recipe_by_image_hash(p_image_hash text)
returns table (recipe_id uuid, recipe jsonb)
language sql
stable
set search_path = ''
as $$
  select r.id, public.recipe_to_app_json(r.id)
    from public.recipes r
   where p_image_hash is not null and r.image_hash = btrim(p_image_hash)
   order by r.is_public desc, r.use_count desc
   limit 1;
$$;

-- 7.3 ค้นหาตามชื่อสูตร (exact -> มีคำค้นอยู่ในชื่อ -> ชื่อสะกดคล้าย)
--     score: 1 = ตรงเป๊ะ, >= 0.8 = ชื่อมีคำค้นอยู่, ที่เหลือ = trigram similarity
create or replace function public.search_recipes_by_name(
  p_query           text,
  p_limit           integer default 5,
  p_min_similarity  real default 0.35
)
returns table (recipe_id uuid, recipe_name text, score real, recipe jsonb)
language sql
stable
set search_path = public, extensions
as $$
  with q as (select public.normalize_text(p_query) as k)
  select r.id,
         r.name,
         (case
            when r.name_key = q.k then 1.0
            when r.name_key like '%' || q.k || '%' then greatest(0.8, similarity(r.name_key, q.k))
            else similarity(r.name_key, q.k)
          end)::real as score,
         public.recipe_to_app_json(r.id)
    from public.recipes r
   cross join q
   where q.k is not null
     and (r.name_key = q.k
          or r.name_key like '%' || q.k || '%'
          or (r.name_key % q.k and similarity(r.name_key, q.k) >= p_min_similarity))
   order by score desc, r.use_count desc
   limit least(greatest(coalesce(p_limit, 5), 1), 50);
$$;

-- 7.4 ค้นหาจาก "วัตถุดิบที่มีในตู้เย็น" (ใช้ก่อนเรียก Gemini ในหน้าสร้างเมนู / แพลนอาหาร)
--     เทียบชื่อ: ตรงกัน, ชื่อเรียกอื่น (alias), ชื่อหนึ่งอยู่ในอีกชื่อ (หมู ~ หมูสับ), สะกดคล้ายมาก
--     ไม่นับของพื้นฐาน (is_staple) เป็นของที่ขาด
create or replace function public.match_recipes_by_ingredients(
  p_ingredients       text[],
  p_max_missing       integer default 2,
  p_min_match_ratio   numeric default 0.5,
  p_max_time_minutes  integer default null,
  p_max_calories      numeric default null,
  p_diet_tags         text[] default null,
  p_limit             integer default 10
)
returns table (
  recipe_id            uuid,
  recipe_name          text,
  matched_count        integer,
  required_count       integer,
  missing_ingredients  text[],
  recipe               jsonb
)
language sql
stable
set search_path = public, extensions
as $$
  with inv as (
    select distinct public.normalize_text(x) as k
      from unnest(p_ingredients) as x
     where public.normalize_text(x) is not null
  ),
  have as (
    select i.id
      from public.ingredients i
      join inv
        on i.name_key = inv.k
        or (char_length(i.name_key) >= 2 and char_length(inv.k) >= 2
            and (inv.k like '%' || i.name_key || '%' or i.name_key like '%' || inv.k || '%'))
        -- สะกดคล้าย: เกณฑ์สูงกว่า default (0.3) เพื่อไม่ให้ "หมูสับ" ไปตรงกับ "หมูยอ"
        or (i.name_key % inv.k and similarity(i.name_key, inv.k) >= 0.6)
    union
    select a.ingredient_id
      from public.ingredient_aliases a
      join inv on a.alias_key = inv.k
  ),
  diet as (
    select array_agg(distinct lower(btrim(x))) as tags
      from unnest(p_diet_tags) as x
     where btrim(x) <> ''
  ),
  candidates as (
    select r.id
      from public.recipes r
     where r.ingredient_ids && (select coalesce(array_agg(h.id), '{}'::bigint[]) from have h)
       and (p_max_time_minutes is null or r.time_minutes is null or r.time_minutes <= p_max_time_minutes)
       and (p_max_calories is null or r.calories_per_serving is null or r.calories_per_serving <= p_max_calories)
       and ((select d.tags from diet d) is null or r.diet_tags @> (select d.tags from diet d))
  ),
  stats as (
    select ri.recipe_id,
           count(distinct ri.ingredient_id) filter (where not i.is_staple) as required_count,
           count(distinct ri.ingredient_id) filter (where not i.is_staple and h.id is not null) as matched_count,
           array_agg(distinct ri.display_name) filter (where not i.is_staple and h.id is null) as missing
      from candidates c
      join public.recipe_ingredients ri on ri.recipe_id = c.id
      join public.ingredients i on i.id = ri.ingredient_id
      left join have h on h.id = ri.ingredient_id
     group by ri.recipe_id
  )
  select r.id,
         r.name,
         s.matched_count::integer,
         s.required_count::integer,
         coalesce(s.missing, '{}'),
         public.recipe_to_app_json(r.id)
    from stats s
    join public.recipes r on r.id = s.recipe_id
   where s.required_count > 0
     and s.matched_count > 0
     and s.required_count - s.matched_count <= coalesce(p_max_missing, 2)
     and s.matched_count::numeric / s.required_count >= coalesce(p_min_match_ratio, 0.5)
   order by (s.required_count - s.matched_count), s.matched_count desc, r.use_count desc
   limit least(greatest(coalesce(p_limit, 10), 1), 50);
$$;

-- 7.5 สูตรที่ผู้ใช้บันทึกไว้ (รวมส่วนที่แก้เองทับสูตรกลางแล้ว) — แทน select จาก scanned_recipes
create or replace function public.my_saved_recipes()
returns table (saved_id uuid, recipe_id uuid, is_favorite boolean, saved_at timestamptz, recipe jsonb)
language sql
stable
set search_path = ''
as $$
  select usr.id,
         usr.recipe_id,
         usr.is_favorite,
         usr.created_at,
         public.recipe_to_app_json(usr.recipe_id) || coalesce(usr.overrides, '{}'::jsonb)
    from public.user_saved_recipes usr
   where usr.user_id = auth.uid()
   order by usr.created_at desc;
$$;

-- 7.6 สรุปผลประหยัด token ของผู้ใช้ (ใช้ทำหน้าสถิติ / ตรวจว่า cache ได้ผลไหม)
create or replace function public.my_ai_usage(p_days integer default 30)
returns table (event_type text, cache_hits bigint, gemini_calls bigint, prompt_tokens bigint, output_tokens bigint)
language sql
stable
set search_path = ''
as $$
  select l.event_type,
         count(*) filter (where l.result = 'cache_hit'),
         count(*) filter (where l.result <> 'cache_hit'),
         coalesce(sum(l.prompt_tokens), 0),
         coalesce(sum(l.output_tokens), 0)
    from public.ai_request_logs l
   where l.user_id = auth.uid()
     and l.created_at > now() - make_interval(days => least(greatest(coalesce(p_days, 30), 1), 365))
   group by l.event_type
   order by l.event_type;
$$;

-- =============================================================================
-- 8) สิทธิ์การเรียกฟังก์ชัน
-- =============================================================================
revoke all on function private.upsert_global_recipe(jsonb, text, uuid, text, boolean)
  from public, anon, authenticated;

revoke all on function public.save_recipe(jsonb, text, text, boolean, boolean) from public, anon;
grant execute on function public.save_recipe(jsonb, text, text, boolean, boolean) to authenticated;

revoke all on function public.my_saved_recipes() from public, anon;
grant execute on function public.my_saved_recipes() to authenticated;
revoke all on function public.my_ai_usage(integer) from public, anon;
grant execute on function public.my_ai_usage(integer) to authenticated;

grant execute on function public.find_recipe_by_image_hash(text) to anon, authenticated;
grant execute on function public.search_recipes_by_name(text, integer, real) to anon, authenticated;
grant execute on function public.match_recipes_by_ingredients(text[], integer, numeric, integer, numeric, text[], integer)
  to anon, authenticated;
grant execute on function public.recipe_to_app_json(uuid) to anon, authenticated;
grant execute on function public.resolve_ingredient_id(text) to anon, authenticated;

-- =============================================================================
-- 9) Row Level Security (ตารางใหม่เท่านั้น — ไม่แตะ policy ของตารางเดิม)
-- =============================================================================
alter table public.ingredients        enable row level security;
alter table public.ingredient_aliases enable row level security;
alter table public.recipes            enable row level security;
alter table public.recipe_ingredients enable row level security;
alter table public.user_saved_recipes enable row level security;
alter table public.ai_request_logs    enable row level security;

-- ---- ตารางกลาง: ทุกคนอ่านได้ (Public READ) / เขียนผ่าน save_recipe() เท่านั้น
revoke insert, update, delete, truncate
  on public.ingredients, public.ingredient_aliases, public.recipes, public.recipe_ingredients
  from anon, authenticated;
grant select
  on public.ingredients, public.ingredient_aliases, public.recipes, public.recipe_ingredients
  to anon, authenticated;

drop policy if exists "ingredients: public read" on public.ingredients;
create policy "ingredients: public read"
  on public.ingredients for select
  to anon, authenticated
  using (true);

drop policy if exists "ingredient_aliases: public read" on public.ingredient_aliases;
create policy "ingredient_aliases: public read"
  on public.ingredient_aliases for select
  to anon, authenticated
  using (true);

drop policy if exists "recipes: public read" on public.recipes;
create policy "recipes: public read"
  on public.recipes for select
  to anon, authenticated
  using (is_public or created_by = (select auth.uid()));

-- ส่วนผสมอ่านได้เมื่ออ่านสูตรนั้นได้ (subquery นี้ผ่าน RLS ของ recipes อีกชั้น)
drop policy if exists "recipe_ingredients: read with recipe" on public.recipe_ingredients;
create policy "recipe_ingredients: read with recipe"
  on public.recipe_ingredients for select
  to anon, authenticated
  using (exists (select 1 from public.recipes r where r.id = recipe_id));

-- ---- user_saved_recipes: เจ้าของ account เท่านั้น (CRUD ตาม auth.uid())
revoke all on public.user_saved_recipes from anon;
grant select, insert, update, delete on public.user_saved_recipes to authenticated;

drop policy if exists "user_saved_recipes: owner select" on public.user_saved_recipes;
create policy "user_saved_recipes: owner select"
  on public.user_saved_recipes for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "user_saved_recipes: owner insert" on public.user_saved_recipes;
create policy "user_saved_recipes: owner insert"
  on public.user_saved_recipes for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.recipes r where r.id = recipe_id)
  );

drop policy if exists "user_saved_recipes: owner update" on public.user_saved_recipes;
create policy "user_saved_recipes: owner update"
  on public.user_saved_recipes for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.recipes r where r.id = recipe_id)
  );

drop policy if exists "user_saved_recipes: owner delete" on public.user_saved_recipes;
create policy "user_saved_recipes: owner delete"
  on public.user_saved_recipes for delete
  to authenticated
  using (user_id = (select auth.uid()));

-- ---- ai_request_logs: เขียน/อ่านได้เฉพาะ log ของตัวเอง (แก้ / ลบ log ไม่ได้)
revoke all on public.ai_request_logs from anon;
revoke update, delete, truncate on public.ai_request_logs from authenticated;
grant select, insert on public.ai_request_logs to authenticated;

drop policy if exists "ai_request_logs: owner select" on public.ai_request_logs;
create policy "ai_request_logs: owner select"
  on public.ai_request_logs for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "ai_request_logs: owner insert" on public.ai_request_logs;
create policy "ai_request_logs: owner insert"
  on public.ai_request_logs for insert
  to authenticated
  with check (user_id = (select auth.uid()));

-- =============================================================================
-- 10) ข้อมูลตั้งต้น: ของพื้นฐาน + ชื่อเรียกอื่น (เพิ่มเติมภายหลังได้)
-- =============================================================================
insert into public.ingredients (name, is_staple) values
  ('เกลือ', true), ('น้ำ', true), ('น้ำปลา', true), ('น้ำตาล', true),
  ('น้ำตาลทราย', true), ('น้ำมัน', true), ('น้ำมันพืช', true), ('พริกไทย', true),
  ('ซีอิ๊วขาว', true), ('ซอสปรุงรส', true), ('ซอสหอยนางรม', true)
on conflict (name_key) do update set is_staple = true;

insert into public.ingredients (name) values
  ('ไข่ไก่'), ('หมูสับ'), ('อกไก่'), ('กระเทียม'), ('ต้นหอม')
on conflict (name_key) do nothing;

insert into public.ingredient_aliases (alias, ingredient_id)
select a.alias, i.id
  from (values
          ('ไข่', 'ไข่ไก่'),
          ('หมูบด', 'หมูสับ'),
          ('เนื้ออกไก่', 'อกไก่'),
          ('อกไก่ลอกหนัง', 'อกไก่'),
          ('กระเทียมไทย', 'กระเทียม'),
          ('หอมต้น', 'ต้นหอม')
       ) as a(alias, canonical)
  join public.ingredients i on i.name_key = public.normalize_text(a.canonical)
on conflict (alias_key) do nothing;

-- =============================================================================
-- 11) MIGRATE ข้อมูลเดิม (ไม่ลบ / ไม่แก้ข้อมูลเดิม นอกจากเติมคอลัมน์ใหม่)
--     ทำเป็นฟังก์ชันเพื่อเรียกซ้ำได้ในขั้นที่ 2 (เก็บแถวที่แอปเวอร์ชันเก่าเขียนเพิ่มระหว่างนั้น)
--     แต่ละรอบทำเฉพาะแถวที่ยังไม่ได้ย้าย
--     สูตรที่ย้ายมาตั้งเป็น is_public = false เพราะผู้ใช้บันทึกไว้เป็นของส่วนตัว
--     (ถ้าต้องการให้ช่วยลด token ด้วย ดูคำสั่ง UPDATE ท้ายไฟล์)
-- =============================================================================
create or replace function private.migrate_legacy_data()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec         record;
  v_recipe_id uuid;
  v_sr_moved  integer := 0;
  v_sr_skip   integer := 0;
  v_wm_linked integer := 0;
  v_wm_skip   integer := 0;
begin
  -- weekly_meals.user_id จาก meal_plans
  update public.weekly_meals wm
     set user_id = mp.user_id
    from public.meal_plans mp
   where mp.id = wm.plan_id
     and wm.user_id is null;

  -- fridge_items.ingredient_id (ชื่อตรง / alias เท่านั้น)
  update public.fridge_items fi
     set ingredient_id = public.resolve_ingredient_id(fi.name)
   where fi.ingredient_id is null
     and public.resolve_ingredient_id(fi.name) is not null;

  -- scanned_recipes -> recipes + user_saved_recipes
  for rec in
    select s.id as sid, to_jsonb(s) as j
      from public.scanned_recipes s
     where s.global_recipe_id is null
  loop
    begin
      v_recipe_id := private.upsert_global_recipe(
        rec.j, 'scanned', (rec.j ->> 'user_id')::uuid, null, false);

      insert into public.user_saved_recipes (user_id, recipe_id, created_at)
      values ((rec.j ->> 'user_id')::uuid,
              v_recipe_id,
              coalesce((rec.j ->> 'created_at')::timestamptz, now()))
      on conflict (user_id, recipe_id) do nothing;

      update public.scanned_recipes set global_recipe_id = v_recipe_id where id = rec.sid;
      v_sr_moved := v_sr_moved + 1;
    exception when others then
      v_sr_skip := v_sr_skip + 1;
      raise notice 'skip scanned_recipes id=%: %', rec.sid, sqlerrm;
    end;
  end loop;

  -- weekly_meals (เมนูที่ AI วางแผนไว้) -> recipes แล้วผูก weekly_meals.recipe_id
  for rec in
    select w.id as wid, to_jsonb(w) as j, mp.user_id as uid
      from public.weekly_meals w
      join public.meal_plans mp on mp.id = w.plan_id
     where w.recipe_id is null
  loop
    begin
      v_recipe_id := private.upsert_global_recipe(
        jsonb_build_object(
          'food_name', rec.j -> 'food_name',
          'ingredients', rec.j -> 'ingredients',
          'steps', rec.j -> 'steps',
          'calories', rec.j -> 'calories',
          'protein', rec.j -> 'protein'),
        'ai_generated', rec.uid::uuid, null, false);

      update public.weekly_meals set recipe_id = v_recipe_id where id = rec.wid;
      v_wm_linked := v_wm_linked + 1;
    exception when others then
      v_wm_skip := v_wm_skip + 1;
      raise notice 'skip weekly_meals id=%: %', rec.wid, sqlerrm;
    end;
  end loop;

  return format('scanned_recipes: moved %s, skipped %s | weekly_meals: linked %s, skipped %s',
                v_sr_moved, v_sr_skip, v_wm_linked, v_wm_skip);
end;
$$;

revoke all on function private.migrate_legacy_data() from public, anon, authenticated;

-- ผลลัพธ์แสดงในแท็บ Results (จำนวนที่ย้ายได้ / ข้าม) — แถวที่ข้ามดูเหตุผลได้ในแท็บ Messages
select private.migrate_legacy_data() as migrate_result;

commit;

-- =============================================================================
-- (ไม่บังคับ) เปิดให้สูตรที่ AI สร้างไว้ในแพลนอาหารเดิมช่วยลด token ให้ทุกคน
-- เนื้อหาสร้างโดย AI จึงไม่มีปัญหาลิขสิทธิ์จากตำรา — รันแยกเมื่อพร้อม:
--
--   update public.recipes set is_public = true
--    where id in (
--      -- สูตรซ้ำกันหลายคน (ชื่อ + วัตถุดิบเดียวกัน) เปิดเป็นสาธารณะแค่แถวเดียว
--      select distinct on (r.name_key, r.ingredient_signature) r.id
--        from public.recipes r
--       where r.source = 'ai_generated' and not r.is_public
--         and not exists (select 1 from public.recipes p
--                          where p.is_public and p.name_key = r.name_key
--                            and p.ingredient_signature = r.ingredient_signature)
--       order by r.name_key, r.ingredient_signature, r.use_count desc);
-- =============================================================================
