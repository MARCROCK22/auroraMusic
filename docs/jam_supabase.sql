-- Aurora Music · Jam en línea (Supabase). Ejecutar COMPLETO en el SQL Editor
-- del proyecto. Es idempotente: se puede volver a ejecutar.
--
-- AVISO: este SQL NO se ha probado contra un proyecto real de Supabase. Antes
-- de usarlo con gente, sigue docs/jam_supabase.md (casos de abuso a probar).
--
-- Modelo de seguridad (mínimo privilegio):
--  * El cliente solo tiene la clave anónima y una sesión de auth anónima.
--  * Ninguna tabla es accesible: RLS activado, SIN políticas y REVOKE ALL.
--  * Todo pasa por RPC SECURITY DEFINER con `search_path = ''`, parámetros
--    tipados, validación por regex/whitelist y rate limit. No hay SQL dinámico
--    ni concatenación de texto del usuario dentro de sentencias SQL.
--  * Los errores al cliente son solo `jam:<código>`; nunca texto interno.
--  * Realtime: canales privados `jam:<CODIGO>:down|up` autorizados por RLS en
--    realtime.messages (solo anfitrión/coanfitrión publican en `down`; `up` lo
--    publica únicamente el servidor desde jam_cmd).

------------------------------------------------------------------------------
-- 1. Tablas (sin acceso directo)
------------------------------------------------------------------------------
create table if not exists public.jam_rooms (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  host          uuid not null,
  is_open       boolean not null default true,
  max_guests    int not null default 15 check (max_guests between 1 and 15),
  created_at    timestamptz not null default now(),
  last_activity timestamptz not null default now()
);
create index if not exists jam_rooms_host_idx on public.jam_rooms (host);
create index if not exists jam_rooms_activity_idx on public.jam_rooms (last_activity);

create table if not exists public.jam_members (
  room_id   uuid not null references public.jam_rooms (id) on delete cascade,
  uid       uuid not null,
  name      text not null check (char_length(name) between 1 and 32),
  device    text not null check (device in ('android', 'windows', 'other')),
  role      text not null check (role in ('host', 'cohost', 'guest')),
  muted     boolean not null default false,
  adds      int not null default 0 check (adds >= 0),
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (room_id, uid)
);
create index if not exists jam_members_uid_idx on public.jam_members (uid);

create table if not exists public.jam_bans (
  room_id uuid not null references public.jam_rooms (id) on delete cascade,
  uid     uuid not null,
  primary key (room_id, uid)
);

-- Ventanas fijas de rate limit por clave (usuario/sala/acción).
create table if not exists public.jam_rate (
  k      text not null check (char_length(k) <= 100),
  bucket timestamptz not null,
  n      int not null default 0,
  primary key (k, bucket)
);

-- Bloqueo por intentos fallidos de código (anti fuerza bruta / enumeración).
create table if not exists public.jam_lock (
  uid          uuid primary key,
  fails        int not null default 0,
  window_start timestamptz not null default now(),
  locked_until timestamptz
);

alter table public.jam_rooms   enable row level security;
alter table public.jam_members enable row level security;
alter table public.jam_bans    enable row level security;
alter table public.jam_rate    enable row level security;
alter table public.jam_lock    enable row level security;
-- Sin políticas a propósito: anon/authenticated no pueden leer ni escribir.
revoke all on public.jam_rooms, public.jam_members, public.jam_bans,
              public.jam_rate, public.jam_lock from public, anon, authenticated;

------------------------------------------------------------------------------
-- 2. Ayudantes internos (no expuestos)
------------------------------------------------------------------------------
create or replace function public.jam_fail(p_code text)
returns void language plpgsql immutable set search_path = '' as $$
begin
  raise exception 'jam:%', p_code;
end $$;

create or replace function public.jam_uid()
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v uuid := auth.uid();
begin
  if v is null then perform public.jam_fail('forbidden'); end if;
  return v;
end $$;

