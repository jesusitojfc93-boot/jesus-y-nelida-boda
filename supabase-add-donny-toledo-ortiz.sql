-- Registra y confirma a Donny Toledo Ortiz con Katy Suarez Cuellar.
begin;

do $$
declare
  v_katy_id uuid;
  v_donny_id uuid;
  v_katy_group public.guest_groups;
begin
  select id into v_katy_id
  from public.invited_guests
  where official_name = 'Katy Suarez Cuellar'
  for update;

  if v_katy_id is null then
    raise exception 'No se encontró a Katy Suarez Cuellar; no se hicieron cambios';
  end if;

  insert into public.invited_guests (official_name, status)
  values ('Donny Toledo Ortiz', 'confirmed')
  on conflict (official_name) do update set status = 'confirmed'
  returning id into v_donny_id;

  select * into v_katy_group
  from public.guest_groups
  where primary_guest_id = v_katy_id
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'No se encontró el grupo de Katy; no se hicieron cambios';
  end if;

  if v_katy_group.companion_guest_id is not null
     and v_katy_group.companion_guest_id <> v_donny_id then
    raise exception 'Katy ya tiene otro acompañante; no se hicieron cambios';
  end if;

  if exists (
    select 1 from public.guest_groups
    where (primary_guest_id = v_donny_id or companion_guest_id = v_donny_id)
      and id <> v_katy_group.id
  ) then
    raise exception 'Donny ya pertenece a otro grupo; no se hicieron cambios';
  end if;

  update public.guest_groups
  set companion_guest_id = v_donny_id,
      companion_name = 'Donny Toledo Ortiz',
      companion_is_unlisted = false,
      status = 'confirmed'
  where id = v_katy_group.id;

  update public.invited_guests
  set status = 'confirmed'
  where id in (v_katy_id, v_donny_id);
end;
$$;

commit;