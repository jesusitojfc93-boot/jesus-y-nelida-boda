-- Registra a Roberto Sugarai como invitado confirmado y acompañante de Karin.
begin;

do $$
declare
  v_karin_id uuid;
  v_roberto_id uuid;
  v_karin_group public.guest_groups;
begin
  select id into v_karin_id
  from public.invited_guests
  where official_name = 'Karin Bejarano Villaroel'
  for update;

  if v_karin_id is null then
    raise exception 'No se encontró a Karin; no se hicieron cambios';
  end if;

  insert into public.invited_guests (official_name, status)
  values ('Roberto Sugarai', 'confirmed')
  on conflict (official_name) do update set status = 'confirmed'
  returning id into v_roberto_id;

  select * into v_karin_group
  from public.guest_groups
  where primary_guest_id = v_karin_id
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'No se encontró el grupo de Karin; no se hicieron cambios';
  end if;

  if v_karin_group.companion_guest_id is not null
     and v_karin_group.companion_guest_id <> v_roberto_id then
    raise exception 'Karin ya tiene otro acompañante; no se hicieron cambios';
  end if;

  update public.guest_groups
  set companion_guest_id = v_roberto_id,
      companion_name = 'Roberto Sugarai',
      companion_is_unlisted = false,
      status = 'confirmed'
  where id = v_karin_group.id;

  update public.invited_guests
  set status = 'confirmed'
  where id = v_karin_id or id = v_roberto_id;
end;
$$;

commit;