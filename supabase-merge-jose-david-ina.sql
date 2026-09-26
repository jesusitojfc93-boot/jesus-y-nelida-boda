-- Agrupa a Jose David con Ina; Jose Daniel Flores permanece aparte.
begin;

do $$
declare
  v_jose_id uuid;
  v_ina_id uuid;
  v_jose_group public.guest_groups;
  v_ina_group public.guest_groups;
begin
  select id into v_jose_id
  from public.invited_guests
  where official_name = 'Jose David'
  for update;

  select id into v_ina_id
  from public.invited_guests
  where official_name = 'Ina'
  for update;

  if v_jose_id is null or v_ina_id is null then
    raise exception 'No se encontraron Jose David e Ina; no se hicieron cambios';
  end if;

  if exists (
    select 1 from public.invited_guests
    where id in (v_jose_id, v_ina_id) and status <> 'confirmed'
  ) then
    raise exception 'Uno de los dos invitados no está confirmado; no se hicieron cambios';
  end if;

  select * into v_jose_group
  from public.guest_groups
  where primary_guest_id = v_jose_id
  order by created_at desc
  limit 1
  for update;
  if not found then raise exception 'No se encontró el grupo de Jose David'; end if;

  if v_jose_group.companion_guest_id is not null and v_jose_group.companion_guest_id <> v_ina_id then
    raise exception 'Jose David ya tiene otro acompañante';
  end if;

  if v_jose_group.companion_guest_id is distinct from v_ina_id then
    select * into v_ina_group
    from public.guest_groups
    where primary_guest_id = v_ina_id and companion_guest_id is null
    order by created_at desc
    limit 1
    for update;
    if not found then raise exception 'No se encontró el grupo individual de Ina'; end if;

    update public.guest_groups
    set companion_guest_id = v_ina_id,
        companion_name = 'Ina',
        companion_is_unlisted = false,
        status = 'confirmed'
    where id = v_jose_group.id;

    delete from public.guest_groups where id = v_ina_group.id;
  end if;

  update public.invited_guests
  set status = 'confirmed'
  where id in (v_jose_id, v_ina_id);
end;
$$;

commit;

-- Une a Romi Ariana Guataica con Jose Daniel Flores.
begin;

do $$
declare
  v_primary_id uuid;
  v_companion_id uuid;
  v_primary_group public.guest_groups;
  v_companion_group public.guest_groups;
begin
  select id into v_primary_id
  from public.invited_guests
  where official_name = 'Romi Ariana Guataica Suarez'
  for update;

  select id into v_companion_id
  from public.invited_guests
  where official_name = 'Jose Daniel Flores'
  for update;

  if v_primary_id is null or v_companion_id is null then
    raise exception 'No se encontraron Ariana y Jose Daniel; no se hicieron cambios';
  end if;
  if exists (
    select 1 from public.invited_guests
    where id in (v_primary_id, v_companion_id) and status <> 'confirmed'
  ) then
    raise exception 'Ariana y Jose Daniel deben estar confirmados';
  end if;

  select * into v_primary_group from public.guest_groups
  where primary_guest_id = v_primary_id order by created_at desc limit 1 for update;
  if not found then raise exception 'No se encontró el grupo de Ariana'; end if;
  if v_primary_group.companion_guest_id is not null and v_primary_group.companion_guest_id <> v_companion_id then
    raise exception 'Ariana ya tiene otro acompañante';
  end if;

  if v_primary_group.companion_guest_id is distinct from v_companion_id then
    select * into v_companion_group from public.guest_groups
    where primary_guest_id = v_companion_id and companion_guest_id is null
    order by created_at desc limit 1 for update;
    if not found then raise exception 'No se encontró el grupo individual de Jose Daniel'; end if;
    update public.guest_groups
    set companion_guest_id = v_companion_id,
        companion_name = 'Jose Daniel Flores',
        companion_is_unlisted = false,
        status = 'confirmed'
    where id = v_primary_group.id;
    delete from public.guest_groups where id = v_companion_group.id;
  end if;

  update public.invited_guests set status = 'confirmed'
  where id in (v_primary_id, v_companion_id);
end;
$$;

commit;