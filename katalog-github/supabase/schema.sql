-- =====================================================================
--  Katalog Digital — skema database Supabase
--  Jalankan SELURUH isi file ini di Supabase: SQL Editor > New query > Run
--  (aman dijalankan ulang)
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- admin ----------
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------- tabel ----------
create table if not exists public.catalogs (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  slug            text not null unique,
  description     text not null default '',
  status          text not null default 'draft' check (status in ('draft','published')),
  cover_path      text,
  page_count      int  not null default 0,
  allow_download  boolean not null default true,
  download_perms  jsonb   not null default '{"full_pdf":true,"page":true,"zip":true}',
  published_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table if not exists public.catalog_pages (
  id           uuid primary key default gen_random_uuid(),
  catalog_id   uuid not null references public.catalogs(id) on delete cascade,
  kind         text not null default 'inner' check (kind in ('front','inner','back')),
  position     int  not null default 0,
  path_full    text,
  path_display text,
  path_thumb   text,
  source_name  text,
  size_bytes   bigint not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists catalog_pages_catalog_idx on public.catalog_pages(catalog_id);
create unique index if not exists one_front_per_catalog on public.catalog_pages(catalog_id) where kind = 'front';
create unique index if not exists one_back_per_catalog  on public.catalog_pages(catalog_id) where kind = 'back';

-- ---------- trigger otomatis ----------
create or replace function public.catalogs_before_write() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if new.status = 'published' and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    new.published_at := now();
  end if;
  return new;
end $$;
drop trigger if exists trg_catalogs_before on public.catalogs;
create trigger trg_catalogs_before before insert or update on public.catalogs
  for each row execute function public.catalogs_before_write();

create or replace function public.refresh_catalog_stats(cid uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  update public.catalogs c set
    page_count = (select count(*) from public.catalog_pages where catalog_id = cid),
    cover_path = (select path_display from public.catalog_pages where catalog_id = cid
                  order by (kind = 'front') desc, (kind = 'inner') desc, position asc limit 1)
  where c.id = cid;
end $$;

create or replace function public.pages_after_write() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op in ('INSERT','UPDATE') then perform public.refresh_catalog_stats(new.catalog_id); end if;
  if tg_op in ('DELETE') then perform public.refresh_catalog_stats(old.catalog_id); end if;
  return null;
end $$;
drop trigger if exists trg_pages_after on public.catalog_pages;
create trigger trg_pages_after after insert or update or delete on public.catalog_pages
  for each row execute function public.pages_after_write();

-- ---------- fungsi yang dipanggil aplikasi ----------
create or replace function public.reorder_pages(p_catalog uuid, p_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  update public.catalog_pages p set position = x.ord
  from unnest(p_ids) with ordinality as x(id, ord)
  where p.id = x.id and p.catalog_id = p_catalog and p.kind = 'inner';
end $$;

create or replace function public.set_page_kind(p_page uuid, p_kind text)
returns void language plpgsql security definer set search_path = public as $$
declare pg public.catalog_pages; cid uuid; old_id uuid;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_kind not in ('front','inner','back') then raise exception 'kind tidak valid'; end if;
  select * into pg from public.catalog_pages where id = p_page;
  if not found then raise exception 'page not found'; end if;
  cid := pg.catalog_id;
  if pg.kind = p_kind then return; end if;

  if p_kind <> 'inner' then
    select id into old_id from public.catalog_pages where catalog_id = cid and kind = p_kind and id <> pg.id;
    if old_id is not null then
      update public.catalog_pages set kind = 'inner',
        position = case when p_kind = 'front'
          then coalesce((select min(position) from public.catalog_pages where catalog_id = cid and kind = 'inner'), 1) - 1
          else coalesce((select max(position) from public.catalog_pages where catalog_id = cid and kind = 'inner'), 0) + 1 end
      where id = old_id;
    end if;
    update public.catalog_pages set kind = p_kind, position = 0 where id = pg.id;
  else
    update public.catalog_pages set kind = 'inner',
      position = coalesce((select max(position) from public.catalog_pages where catalog_id = cid and kind = 'inner'), 0) + 1
    where id = pg.id;
  end if;

  with r as (select id, row_number() over (order by position, created_at) rn
             from public.catalog_pages where catalog_id = cid and kind = 'inner')
  update public.catalog_pages c set position = r.rn from r where c.id = r.id;
end $$;

grant execute on function public.is_admin(), public.reorder_pages(uuid, uuid[]), public.set_page_kind(uuid, text)
  to anon, authenticated;

-- ---------- keamanan (RLS) ----------
alter table public.catalogs      enable row level security;
alter table public.catalog_pages enable row level security;

drop policy if exists "baca katalog terbit"  on public.catalogs;
drop policy if exists "admin kelola katalog" on public.catalogs;
create policy "baca katalog terbit"  on public.catalogs for select using (status = 'published' or public.is_admin());
create policy "admin kelola katalog" on public.catalogs for all    using (public.is_admin()) with check (public.is_admin());

drop policy if exists "baca halaman terbit"  on public.catalog_pages;
drop policy if exists "admin kelola halaman" on public.catalog_pages;
create policy "baca halaman terbit" on public.catalog_pages for select using (
  public.is_admin() or exists (select 1 from public.catalogs c where c.id = catalog_id and c.status = 'published'));
create policy "admin kelola halaman" on public.catalog_pages for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin lihat admins" on public.admins;
create policy "admin lihat admins" on public.admins for select using (user_id = auth.uid());

grant select on public.catalogs, public.catalog_pages to anon, authenticated;
grant insert, update, delete on public.catalogs, public.catalog_pages to authenticated;

-- ---------- penyimpanan gambar ----------
insert into storage.buckets (id, name, public) values ('catalog', 'catalog', true)
on conflict (id) do update set public = true;

drop policy if exists "catalog baca publik"  on storage.objects;
drop policy if exists "catalog admin tulis"  on storage.objects;
drop policy if exists "catalog admin ubah"   on storage.objects;
drop policy if exists "catalog admin hapus"  on storage.objects;
create policy "catalog baca publik" on storage.objects for select using (bucket_id = 'catalog');
create policy "catalog admin tulis" on storage.objects for insert to authenticated with check (bucket_id = 'catalog' and public.is_admin());
create policy "catalog admin ubah"  on storage.objects for update to authenticated using (bucket_id = 'catalog' and public.is_admin());
create policy "catalog admin hapus" on storage.objects for delete to authenticated using (bucket_id = 'catalog' and public.is_admin());

-- =====================================================================
--  LANGKAH TERAKHIR (jalankan terpisah, ganti email Anda):
--  1) Buat akun dulu di Supabase: Authentication > Users > Add user (email + password)
--  2) Jalankan:
--     insert into public.admins (user_id) select id from auth.users where email = 'EMAIL-ANDA@contoh.com';
-- =====================================================================
