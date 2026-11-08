-- =====================================================================
-- SmartFridge.AI — ปรับปรุงฐานข้อมูล (7 พ.ย. 2026)
-- รันใน Supabase Dashboard → SQL Editor ทีละขั้น ตามลำดับ
--
-- ขั้น 0  ตรวจข้อมูลก่อน (อ่านอย่างเดียว)
-- ขั้น 1  ปลอดภัย ไม่ต้องแก้แอป: index, CHECK constraint, weekly_meals.user_id
-- ขั้น 2  ปลอดภัย ไม่ต้องแก้แอป: ให้ profiles ตรงกับ user_metadata อัตโนมัติ
-- ขั้น 3  เตรียมไว้ให้แอป: meal_plans.is_favorite (แอปยังใช้ user_metadata อยู่)
-- ขั้น 4  ไม่บังคับ: ลบ log AI เก่าอัตโนมัติ (ต้องเปิด pg_cron)
-- ขั้น 5  ไม่บังคับ: ตารางประวัติการใช้วัตถุดิบ (ต้องแก้แอปให้เขียนลงตาราง)
--
-- ก่อนเริ่ม: สำรองข้อมูลก่อน (Database → Backups หรือ pg_dump)
-- =====================================================================


-- =====================================================================
-- ขั้น 0: ตรวจข้อมูลก่อน — ทุกคอลัมน์ควรเป็น 0
-- ถ้าไม่เป็น 0 ให้ดูแถวที่ผิดด้วย query ด้านล่าง แล้วแก้ก่อนทำขั้น 1.3
-- =====================================================================
select
  count(*) filter (where storage not in ('fridge', 'freezer'))                    as bad_storage,
  count(*) filter (where category not in
    ('ผัก', 'ผลไม้', 'เนื้อสัตว์', 'แป้ง/ข้าว', 'นม/เครื่องดื่ม', 'ขนม', 'อื่นๆ'))      as bad_category,
  count(*) filter (where quantity < 0 or max_quantity < 0)                        as negative_qty,
  count(*) filter (where fridge_days < 0 or freezer_days < 0)                     as negative_days,
  count(*) filter (where use_per_cook <= 0)                                       as bad_use_per_cook
from public.fridge_items;

select
  count(*) filter (where meals_per_day is not null and meals_per_day <= 0)        as bad_meals_per_day,
  count(*) filter (where target_calories is not null and target_calories <= 0)    as bad_calories,
  count(*) filter (where target_protein is not null and target_protein < 0)       as bad_protein
from public.meal_plans;

-- มื้อที่ไม่มี user_id และหาแผนแม่ไม่เจอ (ต้องเป็น 0 ก่อนทำขั้น 1.4)
select count(*) as orphan_meals
from public.weekly_meals w
left join public.meal_plans p on p.id = w.plan_id
where w.user_id is null and p.id is null;

-- ตาราง legacy ยังอยู่ไหม (NULL = ไม่มีแล้ว ลบออกจากเอกสารได้)
select to_regclass('public.scanned_recipes_legacy') as legacy_table,
       to_regclass('public.scanned_recipes')        as old_name;

-- ดูค่า category ที่ไม่อยู่ในรายการ (ถ้า bad_category > 0)
-- select category, count(*) from public.fridge_items group by 1 order by 2 desc;


-- =====================================================================
-- ขั้น 1.1: Index ที่ยังไม่มี (หน้าจอใช้กรอง/เรียงด้วยคอลัมน์เหล่านี้ และ RLS กรองด้วย user_id)
-- =====================================================================
create index if not exists fridge_items_user_expiry_idx
  on public.fridge_items (user_id, expiry_date);

create index if not exists meal_plans_user_created_idx
  on public.meal_plans (user_id, created_at desc);

create index if not exists weekly_meals_plan_idx
  on public.weekly_meals (plan_id);

create index if not exists ai_request_logs_user_created_idx
  on public.ai_request_logs (user_id, created_at desc);


-- =====================================================================
-- ขั้น 1.2: CHECK constraint แบบ NOT VALID
-- ตรวจเฉพาะข้อมูลที่เพิ่ม/แก้ใหม่ ข้อมูลเดิมที่ผิดจะไม่ทำให้คำสั่งล้ม
-- ค่า NULL ผ่าน CHECK เสมอ จึงไม่กระทบแถวที่ยังไม่มีค่า
-- =====================================================================
do $$
begin
  alter table public.fridge_items add constraint fridge_items_storage_chk
    check (storage in ('fridge', 'freezer')) not valid;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.fridge_items add constraint fridge_items_category_chk
    check (category in ('ผัก', 'ผลไม้', 'เนื้อสัตว์', 'แป้ง/ข้าว', 'นม/เครื่องดื่ม', 'ขนม', 'อื่นๆ')) not valid;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.fridge_items add constraint fridge_items_quantity_chk
    check (quantity >= 0 and max_quantity >= 0) not valid;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.fridge_items add constraint fridge_items_days_chk
    check (fridge_days >= 0 and freezer_days >= 0) not valid;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.meal_plans add constraint meal_plans_targets_chk
    check (meals_per_day > 0 and target_calories > 0 and target_protein >= 0) not valid;
exception when duplicate_object then null;
end $$;


-- =====================================================================
-- ขั้น 1.3: ยืนยันกับข้อมูลเดิม — รันเมื่อขั้น 0 เป็น 0 หมดแล้วเท่านั้น
-- ถ้าล้ม แปลว่ายังมีแถวที่ผิด constraint ยังทำงานกับข้อมูลใหม่ตามปกติ
-- =====================================================================
alter table public.fridge_items validate constraint fridge_items_storage_chk;
alter table public.fridge_items validate constraint fridge_items_category_chk;
alter table public.fridge_items validate constraint fridge_items_quantity_chk;
alter table public.fridge_items validate constraint fridge_items_days_chk;
alter table public.meal_plans   validate constraint meal_plans_targets_chk;


