-- Asocia los tres invitados de Daniela al grupo de Daniela y Vladymir.
begin;

alter table public.invited_guests
  add column if not exists extra_guest_allowance smallint not null default 0;

create table if not exists public.guest_group_members (
  guest_group_id uuid not null references public.guest_groups(id) on delete cascade,
  invited_guest_id uuid not null unique references public.invited_guests(id),
  invited_by_guest_id uuid not null references public.invited_guests(id),
  created_at timestamptz not null default now(),
  primary key (guest_group_id, invited_guest_id)
);

alter table public.guest_group_members enable row level security;
drop policy if exists "Admins can manage guest group members" on public.guest_group_members;
create policy "Admins can manage guest group members"
  on public.guest_group_members for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

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

  if not found or v_allowance < 1 then
    raise exception 'Este invitado no tiene cupos adicionales';
  end if;

  if not exists (
    select 1 from public.guest_groups as guest_group
    where guest_group.id = new.guest_group_id
      and (guest_group.primary_guest_id = new.invited_by_guest_id
        or guest_group.companion_guest_id = new.invited_by_guest_id)
  ) then
    raise exception 'El padrino debe pertenecer al grupo';
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
  v_group public.guest_groups;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin' then raise exception 'No autorizado'; end if;
  if p_status is null or p_status not in ('pending', 'confirmed', 'declined') then raise exception 'Estado no válido'; end if;
  select * into v_group from public.guest_groups where id = p_group_id for update;
  if not found then raise exception 'El grupo no existe'; end if;

  update public.guest_groups set status = p_status where id = p_group_id;
  update public.invited_guests as guest
  set status = p_status
  where guest.id = v_group.primary_guest_id
     or guest.id = v_group.companion_guest_id
     or guest.id in (select invited_guest_id from public.guest_group_members where guest_group_id = p_group_id);
end;
$$;
revoke all on function public.set_guest_group_status(uuid, text) from public, anon;
grant execute on function public.set_guest_group_status(uuid, text) to authenticated;

create or replace function public.set_invited_guest_status(p_guest_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.guest_groups;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin' then raise exception 'No autorizado'; end if;
  if p_status is null or p_status not in ('pending', 'confirmed', 'declined') then raise exception 'Estado no válido'; end if;

  select * into v_group
  from public.guest_groups as guest_group
  where guest_group.primary_guest_id = p_guest_id
     or guest_group.companion_guest_id = p_guest_id
     or exists (
       select 1 from public.guest_group_members as member
       where member.guest_group_id = guest_group.id and member.invited_guest_id = p_guest_id
     )
  order by guest_group.created_at desc
  limit 1
  for update;

  if found then
    update public.guest_groups set status = p_status where id = v_group.id;
    update public.invited_guests as guest
    set status = p_status
    where guest.id = v_group.primary_guest_id
       or guest.id = v_group.companion_guest_id
       or guest.id in (select invited_guest_id from public.guest_group_members where guest_group_id = v_group.id);
  else
    update public.invited_guests set status = p_status where id = p_guest_id;
    if not found then raise exception 'El invitado no existe'; end if;
  end if;
end;
$$;
revoke all on function public.set_invited_guest_status(uuid, text) from public, anon;
grant execute on function public.set_invited_guest_status(uuid, text) to authenticated;

create or replace function public.delete_guest_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.guest_groups;
  v_member_ids uuid[];
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin' then raise exception 'No autorizado'; end if;
  select * into v_group from public.guest_groups where id = p_group_id for update;
  if not found then raise exception 'El grupo no existe'; end if;
  select coalesce(array_agg(invited_guest_id), array[]::uuid[]) into v_member_ids
  from public.guest_group_members where guest_group_id = p_group_id;

  delete from public.guest_groups where id = p_group_id;

  update public.invited_guests as guest
  set status = 'pending'
  where (guest.id = v_group.primary_guest_id or guest.id = v_group.companion_guest_id or guest.id = any(v_member_ids))
    and not exists (
      select 1 from public.guest_groups as remaining_group
      where remaining_group.primary_guest_id = guest.id or remaining_group.companion_guest_id = guest.id
    )
    and not exists (
      select 1 from public.guest_group_members as remaining_member
      where remaining_member.invited_guest_id = guest.id
    );
end;
$$;
revoke all on function public.delete_guest_group(uuid) from public, anon;
grant execute on function public.delete_guest_group(uuid) to authenticated;

insert into public.invited_guests (official_name, status) values
  ('Adrian Suarez', 'pending'), ('Abigail', 'pending')
on conflict (official_name) do nothing;

do $$
declare
  v_vlady_id uuid;
  v_daniela_id uuid;
  v_group_id uuid;
  v_member_ids uuid[];
begin
  select id into v_vlady_id
  from public.invited_guests
  where official_name = 'Vladymir Inarra Mallo'
  for update;

  select id into v_daniela_id
  from public.invited_guests
  where official_name = 'Daniela Cardozo Souza'
  for update;

  if v_vlady_id is null or v_daniela_id is null then
    raise exception 'No se encontraron Daniela y Vladymir; no se hicieron cambios';
  end if;

  select id into v_group_id
  from public.guest_groups
  where primary_guest_id = v_vlady_id
    and companion_guest_id = v_daniela_id
    and status = 'confirmed'
  order by created_at desc
  limit 1
  for update;

  if v_group_id is null then
    raise exception 'No se encontró el grupo confirmado de Daniela y Vladymir; no se hicieron cambios';
  end if;

  select array_agg(id order by official_name) into v_member_ids
  from public.invited_guests
  where official_name in ('Claudia Ferrufino', 'Ámbar Calvimonte', 'Lucerito Montaño Duran');

  if coalesce(array_length(v_member_ids, 1), 0) <> 3 then
    raise exception 'No se encontraron los tres invitados de Daniela; no se hicieron cambios';
  end if;

  if exists (
    select 1 from public.guest_group_members as member
    where member.invited_guest_id = any(v_member_ids)
      and (member.guest_group_id <> v_group_id or member.invited_by_guest_id <> v_daniela_id)
  ) then
    raise exception 'Uno de los invitados ya pertenece a otro grupo; no se hicieron cambios';
  end if;

  if exists (
    select 1 from public.guest_groups as guest_group
    where (guest_group.primary_guest_id = any(v_member_ids)
        or guest_group.companion_guest_id = any(v_member_ids))
      and guest_group.companion_guest_id is not null
  ) then
    raise exception 'Uno de los invitados ya tiene acompañantes; no se hicieron cambios';
  end if;

  update public.invited_guests
  set extra_guest_allowance = 3, status = 'confirmed'
  where id = v_daniela_id or id = v_vlady_id;

  update public.invited_guests
  set status = 'confirmed'
  where id = any(v_member_ids);

  insert into public.guest_group_members (guest_group_id, invited_guest_id, invited_by_guest_id)
  select v_group_id, members.member_id, v_daniela_id
  from unnest(v_member_ids) as members(member_id)
  on conflict (invited_guest_id) do update
  set guest_group_id = excluded.guest_group_id,
      invited_by_guest_id = excluded.invited_by_guest_id;

  delete from public.guest_groups
  where primary_guest_id = any(v_member_ids)
    and companion_guest_id is null;
end;
$$;

commit;