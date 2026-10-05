-- =====================================================================
--  ฐานข้อมูลแดชบอร์ดแผนปฏิบัติการ กยท. (Supabase)
--  วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run (รันซ้ำได้)
--
--  เก็บข้อมูล 1 แถวต่อ 1 ชีตของ Google Sheet:
--    headers = หัวคอลัมน์ตามลำดับในชีต   ["PRJ_Code", "ชื่อโครงการ", ...]
--    rows    = ข้อมูลทุกแถวตามลำดับในชีต  [["010101", "..."], ...]
--  ค่าเป็นข้อความตามที่แสดงในชีต (เหมือนการ export CSV) แดชบอร์ดจึงใช้ตัวแปลงข้อมูลเดิมได้ทั้งหมด
--  และไม่ต้องแก้ตารางเมื่อเพิ่ม/เปลี่ยนคอลัมน์ในชีต
--
--  สิทธิ์: หน้าเว็บ (anon key) อ่านได้อย่างเดียว
--          Apps Script เขียนด้วย service_role / secret key (ข้าม RLS)
-- =====================================================================

create table if not exists public.sheet_snapshots (
  sheet_name text primary key,
  headers    jsonb not null default '[]'::jsonb,
  rows       jsonb not null default '[]'::jsonb,
  row_count  integer not null default 0,
  synced_at  timestamptz not null default now(),
  synced_by  text
);

comment on table public.sheet_snapshots is
  'สำเนาข้อมูลจาก Google Sheet "Data ACP69" ส่งขึ้นโดย Apps Script (1 แถว = 1 ชีต)';

alter table public.sheet_snapshots enable row level security;

drop policy if exists "อ่านได้ทุกคน" on public.sheet_snapshots;
create policy "อ่านได้ทุกคน"
  on public.sheet_snapshots
  for select
  to anon, authenticated
  using (true);

-- กันไว้อีกชั้น: anon / authenticated เขียน แก้ หรือลบไม่ได้ แม้จะมีคนเพิ่ม policy ผิดพลาดในภายหลัง
revoke insert, update, delete, truncate on public.sheet_snapshots from anon, authenticated;
grant select on public.sheet_snapshots to anon, authenticated;
-- Apps Script ใช้ service_role / secret key เขียนข้อมูล (โปรเจกต์ Supabase รุ่นใหม่ไม่ให้สิทธิ์นี้อัตโนมัติ)
grant select, insert, update, delete on public.sheet_snapshots to service_role;

-- =====================================================================
--  นับผู้เข้าชมแดชบอร์ด
--  หน้าเว็บเรียก rpc/log_page_view หลังโหลดเสร็จ (anon key)
--  - anon อ่าน/แก้ตาราง page_views ตรงๆ ไม่ได้ ทำได้แค่ "บันทึกการเข้าชม" ผ่านฟังก์ชันนี้
--  - visitor_id เป็นรหัสสุ่มที่เก็บใน localStorage ของเครื่องผู้ชม ไม่ใช่ข้อมูลส่วนบุคคล
--  - เครื่องเดิมเปิดซ้ำภายใน 30 นาทีนับเป็นครั้งเดียว
--  ดูสถิติ: Table Editor → page_view_monthly / page_view_daily หรือ SQL ด้านล่างสุด
-- =====================================================================

create table if not exists public.page_views (
  id         bigint generated always as identity primary key,
  viewed_at  timestamptz not null default now(),
  visitor_id uuid not null,
  source     text not null default 'web',   -- 'line' = เปิดจากแอป LINE
  is_mobile  boolean not null default false
);

create index if not exists page_views_viewed_at_idx on public.page_views (viewed_at);
create index if not exists page_views_visitor_idx   on public.page_views (visitor_id, viewed_at);

alter table public.page_views enable row level security;   -- ไม่มี policy = anon เข้าถึงตรงๆ ไม่ได้
revoke all on public.page_views from anon, authenticated;

create or replace function public.log_page_view(p_visitor uuid, p_source text default 'web', p_mobile boolean default false)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_visitor is null then
    return;
  end if;
  -- ไม่นับซ้ำถ้าเครื่องเดิมเปิดภายใน 30 นาที (กันกดรีเฟรชรัวๆ)
  if exists (
    select 1 from public.page_views
    where visitor_id = p_visitor and viewed_at > now() - interval '30 minutes'
  ) then
    return;
  end if;
  insert into public.page_views (visitor_id, source, is_mobile)
  values (p_visitor, left(coalesce(nullif(p_source, ''), 'web'), 20), coalesce(p_mobile, false));
end;
$$;

revoke all on function public.log_page_view(uuid, text, boolean) from public;
grant execute on function public.log_page_view(uuid, text, boolean) to anon, authenticated;

-- สถิติรายเดือน / รายวัน (เวลาไทย) — security_invoker ทำให้ anon อ่านไม่ได้ เปิดดูได้ใน Supabase เท่านั้น
create or replace view public.page_view_monthly with (security_invoker = on) as
select
  to_char(date_trunc('month', viewed_at at time zone 'Asia/Bangkok'), 'YYYY-MM') as month,
  count(*)                                  as views,
  count(distinct visitor_id)                as visitors,
  count(*) filter (where source = 'line')   as views_from_line,
  count(*) filter (where is_mobile)         as views_on_mobile
from public.page_views
group by 1
order by 1 desc;

create or replace view public.page_view_daily with (security_invoker = on) as
select
  (viewed_at at time zone 'Asia/Bangkok')::date as day,
  count(*)                                       as views,
  count(distinct visitor_id)                     as visitors,
  count(*) filter (where source = 'line')        as views_from_line
from public.page_views
group by 1
order by 1 desc;

revoke all on public.page_view_monthly, public.page_view_daily from anon, authenticated;
grant select on public.page_views, public.page_view_monthly, public.page_view_daily to service_role;

-- ตัวอย่าง: ผู้เข้าชมทั้งหมดตั้งแต่เริ่มเก็บ
--   select count(*) as views, count(distinct visitor_id) as visitors from public.page_views;
