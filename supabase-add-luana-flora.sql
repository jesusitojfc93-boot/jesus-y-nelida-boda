-- Registra y confirma a Luana Flora Añez Chávez con Kenyi Shiosaqui.
begin;

do $$
declare
  v_kenyi_id uuid;
  v_luana_id uuid;
  v_kenyi_group public.guest_groups;
begin
  select id into v_kenyi_id
  from public.invited_guests
  where official_name = 'Kenyi Shiosaqui'
  for update;

  if v_kenyi_id is null then
    raise exception 'No se encontró a Kenyi Shiosaqui; no se hicieron cambios';
  end if;

  insert into public.invited_guests (official_name, status)
  values ('Luana Flora Añez Chávez', 'confirmed')
  on conflict (official_name) do update set status = 'confirmed'
  returning id into v_luana_id;

  select * into v_kenyi_group
  from public.guest_groups
  where primary_guest_id = v_kenyi_id
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'No se encontró el grupo de Kenyi; no se hicieron cambios';
  end if;

  if v_kenyi_group.companion_guest_id is not null
     and v_kenyi_group.companion_guest_id <> v_luana_id then
    raise exception 'Kenyi ya tiene otro acompañante; no se hicieron cambios';
  end if;

  if exists (
    select 1 from public.guest_groups
    where (primary_guest_id = v_luana_id or companion_guest_id = v_luana_id)
      and id <> v_kenyi_group.id
  ) then
    raise exception 'Luana ya pertenece a otro grupo; no se hicieron cambios';
  end if;

  update public.guest_groups
  set companion_guest_id = v_luana_id,
      companion_name = 'Luana Flora Añez Chávez',
      companion_is_unlisted = false,
      status = 'confirmed'
  where id = v_kenyi_group.id;

  update public.invited_guests
  set status = 'confirmed'
  where id in (v_kenyi_id, v_luana_id);
end;
$$;

commit;