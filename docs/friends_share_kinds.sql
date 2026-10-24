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
