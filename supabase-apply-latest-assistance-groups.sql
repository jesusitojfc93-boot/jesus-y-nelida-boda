-- Aplica las parejas confirmadas recientes y el cupo de Yordi para Claudia.
begin;

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

do $$
declare
  pair record;
  v_primary_id uuid;
  v_companion_id uuid;
  v_primary_group public.guest_groups;
  v_companion_group public.guest_groups;
  v_herman_id uuid;
  v_mercedes_id uuid;
  v_herman_group public.guest_groups;
  v_group_id uuid;
  v_claudia_id uuid;
  v_yordi_id uuid;
begin
  for pair in
    select * from (values
      ('Dalinda Buripoco Gomez', 'Juan Pablo Ortiz'),
      ('Dulia Cuellar Claros', 'Ciro Fuentes Arias'),
      ('Luis', 'Gina Guzman Carranza'),
      ('Jesus Lavadenz', 'Katerine Cayuba'),
      ('Damaris Guzman Carranza', 'Rolando')
    ) as pairs(primary_name, companion_name)
  loop
    select id into v_primary_id from public.invited_guests where official_name = pair.primary_name for update;
    select id into v_companion_id from public.invited_guests where official_name = pair.companion_name for update;
    if v_primary_id is null or v_companion_id is null then
      raise exception 'No se encontraron ambos invitados para %', pair.primary_name;
    end if;
    if exists (select 1 from public.invited_guests where id in (v_primary_id, v_companion_id) and status <> 'confirmed') then
      raise exception 'La pareja % no está completamente confirmada', pair.primary_name;
    end if;

    select * into v_primary_group from public.guest_groups
    where primary_guest_id = v_primary_id order by created_at desc limit 1 for update;
    if not found then raise exception 'No hay grupo para %', pair.primary_name; end if;
    if v_primary_group.companion_guest_id is not null and v_primary_group.companion_guest_id <> v_companion_id then
      raise exception '% ya tiene otro acompañante', pair.primary_name;
    end if;

    if v_primary_group.companion_guest_id is distinct from v_companion_id then
      select * into v_companion_group from public.guest_groups
      where primary_guest_id = v_companion_id and companion_guest_id is null
      order by created_at desc limit 1 for update;
      if not found then raise exception 'No hay grupo individual para %', pair.companion_name; end if;
      update public.guest_groups
      set companion_guest_id = v_companion_id, companion_name = pair.companion_name,
          companion_is_unlisted = false, status = 'confirmed'
      where id = v_primary_group.id;
      delete from public.guest_groups where id = v_companion_group.id;
    end if;
  end loop;

  select id into v_herman_id from public.invited_guests where official_name = 'Herman Buripoco Gomez' for update;
  select id into v_mercedes_id from public.invited_guests where official_name = 'Mercedes Gomez Rivero' for update;
  if v_herman_id is null or v_mercedes_id is null then raise exception 'No se encontraron Herman y Mercedes Gomez'; end if;
  if exists (select 1 from public.guest_groups where primary_guest_id = v_herman_id or companion_guest_id = v_herman_id) then
    raise exception 'Herman ya pertenece a otro grupo';
  end if;
  select * into v_herman_group from public.guest_groups
  where primary_guest_id = v_mercedes_id and companion_guest_id is null
  order by created_at desc limit 1 for update;
  if not found then raise exception 'No se encontró el grupo individual de Mercedes Gomez Rivero'; end if;
  update public.guest_groups
  set primary_guest_id = v_herman_id, companion_guest_id = v_mercedes_id,
      primary_name = 'Herman Buripoco Gomez', companion_name = 'Mercedes Gomez Rivero',
      companion_is_unlisted = false, status = 'confirmed'
  where id = v_herman_group.id;
  update public.invited_guests set status = 'confirmed' where id in (v_herman_id, v_mercedes_id);

  select id into v_claudia_id from public.invited_guests where official_name = 'Claudia Ferrufino' for update;
  select id into v_yordi_id from public.invited_guests where official_name = 'Yordi' for update;
  select id into v_group_id from public.guest_groups
  where primary_guest_id = (select id from public.invited_guests where official_name = 'Vladymir Inarra Mallo')
    and companion_guest_id = (select id from public.invited_guests where official_name = 'Daniela Cardozo Souza')
    and status = 'confirmed'
  order by created_at desc limit 1 for update;
  if v_claudia_id is null or v_yordi_id is null or v_group_id is null then
    raise exception 'No se encontró el grupo de padrinos, Claudia o Yordi';
  end if;
  if exists (select 1 from public.guest_group_members where invited_guest_id = v_yordi_id and guest_group_id <> v_group_id) then
    raise exception 'Yordi ya pertenece a otro grupo';
  end if;

  update public.invited_guests set extra_guest_allowance = 1 where id = v_claudia_id;
  insert into public.guest_group_members (guest_group_id, invited_guest_id, invited_by_guest_id)
  values (v_group_id, v_yordi_id, v_claudia_id)
  on conflict (invited_guest_id) do update
  set guest_group_id = excluded.guest_group_id, invited_by_guest_id = excluded.invited_by_guest_id;
  delete from public.guest_groups where primary_guest_id = v_yordi_id and companion_guest_id is null;
end;
$$;

commit;