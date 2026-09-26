-- Agrupa catorce parejas confirmadas que estaban registradas por separado.
begin;

do $$
declare
  pair record;
  v_primary_guest_id uuid;
  v_companion_guest_id uuid;
  v_primary_group public.guest_groups;
  v_companion_group public.guest_groups;
begin
  for pair in
    select * from (values
      ('Adalberto Solano', 'Gaby Tereba Justiniano'),
      ('Diego Tereba Justiniano', 'Alexandra Peña Mendoza'),
      ('Jose Alberto Yanamo Apinaye', 'Liliana Buripoco Gomez'),
      ('Vladymir Inarra Mallo', 'Daniela Cardozo Souza'),
      ('Ramiro Manuelo', 'Gabriela Guzman Carranza'),
      ('Edson Orihuela', 'Raquel Elizabeth Guimaraes Soruco'),
      ('Adrian Escalante', 'Melissa Melgar Mercado'),
      ('Dalinda Buripoco Gomez', 'Juan Pablo Ortiz'),
      ('Dulia Cuellar Claros', 'Ciro Fuentes Arias'),
      ('Luis', 'Gina Guzman Carranza'),
      ('Jesus Lavadenz', 'Katerine Cayuba'),
      ('Damaris Guzman Carranza', 'Rolando'),
      ('Jose David', 'Ina'),
      ('Romi Ariana Guataica Suarez', 'Jose Daniel Flores')
    ) as pairs(primary_name, companion_name)
  loop
    select guest.id into v_primary_guest_id
    from public.invited_guests as guest
    where guest.official_name = pair.primary_name
    for update;

    select guest.id into v_companion_guest_id
    from public.invited_guests as guest
    where guest.official_name = pair.companion_name
    for update;

    if v_primary_guest_id is null or v_companion_guest_id is null then
      raise exception 'No se encontraron ambos invitados para %; no se hicieron cambios', pair.primary_name;
    end if;

    select * into v_primary_group
    from public.guest_groups as guest_group
    where guest_group.primary_guest_id = v_primary_guest_id
    order by guest_group.created_at desc
    limit 1
    for update;

    if not found then
      raise exception 'No se encontró el grupo de %; no se hicieron cambios', pair.primary_name;
    end if;

    if v_primary_group.companion_guest_id is not null
       and v_primary_group.companion_guest_id <> v_companion_guest_id then
      raise exception '% ya tiene otro acompañante; no se hicieron cambios', pair.primary_name;
    end if;

    if v_primary_group.companion_guest_id is distinct from v_companion_guest_id then
      select * into v_companion_group
      from public.guest_groups as guest_group
      where guest_group.primary_guest_id = v_companion_guest_id
        and guest_group.companion_guest_id is null
      order by guest_group.created_at desc
      limit 1
      for update;

      if not found then
        raise exception 'No se encontró el grupo individual de %; no se hicieron cambios', pair.companion_name;
      end if;

      update public.guest_groups as guest_group
      set companion_guest_id = v_companion_guest_id,
          companion_name = pair.companion_name,
          companion_is_unlisted = false
      where guest_group.id = v_primary_group.id;

      delete from public.guest_groups as guest_group where guest_group.id = v_companion_group.id;
    end if;

    update public.invited_guests as guest
    set status = 'confirmed'
    where guest.id = v_primary_guest_id or guest.id = v_companion_guest_id;
  end loop;
end;
$$;

commit;