-- Rate limit de ventana fija. Falla con jam:rate al superar p_limit.
create or replace function public.jam_hit(p_key text, p_limit int, p_secs int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  b timestamptz := to_timestamp(floor(extract(epoch from now()) / p_secs) * p_secs);
  c int;
begin
  insert into public.jam_rate as r (k, bucket, n) values (left(p_key, 100), b, 1)
  on conflict (k, bucket) do update set n = r.n + 1
  returning r.n into c;
  if c > p_limit then perform public.jam_fail('rate'); end if;
end $$;

create or replace function public.jam_clean_name(p_name text)
returns text language plpgsql immutable set search_path = '' as $$
declare n text := btrim(coalesce(p_name, ''));
begin
  if char_length(n) < 1 or char_length(n) > 32
     or n ~ '[[:cntrl:]‎‏‪-‮⁦-⁩]' then
    perform public.jam_fail('payload');
  end if;
  return n;
end $$;

create or replace function public.jam_check_code(p_code text)
returns text language plpgsql immutable set search_path = '' as $$
declare c text := upper(coalesce(p_code, ''));
begin
  if c !~ '^[A-HJ-NP-Z2-9]{6}$' then perform public.jam_fail('invalid'); end if;
  return c;
end $$;

-- Código de 6 caracteres sin ambiguos (sin I, O, 0, 1) desde 16 bytes aleatorios.
create or replace function public.jam_gen_code()
returns text language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  raw bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  out text := '';
begin
  for i in 0..5 loop
    out := out || substr(alphabet, (get_byte(raw, i) % 32) + 1, 1);
  end loop;
  return out;
end $$;

-- Sala viva (no caducada) y rol del usuario; falla si no es miembro.
create or replace function public.jam_room_for(p_code text, p_uid uuid, out r public.jam_rooms, out m public.jam_members)
language plpgsql security definer set search_path = '' as $$
begin
  select * into r from public.jam_rooms where code = public.jam_check_code(p_code);
  if not found then perform public.jam_fail('invalid'); end if;
  if r.last_activity < now() - interval '12 hours' then
    delete from public.jam_rooms where id = r.id;
    perform public.jam_fail('expired');
  end if;
  select * into m from public.jam_members where room_id = r.id and uid = p_uid;
  if not found then perform public.jam_fail('forbidden'); end if;
end $$;

create or replace function public.jam_json(p_room public.jam_rooms, p_role text)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'code', p_room.code,
    'host', p_room.host,
    'expires_at', p_room.last_activity + interval '12 hours',
    'role', case p_role when 'cohost' then 'coHost' else p_role end);
$$;

-- Limpieza: sesiones sin actividad en 12 h y contadores viejos.
create or replace function public.jam_cleanup()
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.jam_rooms where last_activity < now() - interval '12 hours';
  delete from public.jam_rate where bucket < now() - interval '3 hours';
  delete from public.jam_lock where coalesce(locked_until, window_start) < now() - interval '1 day';
end $$;

