-- Registra y confirma a Katerin Andrea Menacho con Alexander Vazques Rimba.
begin;

do $$
declare
  v_alexander_id uuid;
  v_katerin_id uuid;
  v_alexander_group public.guest_groups;
begin
  select id into v_alexander_id
  from public.invited_guests
  where official_name = 'Alexander Vazques Rimba'
  for update;

  if v_alexander_id is null then
    raise exception 'No se encontró a Alexander Vazques Rimba; no se hicieron cambios';
  end if;

  insert into public.invited_guests (official_name, status)
  values ('Katerin Andrea Menacho', 'confirmed')
  on conflict (official_name) do update set status = 'confirmed'
  returning id into v_katerin_id;

  select * into v_alexander_group
  from public.guest_groups
  where primary_guest_id = v_alexander_id
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'No se encontró el grupo de Alexander; no se hicieron cambios';
  end if;

  if v_alexander_group.companion_guest_id is not null
     and v_alexander_group.companion_guest_id <> v_katerin_id then
    raise exception 'Alexander ya tiene otro acompañante; no se hicieron cambios';
  end if;

  if exists (
    select 1 from public.guest_groups
    where (primary_guest_id = v_katerin_id or companion_guest_id = v_katerin_id)
      and id <> v_alexander_group.id
  ) then
    raise exception 'Katerin ya pertenece a otro grupo; no se hicieron cambios';
  end if;

  update public.guest_groups
  set companion_guest_id = v_katerin_id,
      companion_name = 'Katerin Andrea Menacho',
      companion_is_unlisted = false,
      status = 'confirmed'
  where id = v_alexander_group.id;

  update public.invited_guests
  set status = 'confirmed'
  where id in (v_alexander_id, v_katerin_id);
end;
$$;

commit;