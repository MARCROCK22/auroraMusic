-- Amigos de Aurora. Idempotente. Ejecutar DESPUÉS de accounts_supabase.sql
-- (necesita public.profiles).

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references auth.users(id) on delete cascade,
  to_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  check (from_id <> to_id)
);
-- Un solo par por pareja, sin importar quién la envió.
create unique index if not exists friend_requests_pair_idx
  on public.friend_requests (least(from_id, to_id), greatest(from_id, to_id));
create index if not exists friend_requests_to_idx on public.friend_requests (to_id);
create index if not exists friend_requests_from_idx on public.friend_requests (from_id);

create table if not exists public.shared_tracks (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references auth.users(id) on delete cascade,
  to_id uuid not null references auth.users(id) on delete cascade,
  track jsonb not null check (pg_column_size(track) <= 4096),
  note text check (note is null or char_length(note) <= 200),
  created_at timestamptz not null default now(),
  seen boolean not null default false,
  check (from_id <> to_id)
);
create index if not exists shared_tracks_to_idx
  on public.shared_tracks (to_id, created_at desc);
create index if not exists shared_tracks_from_idx
  on public.shared_tracks (from_id, created_at desc);

-- ¿Hay amistad aceptada entre a y b? Security definer para poder usarla en
-- políticas sin depender de la RLS del llamador.
create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friend_requests
    where status = 'accepted'
      and ((from_id = a and to_id = b) or (from_id = b and to_id = a))
  );
$$;
revoke all on function public.are_friends(uuid, uuid) from public;
grant execute on function public.are_friends(uuid, uuid) to authenticated;

alter table public.friend_requests enable row level security;
alter table public.shared_tracks enable row level security;

drop policy if exists friend_requests_select on public.friend_requests;
create policy friend_requests_select on public.friend_requests
  for select to authenticated
  using (auth.uid() = from_id or auth.uid() = to_id);

drop policy if exists friend_requests_insert on public.friend_requests;
create policy friend_requests_insert on public.friend_requests
  for insert to authenticated
  with check (auth.uid() = from_id and from_id <> to_id and status = 'pending');

-- Solo el destinatario resuelve la solicitud, y solo hacia accepted/declined.
drop policy if exists friend_requests_update on public.friend_requests;
create policy friend_requests_update on public.friend_requests
  for update to authenticated
  using (auth.uid() = to_id)
  with check (auth.uid() = to_id and status in ('accepted', 'declined'));

-- Cualquiera de los dos puede borrar (cancelar, rechazar o dejar de ser amigos).
drop policy if exists friend_requests_delete on public.friend_requests;
create policy friend_requests_delete on public.friend_requests
  for delete to authenticated
  using (auth.uid() = from_id or auth.uid() = to_id);

-- El update del destinatario no puede cambiar de quién es la solicitud.
create or replace function public.friend_requests_guard()
returns trigger
language plpgsql
as $$
begin
  if new.from_id <> old.from_id or new.to_id <> old.to_id
     or new.created_at <> old.created_at then
    raise exception 'Solo se puede cambiar el estado';
  end if;
  return new;
end;
$$;
drop trigger if exists friend_requests_guard on public.friend_requests;
create trigger friend_requests_guard before update on public.friend_requests
  for each row execute function public.friend_requests_guard();

drop policy if exists shared_tracks_select on public.shared_tracks;
create policy shared_tracks_select on public.shared_tracks
  for select to authenticated
  using (auth.uid() = from_id or auth.uid() = to_id);

drop policy if exists shared_tracks_insert on public.shared_tracks;
create policy shared_tracks_insert on public.shared_tracks
  for insert to authenticated
  with check (
    auth.uid() = from_id
    and seen = false
    and public.are_friends(from_id, to_id)
  );

drop policy if exists shared_tracks_update on public.shared_tracks;
create policy shared_tracks_update on public.shared_tracks
  for update to authenticated
  using (auth.uid() = to_id)
  with check (auth.uid() = to_id);

-- El destinatario solo puede tocar `seen`.
create or replace function public.shared_tracks_guard()
returns trigger
language plpgsql
as $$
begin
  if new.from_id <> old.from_id or new.to_id <> old.to_id
     or new.track <> old.track or new.note is distinct from old.note
     or new.created_at <> old.created_at then
    raise exception 'Solo se puede marcar como vista';
  end if;
  return new;
end;
$$;
drop trigger if exists shared_tracks_guard on public.shared_tracks;
create trigger shared_tracks_guard before update on public.shared_tracks
  for each row execute function public.shared_tracks_guard();

drop policy if exists shared_tracks_delete on public.shared_tracks;
create policy shared_tracks_delete on public.shared_tracks
  for delete to authenticated
  using (auth.uid() = to_id);

-- Límite: 30 envíos por hora y remitente.
create or replace function public.shared_tracks_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.shared_tracks
      where from_id = new.from_id
        and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'Demasiados envíos; prueba en un rato';
  end if;
  return new;
end;
$$;
drop trigger if exists shared_tracks_rate_limit on public.shared_tracks;
create trigger shared_tracks_rate_limit before insert on public.shared_tracks
  for each row execute function public.shared_tracks_rate_limit();

-- Realtime (postgres_changes). Ignora el error si ya estaban añadidas.
do $$
begin
  begin
    alter publication supabase_realtime add table public.friend_requests;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.shared_tracks;
  exception when duplicate_object then null;
  end;
end $$;