-- Validación de una pista (misma forma que JamTrack del cliente).
create or replace function public.jam_valid_track(t jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare k text;
begin
  if jsonb_typeof(t) <> 'object' then return false; end if;
  for k in select jsonb_object_keys(t) loop
    if k <> all (array['key','title','artist','durationMs','youtubeId','spotifyUri','artworkUrl','localOnly']) then
      return false;
    end if;
  end loop;
  return jsonb_typeof(t->'key') = 'string' and (t->>'key') ~ '^[a-zA-Z0-9_-]{1,64}$'
     and jsonb_typeof(t->'title') = 'string' and char_length(t->>'title') between 1 and 256
     and (t->>'title') !~ '[[:cntrl:]]'
     and jsonb_typeof(t->'artist') = 'string' and char_length(t->>'artist') between 1 and 256
     and (t->>'artist') !~ '[[:cntrl:]]'
     and jsonb_typeof(t->'durationMs') = 'number' and (t->>'durationMs') ~ '^[0-9]{1,8}$'
     and (t->>'durationMs')::bigint <= 86400000
     and (t->'youtubeId' is null or jsonb_typeof(t->'youtubeId') = 'null'
          or (jsonb_typeof(t->'youtubeId') = 'string' and (t->>'youtubeId') ~ '^[a-zA-Z0-9_-]{11}$'))
     and (t->'spotifyUri' is null or jsonb_typeof(t->'spotifyUri') = 'null'
          or (jsonb_typeof(t->'spotifyUri') = 'string' and (t->>'spotifyUri') ~ '^spotify:track:[a-zA-Z0-9]{22}$'))
     and (t->'artworkUrl' is null or jsonb_typeof(t->'artworkUrl') = 'null'
          or (jsonb_typeof(t->'artworkUrl') = 'string' and char_length(t->>'artworkUrl') <= 512
              and (t->>'artworkUrl') ~ '^https://(i\.ytimg\.com|img\.youtube\.com|i\.scdn\.co|image-cdn-ak\.spotifycdn\.com)/[A-Za-z0-9_./-]*$'))
     and jsonb_typeof(t->'localOnly') = 'boolean';
end $$;

------------------------------------------------------------------------------
-- 3. RPC públicas (única superficie de escritura)
------------------------------------------------------------------------------
create or replace function public.jam_create(p_name text, p_device text)
returns jsonb language plpgsql security definer set search_path = '' set statement_timeout = '4s' as $$
declare
  u uuid := public.jam_uid();
  nm text := public.jam_clean_name(p_name);
  r public.jam_rooms;
  tries int := 0;
begin
  if p_device is null or p_device not in ('android', 'windows', 'other') then
    perform public.jam_fail('payload');
  end if;
  perform public.jam_hit('create:' || u::text, 3, 3600);   -- 3 salas por hora y usuario
  perform public.jam_cleanup();
  if (select count(*) from public.jam_rooms) >= 5000 then perform public.jam_fail('rate'); end if;
  if exists (select 1 from public.jam_rooms where host = u) then
    perform public.jam_fail('active');                      -- 1 sala activa por usuario
  end if;
  loop
    begin
      insert into public.jam_rooms (code, host) values (public.jam_gen_code(), u) returning * into r;
      exit;
    exception when unique_violation then
      tries := tries + 1;
      if tries > 5 then perform public.jam_fail('rate'); end if;
    end;
  end loop;
  insert into public.jam_members (room_id, uid, name, device, role) values (r.id, u, nm, p_device, 'host');
  return public.jam_json(r, 'host');
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

create or replace function public.jam_join(p_code text, p_name text, p_device text)
returns jsonb language plpgsql security definer set search_path = '' set statement_timeout = '4s' as $$
declare
  u uuid := public.jam_uid();
  nm text := public.jam_clean_name(p_name);
  c text;
  r public.jam_rooms;
  lk public.jam_lock;
  cnt int;
  mem public.jam_members;
begin
  if p_device is null or p_device not in ('android', 'windows', 'other') then
    perform public.jam_fail('payload');
  end if;
  perform public.jam_hit('join:' || u::text, 20, 600);      -- 20 intentos / 10 min
  select * into lk from public.jam_lock where uid = u;
  if found and lk.locked_until is not null and lk.locked_until > now() then
    perform public.jam_fail('rate');
  end if;
  -- Código mal formado o inexistente cuenta como fallo (bloqueo 15 min tras 5 en 10 min).
  begin
    c := public.jam_check_code(p_code);
    select * into r from public.jam_rooms where code = c;
    if not found then perform public.jam_fail('invalid'); end if;
  exception when others then
    insert into public.jam_lock as l (uid, fails, window_start) values (u, 1, now())
    on conflict (uid) do update set
      fails = case when l.window_start < now() - interval '10 minutes' then 1 else l.fails + 1 end,
      window_start = case when l.window_start < now() - interval '10 minutes' then now() else l.window_start end,
      locked_until = case when (case when l.window_start < now() - interval '10 minutes' then 1 else l.fails + 1 end) >= 5
                          then now() + interval '15 minutes' else null end;
    -- Se devuelve (no se lanza) para que el contador de fallos se confirme.
    return jsonb_build_object('error', 'invalid');
  end;
  delete from public.jam_lock where uid = u;
  if r.last_activity < now() - interval '12 hours' then
    delete from public.jam_rooms where id = r.id;
    perform public.jam_fail('expired');
  end if;
  if exists (select 1 from public.jam_bans where room_id = r.id and uid = u) then
    perform public.jam_fail('banned');
  end if;
  select * into mem from public.jam_members where room_id = r.id and uid = u;
  if found then
    update public.jam_members set name = nm, last_seen = now() where room_id = r.id and uid = u;
    return public.jam_json(r, mem.role);
  end if;
  if not r.is_open then perform public.jam_fail('closed'); end if;
  select count(*) into cnt from public.jam_members where room_id = r.id;
  if cnt >= r.max_guests + 1 then perform public.jam_fail('full'); end if;
  if (select count(*) from public.jam_members where uid = u) >= 3 then
    perform public.jam_fail('limit');                        -- máx. 3 salas a la vez
  end if;
  insert into public.jam_members (room_id, uid, name, device, role) values (r.id, u, nm, p_device, 'guest');
  update public.jam_rooms set last_activity = now() where id = r.id;
  return public.jam_json(r, 'guest');
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

create or replace function public.jam_members(p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  u uuid := public.jam_uid();
  x record;
begin
  perform public.jam_hit('mem:' || u::text, 60, 60);
  select * into x from public.jam_room_for(p_code, u);
  return coalesce((
    select jsonb_agg(jsonb_build_object('uid', m.uid, 'name', m.name,
      'role', case m.role when 'cohost' then 'coHost' else m.role end,
      'muted', m.muted, 'joined_at', m.joined_at) order by m.joined_at)
    from (select * from public.jam_members where room_id = (x.r).id order by joined_at limit 16) m
  ), '[]'::jsonb);
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

create or replace function public.jam_heartbeat(p_code text, p_activity boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare
  u uuid := public.jam_uid();
  x record;
begin
  perform public.jam_hit('hb:' || u::text, 12, 60);
  select * into x from public.jam_room_for(p_code, u);
  update public.jam_members set last_seen = now() where room_id = (x.r).id and uid = u;
  if coalesce(p_activity, false) then
    update public.jam_rooms set last_activity = now() where id = (x.r).id;
  end if;
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

-- Acción de invitado: el servidor valida y la reenvía al anfitrión con `from`
-- verificado (auth.uid()). El anfitrión decide el estado final.
create or replace function public.jam_cmd(p_code text, p_kind text, p_payload jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = '' set statement_timeout = '4s' as $$
declare
  u uuid := public.jam_uid();
  x record;
  allowed text[];
  k text;
  it jsonb;
  body text;
  topic text;
begin
  if p_kind is null or p_kind !~ '^[a-z]{3,10}$'
     or p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or octet_length(p_payload::text) > 6000 then
    perform public.jam_fail('payload');
  end if;
  allowed := case p_kind
    when 'hello'    then array[]::text[]
    when 'ping'     then array['sent']
    when 'leave'    then array[]::text[]
    when 'skip'     then array[]::text[]
    when 'voteskip' then array[]::text[]
    when 'add'      then array['track']
    when 'remove'   then array['entryId']
    when 'reorder'  then array['entryId','to']
    when 'vote'     then array['entryId','v']
    when 'pause'    then array['play']
    when 'listen'   then array['on']
    when 'suggest'  then array['items']
    else null end;
  if allowed is null then perform public.jam_fail('payload'); end if;
  for k in select jsonb_object_keys(p_payload) loop       -- rechaza campos inesperados
    if k <> all (allowed) then perform public.jam_fail('payload'); end if;
  end loop;

  perform public.jam_hit('cmd:' || u::text, 120, 60);     -- por usuario
  select * into x from public.jam_room_for(p_code, u);
  perform public.jam_hit('room:' || (x.r).id::text, 600, 60); -- por sala
  if (x.m).role = 'host' then perform public.jam_fail('forbidden'); end if;
  if (x.m).muted and p_kind in ('add', 'vote', 'voteskip', 'suggest') then
    perform public.jam_fail('muted');
  end if;

  if p_kind = 'add' then
    perform public.jam_hit('add:' || u::text, 20, 60);
    if not public.jam_valid_track(p_payload->'track') then perform public.jam_fail('payload'); end if;
    if (x.m).adds >= 200 then perform public.jam_fail('limit'); end if;
    update public.jam_members set adds = adds + 1 where room_id = (x.r).id and uid = u;
  elsif p_kind in ('remove', 'vote') then
    if jsonb_typeof(p_payload->'entryId') <> 'string' or (p_payload->>'entryId') !~ '^[a-zA-Z0-9_-]{1,64}$' then
      perform public.jam_fail('payload');
    end if;
    if p_kind = 'vote' and (jsonb_typeof(p_payload->'v') <> 'number' or (p_payload->>'v') not in ('-1', '0', '1')) then
      perform public.jam_fail('payload');
    end if;
  elsif p_kind = 'reorder' then
    if jsonb_typeof(p_payload->'entryId') <> 'string' or (p_payload->>'entryId') !~ '^[a-zA-Z0-9_-]{1,64}$'
       or jsonb_typeof(p_payload->'to') <> 'number' or (p_payload->>'to') !~ '^[0-9]{1,3}$' then
      perform public.jam_fail('payload');
    end if;
  elsif p_kind = 'pause' then
    if jsonb_typeof(p_payload->'play') <> 'boolean' then perform public.jam_fail('payload'); end if;
  elsif p_kind = 'listen' then
    if jsonb_typeof(p_payload->'on') <> 'boolean' then perform public.jam_fail('payload'); end if;
  elsif p_kind = 'ping' then
    if jsonb_typeof(p_payload->'sent') <> 'number' or (p_payload->>'sent') !~ '^[0-9]{1,16}$' then
      perform public.jam_fail('payload');
    end if;
  elsif p_kind = 'suggest' then
    perform public.jam_hit('sug:' || u::text, 1, 60);      -- 1 publicación por minuto
    if jsonb_typeof(p_payload->'items') <> 'array' or jsonb_array_length(p_payload->'items') > 5 then
      perform public.jam_fail('payload');
    end if;
    for it in select * from jsonb_array_elements(p_payload->'items') loop
      if jsonb_typeof(it) <> 'object'
         or exists (select 1 from jsonb_object_keys(it) kk where kk <> all (array['track','reason']))
         or not public.jam_valid_track(it->'track')
         or jsonb_typeof(it->'reason') <> 'string' or char_length(it->>'reason') not between 1 and 60
         or (it->>'reason') ~ '[[:cntrl:]]' then
        perform public.jam_fail('payload');
      end if;
    end loop;
  end if;

  if p_kind not in ('ping', 'hello') then
    update public.jam_rooms set last_activity = now() where id = (x.r).id;
  end if;
  update public.jam_members set last_seen = now() where room_id = (x.r).id and uid = u;

  body := (jsonb_build_object('kind', p_kind) || p_payload)::text;
  topic := 'jam:' || (x.r).code || ':up';
  perform realtime.send(jsonb_build_object('f', u::text, 't', '*', 'm', body), 'm', topic, true);
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

create or replace function public.jam_leave(p_code text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  u uuid := public.jam_uid();
  x record;
begin
  perform public.jam_hit('leave:' || u::text, 30, 60);
  select * into x from public.jam_room_for(p_code, u);
  if (x.m).role = 'host' then
    delete from public.jam_rooms where id = (x.r).id;
  else
    delete from public.jam_members where room_id = (x.r).id and uid = u;
  end if;
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

create or replace function public.jam_close(p_code text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  u uuid := public.jam_uid();
  x record;
begin
  select * into x from public.jam_room_for(p_code, u);
  if (x.m).role <> 'host' then perform public.jam_fail('forbidden'); end if;
  delete from public.jam_rooms where id = (x.r).id;
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

create or replace function public.jam_kick(p_code text, p_uid uuid, p_ban boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare
  u uuid := public.jam_uid();
  x record;
  tgt public.jam_members;
begin
  perform public.jam_hit('mod:' || u::text, 30, 60);
  select * into x from public.jam_room_for(p_code, u);
  if (x.m).role not in ('host', 'cohost') then perform public.jam_fail('forbidden'); end if;
  select * into tgt from public.jam_members where room_id = (x.r).id and uid = p_uid;
  if not found or tgt.role = 'host' or (tgt.role = 'cohost' and (x.m).role <> 'host') then
    perform public.jam_fail('forbidden');
  end if;
  delete from public.jam_members where room_id = (x.r).id and uid = p_uid;
  if coalesce(p_ban, false) then
    if (select count(*) from public.jam_bans where room_id = (x.r).id) >= 50 then
      perform public.jam_fail('limit');
    end if;
    insert into public.jam_bans (room_id, uid) values ((x.r).id, p_uid) on conflict do nothing;
  end if;
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

create or replace function public.jam_mute(p_code text, p_uid uuid, p_muted boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  u uuid := public.jam_uid();
  x record;
begin
  perform public.jam_hit('mod:' || u::text, 30, 60);
  select * into x from public.jam_room_for(p_code, u);
  if (x.m).role not in ('host', 'cohost') then perform public.jam_fail('forbidden'); end if;
  update public.jam_members set muted = coalesce(p_muted, false)
   where room_id = (x.r).id and uid = p_uid and role = 'guest';
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

create or replace function public.jam_cohost(p_code text, p_uid uuid, p_on boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  u uuid := public.jam_uid();
  x record;
begin
  perform public.jam_hit('mod:' || u::text, 30, 60);
  select * into x from public.jam_room_for(p_code, u);
  if (x.m).role <> 'host' then perform public.jam_fail('forbidden'); end if;
  update public.jam_members set role = case when coalesce(p_on, false) then 'cohost' else 'guest' end
   where room_id = (x.r).id and uid = p_uid and role <> 'host';
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

create or replace function public.jam_access(p_code text, p_open boolean, p_max int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  u uuid := public.jam_uid();
  x record;
begin
  perform public.jam_hit('mod:' || u::text, 30, 60);
  select * into x from public.jam_room_for(p_code, u);
  if (x.m).role <> 'host' then perform public.jam_fail('forbidden'); end if;
  if p_max is null or p_max not between 1 and 15 or p_open is null then perform public.jam_fail('payload'); end if;
  update public.jam_rooms set is_open = p_open, max_guests = p_max where id = (x.r).id;
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

-- Rota el código: el anterior deja de servir; los miembros siguen dentro.
create or replace function public.jam_rotate(p_code text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  u uuid := public.jam_uid();
  x record;
  nc text;
  tries int := 0;
begin
  perform public.jam_hit('rot:' || u::text, 5, 3600);
  select * into x from public.jam_room_for(p_code, u);
  if (x.m).role <> 'host' then perform public.jam_fail('forbidden'); end if;
  loop
    nc := public.jam_gen_code();
    begin
      update public.jam_rooms set code = nc where id = (x.r).id;
      exit;
    exception when unique_violation then
      tries := tries + 1;
      if tries > 5 then perform public.jam_fail('rate'); end if;
    end;
  end loop;
  return nc;
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

-- El anfitrión cede el mando y pasa a coanfitrión.
create or replace function public.jam_transfer(p_code text, p_uid uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  u uuid := public.jam_uid();
  x record;
begin
  perform public.jam_hit('mod:' || u::text, 30, 60);
  select * into x from public.jam_room_for(p_code, u);
  if (x.m).role <> 'host' or p_uid is null or p_uid = u
     or not exists (select 1 from public.jam_members where room_id = (x.r).id and uid = p_uid) then
    perform public.jam_fail('forbidden');
  end if;
  update public.jam_members set role = 'cohost' where room_id = (x.r).id and uid = u;
  update public.jam_members set role = 'host', muted = false where room_id = (x.r).id and uid = p_uid;
  update public.jam_rooms set host = p_uid where id = (x.r).id;
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

-- Confirma el mando tras una cesión, o lo hereda el invitado más antiguo si el
-- anfitrión lleva más de 60 s sin latido.
create or replace function public.jam_claim_host(p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  u uuid := public.jam_uid();
  x record;
  oldest uuid;
begin
  perform public.jam_hit('claim:' || u::text, 10, 600);
  select * into x from public.jam_room_for(p_code, u);
  if (x.m).role = 'host' then return public.jam_json(x.r, 'host'); end if;
  if (select last_seen from public.jam_members where room_id = (x.r).id and uid = (x.r).host)
       > now() - interval '60 seconds' then
    perform public.jam_fail('forbidden');
  end if;
  select uid into oldest from public.jam_members
   where room_id = (x.r).id and role <> 'host' and last_seen > now() - interval '60 seconds'
   order by joined_at, uid limit 1;
  if oldest is distinct from u then perform public.jam_fail('forbidden'); end if;
  update public.jam_members set role = 'guest' where room_id = (x.r).id and uid = (x.r).host;
  update public.jam_members set role = 'host', muted = false where room_id = (x.r).id and uid = u;
  update public.jam_rooms set host = u, last_activity = now() where id = (x.r).id;
  return jsonb_build_object('code', (x.r).code, 'host', u, 'role', 'host',
                            'expires_at', now() + interval '12 hours');
exception when others then
  if sqlerrm ~ '^jam:[a-z]{3,12}$' then raise; end if;
  raise exception 'jam:unknown';
end $$;

------------------------------------------------------------------------------
-- 4. Privilegios: nada por defecto; solo EXECUTE a las RPC públicas
------------------------------------------------------------------------------
revoke all on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

grant execute on function
  public.jam_create(text, text),
  public.jam_join(text, text, text),
  public.jam_members(text),
  public.jam_heartbeat(text, boolean),
  public.jam_cmd(text, text, jsonb),
  public.jam_leave(text),
  public.jam_close(text),
  public.jam_kick(text, uuid, boolean),
  public.jam_mute(text, uuid, boolean),
  public.jam_cohost(text, uuid, boolean),
  public.jam_access(text, boolean, int),
  public.jam_rotate(text),
  public.jam_transfer(text, uuid),
  public.jam_claim_host(text)
to authenticated;   -- las sesiones anónimas usan el rol `authenticated`

------------------------------------------------------------------------------
-- 5. Realtime privado: autorización de canales jam:<CODIGO>:down|up
------------------------------------------------------------------------------
-- Ayudante usado por las políticas (solo responde sobre el propio usuario).
create or replace function public.jam_rt_role(p_topic text)
returns text language sql stable security definer set search_path = '' as $$
  select m.role
    from public.jam_rooms r
    join public.jam_members m on m.room_id = r.id and m.uid = auth.uid()
   where p_topic ~ '^jam:[A-HJ-NP-Z2-9]{6}:(down|up)$'
     and r.code = split_part(p_topic, ':', 2)
     and r.last_activity > now() - interval '12 hours'
$$;
revoke all on function public.jam_rt_role(text) from public, anon;
grant execute on function public.jam_rt_role(text) to authenticated;

alter table realtime.messages enable row level security;

drop policy if exists jam_rt_read on realtime.messages;
create policy jam_rt_read on realtime.messages for select to authenticated
using (
  (extension in ('broadcast', 'presence'))
  and (
    (realtime.topic() like 'jam:%:down' and public.jam_rt_role(realtime.topic()) is not null)
    or (realtime.topic() like 'jam:%:up' and extension = 'broadcast'
        and public.jam_rt_role(realtime.topic()) = 'host')
  )
);

drop policy if exists jam_rt_write on realtime.messages;
create policy jam_rt_write on realtime.messages for insert to authenticated
with check (
  realtime.topic() like 'jam:%:down'
  and (
    (extension = 'broadcast' and public.jam_rt_role(realtime.topic()) in ('host', 'cohost'))
    or (extension = 'presence' and public.jam_rt_role(realtime.topic()) is not null)
  )
);
-- `jam:*:up` no tiene política de escritura: solo el servidor publica ahí
-- (realtime.send dentro de jam_cmd, que corre como propietario).

------------------------------------------------------------------------------
-- 6. Limpieza programada (12 h sin actividad). Requiere la extensión pg_cron:
--    Dashboard → Database → Extensions → pg_cron → Enable. Luego descomenta.
------------------------------------------------------------------------------
-- select cron.schedule('jam-cleanup', '*/15 * * * *', $$select public.jam_cleanup()$$);
-- Sin pg_cron igualmente se limpia al crear salas (jam_create) y al unirse
-- a una sala caducada.
