-- Ejecuta este archivo completo en Supabase > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.invited_guests (
  id uuid primary key default gen_random_uuid(),
  official_name text not null,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'declined')),
  extra_guest_allowance smallint not null default 0 check (extra_guest_allowance >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.guest_groups (
  id uuid primary key default gen_random_uuid(),
  primary_guest_id uuid not null references public.invited_guests(id),
  companion_guest_id uuid references public.invited_guests(id),
  primary_name text not null,
  companion_name text,
  companion_is_unlisted boolean not null default false,
  status text not null default 'confirmed' check (status in ('confirmed', 'declined', 'pending')),
  whatsapp_sent_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.guest_groups add column if not exists companion_is_unlisted boolean not null default false;
alter table public.invited_guests add column if not exists extra_guest_allowance smallint not null default 0;

create table if not exists public.guest_group_members (
  guest_group_id uuid not null references public.guest_groups(id) on delete cascade,
  invited_guest_id uuid not null unique references public.invited_guests(id),
  invited_by_guest_id uuid not null references public.invited_guests(id),
  created_at timestamptz not null default now(),
  primary key (guest_group_id, invited_guest_id)
);

create or replace function public.enforce_guest_group_member_allowance()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_allowance smallint;
  v_used integer;
begin
  select extra_guest_allowance into v_allowance
  from public.invited_guests
  where id = new.invited_by_guest_id
  for update;

  if v_allowance is null or v_allowance < 1 then
    raise exception 'Este invitado no tiene cupos adicionales';
  end if;

  if not exists (
    select 1 from public.guest_groups as guest_group
    where guest_group.id = new.guest_group_id
      and (guest_group.primary_guest_id = new.invited_by_guest_id
        or guest_group.companion_guest_id = new.invited_by_guest_id)
  ) and not exists (
    select 1 from public.guest_group_members as inviter_member
    where inviter_member.guest_group_id = new.guest_group_id
      and inviter_member.invited_guest_id = new.invited_by_guest_id
  ) then
    raise exception 'El invitado que asigna el cupo debe pertenecer al grupo';
  end if;

  select count(*) into v_used
  from public.guest_group_members as member
  where member.invited_by_guest_id = new.invited_by_guest_id
    and member.invited_guest_id <> new.invited_guest_id;

  if v_used >= v_allowance then
    raise exception 'Se alcanzó el límite de invitados adicionales';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_guest_group_member_allowance on public.guest_group_members;
create trigger enforce_guest_group_member_allowance
before insert or update on public.guest_group_members
for each row execute function public.enforce_guest_group_member_allowance();

create unique index if not exists invited_guests_official_name_key
  on public.invited_guests (official_name);

alter table public.invited_guests enable row level security;
alter table public.guest_groups enable row level security;
alter table public.guest_group_members enable row level security;

drop policy if exists "Anyone can search invited guests" on public.invited_guests;
create policy "Anyone can search invited guests"
  on public.invited_guests for select to anon, authenticated using (true);

drop policy if exists "Admins can manage invited guests" on public.invited_guests;
create policy "Admins can manage invited guests"
  on public.invited_guests for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can view guest groups" on public.guest_groups;
create policy "Admins can view guest groups"
  on public.guest_groups for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can manage guest groups" on public.guest_groups;
create policy "Admins can manage guest groups"
  on public.guest_groups for update to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can manage guest group members" on public.guest_group_members;
create policy "Admins can manage guest group members"
  on public.guest_group_members for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop function if exists public.confirm_guest_group(uuid, text, uuid, text);
create or replace function public.confirm_guest_group(
  p_primary_id uuid,
  p_primary_name text,
  p_companion_id uuid default null,
  p_companion_name text default null,
  p_companion_is_unlisted boolean default false
)
returns public.guest_groups
language plpgsql
security definer
set search_path = public
as $$
declare
  primary_guest public.invited_guests;
  companion_guest public.invited_guests;
  new_group public.guest_groups;
begin
  if (now() at time zone 'America/La_Paz')::date > date '2026-09-30' then
    raise exception 'El plazo para confirmar asistencia ya finalizó';
  end if;

  select * into primary_guest from public.invited_guests where id = p_primary_id for update;
  if primary_guest.id is null then raise exception 'El invitado principal no existe'; end if;
  if primary_guest.status <> 'pending' then raise exception 'El invitado principal ya tiene una respuesta'; end if;
  if p_primary_name is null or btrim(p_primary_name) = '' then raise exception 'El nombre principal es obligatorio'; end if;

  if p_companion_id is not null then
    if p_companion_id = p_primary_id then raise exception 'El acompañante debe ser diferente'; end if;
    select * into companion_guest from public.invited_guests where id = p_companion_id for update;
    if companion_guest.id is null then raise exception 'El acompañante no existe'; end if;
    if companion_guest.status <> 'pending' then raise exception 'El acompañante ya tiene una respuesta'; end if;
    if p_companion_name is null or btrim(p_companion_name) = '' then raise exception 'Falta el nombre del acompañante'; end if;
  elsif p_companion_is_unlisted and (p_companion_name is null or btrim(p_companion_name) = '') then
    raise exception 'Falta el nombre del acompañante';
  end if;

  insert into public.guest_groups (primary_guest_id, companion_guest_id, primary_name, companion_name, companion_is_unlisted)
  values (p_primary_id, p_companion_id, btrim(p_primary_name), nullif(btrim(p_companion_name), ''), p_companion_is_unlisted)
  returning * into new_group;

  update public.invited_guests set status = 'confirmed' where id = p_primary_id or id = p_companion_id;
  return new_group;
end;
$$;

grant execute on function public.confirm_guest_group(uuid, text, uuid, text, boolean) to anon, authenticated;

drop function if exists public.get_public_confirmed_groups();
create function public.get_public_confirmed_groups()
returns table (primary_name text, companion_name text, additional_names text[])
language sql
stable
security definer
set search_path = public
as $$
  select guest_group.primary_name,
         guest_group.companion_name,
         coalesce(array_agg(guest.official_name order by guest.official_name)
           filter (where guest.id is not null), array[]::text[])
  from public.guest_groups as guest_group
  left join public.guest_group_members as member on member.guest_group_id = guest_group.id
  left join public.invited_guests as guest on guest.id = member.invited_guest_id
  where guest_group.status = 'confirmed'
  group by guest_group.id, guest_group.primary_name, guest_group.companion_name
  order by guest_group.primary_name;
$$;

grant execute on function public.get_public_confirmed_groups() to anon, authenticated;

create or replace function public.set_guest_group_status(p_group_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  guest_group public.guest_groups;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin' then
    raise exception 'No autorizado';
  end if;
  if p_status is null or p_status not in ('pending', 'confirmed', 'declined') then
    raise exception 'Estado no válido';
  end if;

  select * into guest_group from public.guest_groups where id = p_group_id for update;
  if not found then raise exception 'El grupo no existe'; end if;

  update public.guest_groups set status = p_status where id = p_group_id;
  update public.invited_guests
  set status = p_status
  where id = guest_group.primary_guest_id or id = guest_group.companion_guest_id;
  update public.invited_guests as guest
  set status = p_status
  where guest.id in (
    select member.invited_guest_id
    from public.guest_group_members as member
    where member.guest_group_id = p_group_id
  );
end;
$$;

create or replace function public.set_invited_guest_status(p_guest_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  guest_group public.guest_groups;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin' then
    raise exception 'No autorizado';
  end if;
  if p_status is null or p_status not in ('pending', 'confirmed', 'declined') then
    raise exception 'Estado no válido';
  end if;

  select * into guest_group
  from public.guest_groups as group_row
  where group_row.primary_guest_id = p_guest_id
     or group_row.companion_guest_id = p_guest_id
     or exists (
       select 1 from public.guest_group_members as member
       where member.guest_group_id = group_row.id
         and member.invited_guest_id = p_guest_id
     )
  order by group_row.created_at desc
  limit 1
  for update;

  if found then
    update public.guest_groups set status = p_status where id = guest_group.id;
    update public.invited_guests
    set status = p_status
    where id = guest_group.primary_guest_id or id = guest_group.companion_guest_id;
    update public.invited_guests as guest
    set status = p_status
    where guest.id in (
      select member.invited_guest_id
      from public.guest_group_members as member
      where member.guest_group_id = guest_group.id
    );
  else
    update public.invited_guests set status = p_status where id = p_guest_id;
    if not found then raise exception 'El invitado no existe'; end if;
  end if;
end;
$$;

grant execute on function public.set_guest_group_status(uuid, text) to authenticated;
revoke all on function public.set_guest_group_status(uuid, text) from public, anon;
grant execute on function public.set_invited_guest_status(uuid, text) to authenticated;
revoke all on function public.set_invited_guest_status(uuid, text) from public, anon;

create or replace function public.approve_unlisted_companion(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  guest_group public.guest_groups;
  companion_name text;
  companion_guest public.invited_guests;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin' then
    raise exception 'No autorizado';
  end if;

  select * into guest_group from public.guest_groups where id = p_group_id for update;
  if not found then raise exception 'El grupo no existe'; end if;
  if guest_group.companion_guest_id is not null then
    raise exception 'Este acompañante ya está registrado';
  end if;
  if guest_group.companion_name is null then
    raise exception 'Este grupo no tiene un acompañante pendiente';
  end if;

  companion_name := btrim(guest_group.companion_name);
  if companion_name = '' then raise exception 'El nombre del acompañante no es válido'; end if;

  select * into companion_guest from public.invited_guests where official_name = companion_name for update;

  if companion_guest.id is null then
    insert into public.invited_guests (official_name, status)
    values (companion_name, 'confirmed')
    returning * into companion_guest;
  else
    update public.invited_guests
    set status = 'confirmed'
    where id = companion_guest.id;
  end if;

  update public.guest_groups
  set companion_guest_id = companion_guest.id,
      companion_name = companion_guest.official_name,
      companion_is_unlisted = false,
      status = 'confirmed'
  where id = p_group_id;

  update public.invited_guests
  set status = 'confirmed'
  where id = guest_group.primary_guest_id or id = companion_guest.id;
end;
$$;

grant execute on function public.approve_unlisted_companion(uuid) to authenticated;
revoke all on function public.approve_unlisted_companion(uuid) from public, anon;

create or replace function public.delete_guest_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_group public.guest_groups;
  deleted_member_ids uuid[];
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin' then
    raise exception 'No autorizado';
  end if;

  select * into deleted_group from public.guest_groups where id = p_group_id for update;
  if not found then raise exception 'El grupo no existe'; end if;

  select coalesce(array_agg(member.invited_guest_id), array[]::uuid[])
  into deleted_member_ids
  from public.guest_group_members as member
  where member.guest_group_id = p_group_id;

  delete from public.guest_groups where id = p_group_id;

  update public.invited_guests as guest
  set status = 'pending'
  where guest.id = any(deleted_member_ids)
    and not exists (
      select 1 from public.guest_groups as remaining_group
      where remaining_group.primary_guest_id = guest.id
         or remaining_group.companion_guest_id = guest.id
    )
    and not exists (
      select 1 from public.guest_group_members as remaining_member
      where remaining_member.invited_guest_id = guest.id
    );

  update public.invited_guests as guest
  set status = 'pending'
  where (guest.id = deleted_group.primary_guest_id or guest.id = deleted_group.companion_guest_id)
    and not exists (
      select 1 from public.guest_groups as remaining_group
      where remaining_group.primary_guest_id = guest.id
         or remaining_group.companion_guest_id = guest.id
    );
end;
$$;

revoke all on function public.delete_guest_group(uuid) from public, anon;
grant execute on function public.delete_guest_group(uuid) to authenticated;

update public.invited_guests
set official_name = 'Shirley Soruco Soleto'
where official_name = 'Shirley'
  and not exists (select 1 from public.invited_guests where official_name = 'Shirley Soruco Soleto');

update public.invited_guests
set official_name = 'Alejandro Pedraza'
where official_name = 'Alejandro'
  and not exists (select 1 from public.invited_guests where official_name = 'Alejandro Pedraza');

update public.invited_guests
set official_name = 'Mauricio Semo Cortez'
where official_name = 'Mauricio Seno Cortez'
  and not exists (select 1 from public.invited_guests where official_name = 'Mauricio Semo Cortez');

insert into public.invited_guests (official_name) values
  ('Erick Zelada Novay'), ('Carmen Rosa Mercado Soliz'), ('Margarita Cuellar Claros'), ('Ciro Fuentes Arias'),
  ('Dulia Cuellar Claros'), ('Cesar Fuentes Cuellar'), ('Gaby Tereba Justiniano'),
  ('Alexandra Peña Mendoza'), ('Alexander Vazques Rimba'), ('Katerin Andrea Menacho'), ('Diego Tereba Justiniano'),
  ('Liliana Buripoco Gomez'), ('Jose Alberto Yanamo Apinaye'), ('Dalinda Buripoco Gomez'),
  ('Juan Pablo Ortiz'), ('Mercedes Gomez Rivero'), ('Lisbeth Camacho Souza'),
  ('Daniela Cardozo Souza'), ('Vladymir Inarra Mallo'), ('Ámbar Calvimonte'), ('Claudia Ferrufino'),
  ('Yordi'), ('Lucerito Montaño Duran'), ('Romi Ariana Guataica Suarez'),
  ('Jose Daniel Flores'), ('Anner Cardozo Suarez'), ('Pamela Suarez Cuellar'),
  ('Katy Suarez Cuellar'), ('Donny Toledo Ortiz'), ('Rafael Suarez Cuellar'), ('Gabriela Guzman Carranza'),
  ('Ramiro Manuelo'), ('Luis'), ('Gina Guzman Carranza'), ('Herman Buripoco Gomez'),
  ('Natalia Moco Suarez'), ('Shirley Soruco Soleto'), ('Monica Noza'), ('Damaris Guzman Carranza'),
  ('Rolando'), ('Arnol Guzman Carranza'), ('Anadoli Quirogas'), ('Kenyi Shiosaqui'), ('Luana Flora Añez Chávez'),
  ('Leonardo Favio Urquiza'), ('Alejandro Pedraza'), ('Ademar Cuellar Cuellar'), ('Yancara'),
  ('Jose David'), ('Gina Coimbra Cuellar'), ('Carlos Alipaz'), ('Elvira Arias'),
  ('Ciro Fuentes Cuellar'), ('Mercedes'), ('Idilio Cuellar'), ('Mauricio Semo Cortez'),
  ('Sara Ramallo'), ('Roger Cuellar Claros'), ('Roberto Sugarai'), ('Anita Suarez'), ('Nataly Cuellar'),
  ('Dayana Cuellar'), ('Reina Suarez'), ('Jesus Lavadenz'), ('Katerine Cayuba'),
  ('Lorena Fuentes Cuellar'), ('Karin Bejarano Villaroel'), ('Gildana'), ('Ronal'),
  ('Jose Luis Rivero'), ('Angela Mocoro Suarez'), ('Fernando Suarez Suarez'),
  ('Yerusa Taborga'), ('Esposo'), ('Dodamin Suarez'), ('Fernando Suarez'), ('Doli Guardia'),
  ('María Vargas'), ('Yarlene Ramallo'), ('Iris Ramallo'), ('Ruth Dennis Ramallo'),
  ('María Fernanda Saucedo'), ('María Rivero Rodriguez'), ('Jonas Suarez'), ('Gricelda'),
  ('Edson Orihuela'), ('Raquel Elizabeth Guimaraes Soruco'), ('Adalberto Solano'),
  ('Ina'), ('Adrian Escalante'), ('Adrian Suarez'), ('Abigail'), ('Melissa Melgar Mercado')
on conflict (official_name) do nothing;
