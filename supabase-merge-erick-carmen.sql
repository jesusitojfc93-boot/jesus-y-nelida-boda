-- Une la confirmación individual de Carmen Rosa al grupo de Erick.
-- Se puede ejecutar más de una vez; solo elimina la fila individual de Carmen.
begin;

do $$
declare
  erick_id uuid;
  carmen_id uuid;
  erick_group public.guest_groups;
  carmen_group public.guest_groups;
begin
  select id into erick_id
  from public.invited_guests
  where official_name = 'Erick Zelada Novay'
  for update;

  select id into carmen_id
  from public.invited_guests
  where official_name = 'Carmen Rosa Mercado Soliz'
  for update;

  if erick_id is null or carmen_id is null then
    raise exception 'No se encontraron los dos invitados; no se hicieron cambios';
  end if;

  select * into erick_group
  from public.guest_groups
  where primary_guest_id = erick_id
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'No se encontró la confirmación de Erick; no se hicieron cambios';
  end if;

  if erick_group.companion_guest_id is not null and erick_group.companion_guest_id <> carmen_id then
    raise exception 'Erick ya tiene otro acompañante; no se hicieron cambios';
  end if;

  if erick_group.companion_guest_id = carmen_id then
    delete from public.guest_groups
    where primary_guest_id = carmen_id
      and companion_guest_id is null;
  else
    select * into carmen_group
    from public.guest_groups
    where primary_guest_id = carmen_id
      and companion_guest_id is null
    order by created_at desc
    limit 1
    for update;

    if not found then
      raise exception 'No se encontró la confirmación individual de Carmen; no se hicieron cambios';
    end if;

    update public.guest_groups
    set companion_guest_id = carmen_id,
        companion_name = 'Carmen Rosa Mercado Soliz',
        companion_is_unlisted = false
    where id = erick_group.id;

    delete from public.guest_groups where id = carmen_group.id;
  end if;

  update public.invited_guests
  set status = 'confirmed'
  where id = erick_id or id = carmen_id;
end;
$$;

commit;