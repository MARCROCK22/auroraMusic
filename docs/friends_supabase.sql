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

-- ===== Listas y Jam (igual que friends_share_kinds.sql) =====
-- Aurora: compartir listas e invitar a una Jam. Idempotente.
-- Pega SOLO este archivo si ya aplicaste friends_supabase.sql antes.
-- Las filas antiguas siguen siendo válidas (kind = 'track').
-- `track` guarda la carga útil de cualquier tipo:
--   track    -> pista (<= 4 KB)
--   playlist -> {name, tracks[]} (<= 256 KB, la app envía como mucho 500 pistas)
--   jam      -> {code} con el código de la Jam; solo lo ven remitente y
--               destinatario (RLS) y caduca a las 2 h.

alter table public.shared_tracks
  add column if not exists kind text not null default 'track';

alter table public.shared_tracks drop constraint if exists shared_tracks_kind_chk;
alter table public.shared_tracks add constraint shared_tracks_kind_chk
  check (kind in ('track', 'playlist', 'jam'));

-- Sustituye el límite fijo de 4 KB por uno según el tipo.
alter table public.shared_tracks drop constraint if exists shared_tracks_track_check;
alter table public.shared_tracks drop constraint if exists shared_tracks_payload_chk;
alter table public.shared_tracks add constraint shared_tracks_payload_chk
  check (
    pg_column_size(track) <= case kind when 'playlist' then 262144 else 4096 end
  );

alter table public.shared_tracks drop constraint if exists shared_tracks_jam_code_chk;
alter table public.shared_tracks add constraint shared_tracks_jam_code_chk
  check (
    kind <> 'jam'
    or (track->>'code') ~ '^[A-HJ-NP-Z2-9]{6}([A-HJ-NP-Z2-9]{2})?$'
  );

-- Lectura: una invitación a Jam deja de ser visible a las 2 h.
drop policy if exists shared_tracks_select on public.shared_tracks;
create policy shared_tracks_select on public.shared_tracks
  for select to authenticated
  using (
    (auth.uid() = from_id or auth.uid() = to_id)
    and (kind <> 'jam' or created_at > now() - interval '2 hours')
  );

-- El destinatario solo puede tocar `seen` (tampoco `kind`).
create or replace function public.shared_tracks_guard()
returns trigger
language plpgsql
as $$
begin
  if new.from_id <> old.from_id or new.to_id <> old.to_id
     or new.track <> old.track or new.note is distinct from old.note
     or new.kind <> old.kind
     or new.created_at <> old.created_at then
    raise exception 'Solo se puede marcar como vista';
  end if;
  return new;
end;
$$;
drop trigger if exists shared_tracks_guard on public.shared_tracks;
create trigger shared_tracks_guard before update on public.shared_tracks
  for each row execute function public.shared_tracks_guard();

-- Insert: sigue exigiendo amistad aceptada (se reafirma por si faltaba).
drop policy if exists shared_tracks_insert on public.shared_tracks;
create policy shared_tracks_insert on public.shared_tracks
  for insert to authenticated
  with check (
    auth.uid() = from_id
    and seen = false
    and public.are_friends(from_id, to_id)
  );

-- El límite de 30 envíos/hora (cualquier tipo) ya lo aplica el trigger
-- shared_tracks_rate_limit del archivo base; no cambia.

-- Realtime: la tabla ya estaba publicada; ignora el error si es así.
do $$
begin
  begin
    alter publication supabase_realtime add table public.shared_tracks;
  exception when duplicate_object then null;
  end;
end $$;
