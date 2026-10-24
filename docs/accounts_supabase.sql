-- Aurora Music · Cuentas y sincronización (Supabase). Ejecutar COMPLETO en el
-- SQL Editor del MISMO proyecto que la Jam. Idempotente: se puede repetir.
--
-- Antes: Authentication > Providers > habilitar "Email". Para pruebas, desactiva
-- "Confirm email" (si queda activo, la app pide confirmar el correo antes de
-- poder entrar). La Jam sigue usando sesiones anónimas: las políticas de abajo
-- exigen una cuenta real (is_anonymous = false).
--
-- AVISO: no probado contra un proyecto real.

-- 1. Perfiles ---------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  avatar_path text,
  username_changed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint profiles_username_chk check (username ~ '^[a-z0-9_.]{3,24}$'),
  constraint profiles_avatar_chk check (
    avatar_path is null or avatar_path ~ '^[0-9a-f-]{36}/[0-9]{1,16}\.png$')
);
create unique index if not exists profiles_username_key on public.profiles (username);

create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;

-- Crea el perfil al registrarse. Si el nombre no es válido el alta falla.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare u text := lower(coalesce(new.raw_user_meta_data->>'username', ''));
begin
  if u !~ '^[a-z0-9_.]{3,24}$' then raise exception 'username invalido'; end if;
  insert into public.profiles (id, username) values (new.id, u);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Reglas de edición: el id no cambia; el nombre solo una vez cada 30 días.
create or replace function public.profiles_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.id := old.id;
  new.updated_at := now();
  if new.username is distinct from old.username then
    if old.username_changed_at is not null
       and old.username_changed_at > now() - interval '30 days' then
      raise exception 'username: cambio demasiado reciente';
    end if;
    new.username_changed_at := now();
  else
    new.username_changed_at := old.username_changed_at;
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update on public.profiles
  for each row execute function public.profiles_guard();

alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select (id, username, avatar_path) on public.profiles to authenticated;
grant update (username, avatar_path) on public.profiles to authenticated;
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using ((select (auth.jwt()->>'is_anonymous')::boolean) is not true);
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- 2. Datos sincronizados ----------------------------------------------------
-- updated_at lo fija SIEMPRE el servidor (trigger), así el cursor de
-- sincronización no depende del reloj de cada dispositivo.
create table if not exists public.user_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  track_id text not null check (char_length(track_id) between 1 and 64),
  track jsonb not null check (octet_length(track::text) <= 4096),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false,
  primary key (user_id, track_id)
);
create table if not exists public.user_playlists (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null check (char_length(id) between 1 and 64),
  name text not null check (char_length(name) between 1 and 100),
  tracks jsonb not null check (octet_length(tracks::text) <= 524288),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false,
  primary key (user_id, id)
);
create table if not exists public.user_history (
  user_id uuid not null references auth.users(id) on delete cascade,
  track_id text not null check (char_length(track_id) between 1 and 64),
  track jsonb not null check (octet_length(track::text) <= 4096),
  played_at timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, track_id)
);
create table if not exists public.user_taste (
  user_id uuid primary key references auth.users(id) on delete cascade,
  profile jsonb not null check (octet_length(profile::text) <= 16384),
  updated_at timestamptz not null default now()
);
create index if not exists user_favorites_upd on public.user_favorites (user_id, updated_at);
create index if not exists user_playlists_upd on public.user_playlists (user_id, updated_at);
create index if not exists user_history_upd on public.user_history (user_id, updated_at);

do $$ declare t text; begin
  foreach t in array array['user_favorites','user_playlists','user_history','user_taste'] loop
    execute format('drop trigger if exists touch on public.%I', t);
    execute format('create trigger touch before insert or update on public.%I
                    for each row execute function public.touch_updated_at()', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('drop policy if exists own on public.%I', t);
    execute format('create policy own on public.%I for all to authenticated
      using (user_id = (select auth.uid()) and (select (auth.jwt()->>''is_anonymous'')::boolean) is not true)
      with check (user_id = (select auth.uid()) and (select (auth.jwt()->>''is_anonymous'')::boolean) is not true)', t);
  end loop;
end $$;

-- Historial: se conservan las últimas 500 reproducciones por usuario.
create or replace function public.user_history_trim() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.user_history h where h.user_id = new.user_id and h.track_id in (
    select track_id from public.user_history where user_id = new.user_id
    order by played_at desc offset 500);
  return null;
end $$;
drop trigger if exists user_history_trim on public.user_history;
create trigger user_history_trim after insert on public.user_history
  for each row execute function public.user_history_trim();

-- 3. Avatares (lectura pública; cada usuario solo escribe en su carpeta) -------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 65536, array['image/png'])
on conflict (id) do update set public = true, file_size_limit = 65536,
  allowed_mime_types = array['image/png'];

drop policy if exists avatars_insert on storage.objects;
create policy avatars_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists avatars_update on storage.objects;
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists avatars_delete on storage.objects;
create policy avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
