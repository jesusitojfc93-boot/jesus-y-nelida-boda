-- Confirma a Herman Buripoco y lo une con Mercedes Gomez Rivero.
begin;

do $$
declare
  v_herman public.invited_guests;
  v_mercedes public.invited_guests;
  v_group public.guest_groups;
begin
  select * into v_herman
  from public.invited_guests
  where official_name = 'Herman Buripoco Gomez'
  for update;

  select * into v_mercedes
  from public.invited_guests
  where official_name = 'Mercedes Gomez Rivero'
  for update;

  if v_herman.id is null or v_mercedes.id is null then
    raise exception 'No se encontraron ambos invitados; no se hicieron cambios';
  end if;
  if v_mercedes.status <> 'confirmed' then
    raise exception 'Mercedes Gomez Rivero ya no está confirmada; no se hicieron cambios';
  end if;

  select * into v_group
  from public.guest_groups
  where primary_guest_id = v_herman.id
    and companion_guest_id = v_mercedes.id
  order by created_at desc
  limit 1
  for update;

  if not found then
    if exists (
      select 1 from public.guest_groups
      where primary_guest_id = v_herman.id or companion_guest_id = v_herman.id
    ) then
      raise exception 'Herman ya pertenece a otro grupo; no se hicieron cambios';
    end if;

    select * into v_group
    from public.guest_groups
    where primary_guest_id = v_mercedes.id
      and companion_guest_id is null
    order by created_at desc
    limit 1
    for update;

    if not found then
      raise exception 'No se encontró el grupo individual de Mercedes; no se hicieron cambios';
    end if;

    update public.guest_groups
    set primary_guest_id = v_herman.id,
        companion_guest_id = v_mercedes.id,
        primary_name = v_herman.official_name,
        companion_name = v_mercedes.official_name,
        companion_is_unlisted = false,
        status = 'confirmed'
    where id = v_group.id;
  else
    update public.guest_groups set status = 'confirmed' where id = v_group.id;
  end if;

  update public.invited_guests
  set status = 'confirmed'
  where id in (v_herman.id, v_mercedes.id);
end;
$$;

commit;