-- =====================================================================
-- ขั้น 1.4: weekly_meals.user_id ห้ามว่าง (RLS ใช้คอลัมน์นี้)
-- แอปไม่ได้ส่ง user_id เอง ใช้ default auth.uid() อยู่แล้ว จึงไม่ต้องแก้แอป
-- =====================================================================
update public.weekly_meals w
set user_id = p.user_id
from public.meal_plans p
where w.plan_id = p.id
  and w.user_id is null;

alter table public.weekly_meals alter column user_id set not null;


-- =====================================================================
-- ขั้น 2: ให้ profiles ตรงกับข้อมูลที่แอปเก็บจริง (auth.users.user_metadata)
-- ไม่ต้องแก้แอป: ทุกครั้งที่สมัคร/แก้โปรไฟล์ trigger จะคัดลอกค่าไปที่ profiles
-- ถ้า trigger มีปัญหา จะแค่ขึ้น warning ไม่ทำให้สมัครสมาชิกล้ม
-- =====================================================================
alter table public.profiles add column if not exists notify_days integer;

create or replace function private.sync_profile_from_auth()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, first_name, last_name, phone, notify_days)
  values (
    new.id,
    new.raw_user_meta_data ->> 'first_name',
    new.raw_user_meta_data ->> 'last_name',
    new.raw_user_meta_data ->> 'phone',
    nullif(new.raw_user_meta_data ->> 'notify_days', '')::integer
  )
  on conflict (id) do update
    set first_name  = excluded.first_name,
        last_name   = excluded.last_name,
        phone       = excluded.phone,
        notify_days = excluded.notify_days;
  return new;
exception when others then
  raise warning 'sync_profile_from_auth failed for %: %', new.id, sqlerrm;
  return new;
end;
$$;

drop trigger if exists sync_profile_from_auth on auth.users;
create trigger sync_profile_from_auth
  after insert or update of raw_user_meta_data on auth.users
  for each row execute function private.sync_profile_from_auth();

-- คัดลอกข้อมูลผู้ใช้เดิมทั้งหมดครั้งเดียว (ถ้าล้มเพราะ on conflict แปลว่า profiles.id ไม่ใช่ PK — แจ้งก่อนทำต่อ)
insert into public.profiles (id, first_name, last_name, phone, notify_days)
select id,
       raw_user_meta_data ->> 'first_name',
       raw_user_meta_data ->> 'last_name',
       raw_user_meta_data ->> 'phone',
       nullif(raw_user_meta_data ->> 'notify_days', '')::integer
from auth.users
on conflict (id) do update
  set first_name  = excluded.first_name,
      last_name   = excluded.last_name,
      phone       = excluded.phone,
      notify_days = excluded.notify_days;


-- =====================================================================
-- ขั้น 3: แพลนโปรดเป็นคอลัมน์ของ meal_plans (เตรียมไว้ — แอปยังอ่านจาก user_metadata)
-- รันได้เลย ไม่กระทบแอป แต่ต้องแก้ my_plan_screen.dart ให้ใช้คอลัมน์นี้ ถึงจะได้ประโยชน์
-- =====================================================================
alter table public.meal_plans
  add column if not exists is_favorite boolean not null default false;

update public.meal_plans p
set is_favorite = true
from auth.users u
where p.user_id = u.id
  and jsonb_typeof(u.raw_user_meta_data -> 'favorite_plan_ids') = 'array'
  and (u.raw_user_meta_data -> 'favorite_plan_ids') ? p.id::text;


-- =====================================================================
-- ขั้น 4 (ไม่บังคับ): ลบ ai_request_logs ที่เก่ากว่า 90 วัน ทุกวันตี 3 (UTC)
-- ต้องเปิด extension pg_cron ก่อน: Database → Extensions → pg_cron
-- =====================================================================
-- select cron.schedule(
--   'purge-ai-request-logs',
--   '0 3 * * *',
--   $$delete from public.ai_request_logs where created_at < now() - interval '90 days'$$
-- );


-- =====================================================================
-- ขั้น 5 (ไม่บังคับ): ประวัติการใช้วัตถุดิบ — ตอนนี้ของที่ใช้หมดถูกลบแถวทิ้ง
-- (fridge_stock.dart) จึงไม่รู้ว่ากินหมดหรือทิ้งเพราะเสีย ตารางนี้ต้องแก้แอปให้เขียนลงด้วย
-- item_id ไม่ทำ FK เพราะแถวใน fridge_items ถูกลบเมื่อใช้หมด
-- ถ้า fridge_items.item_id เป็น uuid ให้เปลี่ยนชนิดของ item_id ด้านล่างเป็น uuid
-- =====================================================================
-- create table if not exists public.fridge_item_events (
--   id          bigint generated always as identity primary key,
--   user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
--   item_id     bigint,
--   ingredient_id bigint references public.ingredients (id) on delete set null,
--   item_name   text not null,
--   event       text not null check (event in ('added', 'used', 'moved', 'discarded', 'expired')),
--   quantity    numeric check (quantity >= 0),
--   unit        text,
--   storage     text check (storage in ('fridge', 'freezer')),
--   created_at  timestamptz not null default now()
-- );
-- create index if not exists fridge_item_events_user_created_idx
--   on public.fridge_item_events (user_id, created_at desc);
-- alter table public.fridge_item_events enable row level security;
-- create policy "own events read"   on public.fridge_item_events for select using (user_id = auth.uid());
-- create policy "own events insert" on public.fridge_item_events for insert with check (user_id = auth.uid());
-- revoke truncate on public.fridge_item_events from anon, authenticated;
