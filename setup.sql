-- 달쌤 학습 앱 · Supabase 설정 (SQL Editor에 전체 붙여 넣고 Run)
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.students (
  name text primary key,
  pin_hash text not null,
  data jsonb not null default '{}'::jsonb,
  rev int not null default 0,
  fails int not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.app_admin (
  id int primary key default 1 check (id = 1),
  pw_hash text not null
);
alter table public.students enable row level security;
alter table public.app_admin enable row level security;
revoke all on public.students from anon, authenticated;
revoke all on public.app_admin from anon, authenticated;

-- 학생 확인 (비밀번호 10번 틀리면 10분 잠금)
create or replace function public._st_check(p_name text, p_pin text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare r public.students;
begin
  select * into r from public.students where name = btrim(p_name) for update;
  if not found then return 'not_found'; end if;
  if r.locked_until is not null and r.locked_until > now() then return 'locked'; end if;
  if r.pin_hash <> crypt(p_pin, r.pin_hash) then
    update public.students set fails = fails + 1,
      locked_until = case when fails + 1 >= 10 then now() + interval '10 minutes' else null end
      where name = r.name;
    return 'wrong_pin';
  end if;
  if r.fails > 0 then update public.students set fails = 0, locked_until = null where name = r.name; end if;
  return 'ok';
end $$;

create or replace function public.st_login(p_name text, p_pin text, p_create boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r public.students; n text := btrim(coalesce(p_name, '')); st text;
begin
  if n = '' or length(n) > 20 or coalesce(p_pin, '') !~ '^[0-9]{4}$' then return jsonb_build_object('error', 'invalid'); end if;
  if not exists (select 1 from public.students where name = n) then
    if not p_create then return jsonb_build_object('error', 'not_found'); end if;
    insert into public.students(name, pin_hash) values (n, crypt(p_pin, gen_salt('bf'))) returning * into r;
    return jsonb_build_object('ok', true, 'created', true, 'data', r.data, 'rev', r.rev);
  end if;
  st := public._st_check(n, p_pin);
  if st <> 'ok' then return jsonb_build_object('error', st); end if;
  select * into r from public.students where name = n;
  return jsonb_build_object('ok', true, 'created', false, 'data', r.data, 'rev', r.rev);
end $$;

create or replace function public.st_save(p_name text, p_pin text, p_data jsonb, p_rev int)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r public.students; st text;
begin
  if pg_column_size(p_data) > 3000000 then return jsonb_build_object('error', 'too_big'); end if;
  st := public._st_check(p_name, p_pin);
  if st <> 'ok' then return jsonb_build_object('error', st); end if;
  select * into r from public.students where name = btrim(p_name);
  if r.rev <> p_rev then return jsonb_build_object('error', 'conflict', 'data', r.data, 'rev', r.rev); end if;
  update public.students set data = p_data, rev = rev + 1, updated_at = now() where name = r.name;
  return jsonb_build_object('ok', true, 'rev', r.rev + 1);
end $$;

create or replace function public.ping() returns int language sql as $$ select 1 $$;

-- 관리자
create or replace function public.admin_setup(p_pw text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from public.app_admin) then return jsonb_build_object('error', 'already_set'); end if;
  if length(coalesce(p_pw, '')) < 6 then return jsonb_build_object('error', 'too_short'); end if;
  insert into public.app_admin(id, pw_hash) values (1, crypt(p_pw, gen_salt('bf')));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public._admin_ok(p_pw text)
returns boolean language sql security definer set search_path = public, extensions as $$
  select exists (select 1 from public.app_admin where pw_hash = crypt(p_pw, pw_hash));
$$;

create or replace function public.admin_status()
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object('set', exists (select 1 from public.app_admin));
$$;

create or replace function public.admin_list(p_pw text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform pg_sleep(0.3);
  if not public._admin_ok(p_pw) then return jsonb_build_object('error', 'wrong_pw'); end if;
  return jsonb_build_object('ok', true, 'students', coalesce((
    select jsonb_agg(jsonb_build_object('name', name, 'data', data, 'created_at', created_at, 'updated_at', updated_at) order by updated_at desc)
    from public.students), '[]'::jsonb));
end $$;

create or replace function public.admin_reset_pin(p_pw text, p_name text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public._admin_ok(p_pw) then return jsonb_build_object('error', 'wrong_pw'); end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then return jsonb_build_object('error', 'invalid'); end if;
  update public.students set pin_hash = crypt(p_pin, gen_salt('bf')), fails = 0, locked_until = null where name = p_name;
  return jsonb_build_object('ok', found);
end $$;

create or replace function public.admin_delete(p_pw text, p_name text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public._admin_ok(p_pw) then return jsonb_build_object('error', 'wrong_pw'); end if;
  delete from public.students where name = p_name;
  return jsonb_build_object('ok', found);
end $$;

revoke execute on function public._st_check(text, text) from public, anon, authenticated;
revoke execute on function public._admin_ok(text) from public, anon, authenticated;
grant execute on function public.st_login(text, text, boolean), public.st_save(text, text, jsonb, int), public.ping(),
  public.admin_setup(text), public.admin_status(), public.admin_list(text), public.admin_reset_pin(text, text, text), public.admin_delete(text, text)
  to anon, authenticated;
