-- Ejecuta este archivo una sola vez para cargar los estados históricos iniciales.
create table if not exists public.wedding_attendance_seed_runs (
  seed_name text primary key,
  applied_at timestamptz not null default now()
);
alter table public.wedding_attendance_seed_runs enable row level security;

drop table if exists pg_temp.wedding_attendance_import;
create temporary table wedding_attendance_import (
  official_name text primary key,
  status text not null check (status in ('confirmed', 'pending', 'declined'))
);

insert into pg_temp.wedding_attendance_import (official_name, status) values
  ('Erick Zelada Novay', 'confirmed'), ('Carmen Rosa Mercado Soliz', 'confirmed'),
  ('Margarita Cuellar Claros', 'confirmed'), ('Ciro Fuentes Arias', 'confirmed'),
  ('Dulia Cuellar Claros', 'confirmed'), ('Cesar Fuentes Cuellar', 'confirmed'),
  ('Gaby Tereba Justiniano', 'confirmed'), ('Alexandra Peña Mendoza', 'confirmed'),
  ('Alexander Vazques Rimba', 'confirmed'), ('Katerin Andrea Menacho', 'confirmed'),
  ('Diego Tereba Justiniano', 'confirmed'),
  ('Liliana Buripoco Gomez', 'confirmed'), ('Jose Alberto Yanamo Apinaye', 'confirmed'),
  ('Dalinda Buripoco Gomez', 'confirmed'), ('Juan Pablo Ortiz', 'confirmed'),
  ('Mercedes Gomez Rivero', 'confirmed'), ('Lisbeth Camacho Souza', 'confirmed'),
  ('Daniela Cardozo Souza', 'confirmed'), ('Vladymir Inarra Mallo', 'confirmed'),
  ('Ámbar Calvimonte', 'confirmed'), ('Claudia Ferrufino', 'confirmed'),
  ('Yordi', 'confirmed'), ('Lucerito Montaño Duran', 'confirmed'),
  ('Romi Ariana Guataica Suarez', 'confirmed'), ('Jose Daniel Flores', 'confirmed'),
  ('Anner Cardozo Suarez', 'confirmed'), ('Pamela Suarez Cuellar', 'confirmed'),
  ('Katy Suarez Cuellar', 'confirmed'), ('Donny Toledo Ortiz', 'confirmed'), ('Rafael Suarez Cuellar', 'confirmed'),
  ('Gabriela Guzman Carranza', 'confirmed'), ('Ramiro Manuelo', 'confirmed'),
  ('Luis', 'confirmed'), ('Gina Guzman Carranza', 'confirmed'),
  ('Shirley Soruco Soleto', 'confirmed'), ('Monica Noza', 'confirmed'),
  ('Damaris Guzman Carranza', 'confirmed'), ('Rolando', 'confirmed'),
  ('Anadoli Quirogas', 'confirmed'), ('Kenyi Shiosaqui', 'confirmed'), ('Luana Flora Añez Chávez', 'confirmed'),
  ('Leonardo Favio Urquiza', 'confirmed'), ('Jose David', 'confirmed'),
  ('Ina', 'confirmed'), ('Ciro Fuentes Cuellar', 'declined'),
  ('Mauricio Semo Cortez', 'confirmed'), ('Jesus Lavadenz', 'confirmed'),
  ('Katerine Cayuba', 'confirmed'), ('Karin Bejarano Villaroel', 'confirmed'), ('Roberto Sugarai', 'confirmed'),
  ('Edson Orihuela', 'confirmed'), ('Raquel Elizabeth Guimaraes Soruco', 'confirmed'),
  ('Adalberto Solano', 'confirmed'), ('Adrian Escalante', 'confirmed'),
  ('Melissa Melgar Mercado', 'confirmed'),
  ('Herman Buripoco Gomez', 'confirmed'), ('Natalia Moco Suarez', 'pending'),
  ('Arnol Guzman Carranza', 'pending'), ('Alejandro Pedraza', 'pending'),
  ('Ademar Cuellar Cuellar', 'pending'), ('Yancara', 'pending'),
  ('Gina Coimbra Cuellar', 'pending'), ('Carlos Alipaz', 'pending'),
  ('Elvira Arias', 'pending'), ('Mercedes', 'pending'), ('Idilio Cuellar', 'pending'),
  ('Sara Ramallo', 'pending'), ('Nataly Cuellar', 'pending'), ('Reina Suarez', 'pending'),
  ('Lorena Fuentes Cuellar', 'pending'), ('Gildana', 'pending'), ('Ronal', 'pending'),
  ('Dodamin Suarez', 'pending'), ('Yarlene Ramallo', 'pending'),
  ('Ruth Dennis Ramallo', 'pending'), ('María Fernanda Saucedo', 'pending'),
  ('Gricelda', 'pending');

do $$
begin
  if exists (select 1 from public.wedding_attendance_seed_runs where seed_name = 'initial-v1') then
    raise notice 'La carga inicial ya se aplicó; no se modificaron respuestas.';
    return;
  end if;

  update public.invited_guests as guest
  set status = 'pending'
  where not exists (
    select 1 from pg_temp.wedding_attendance_import as roster
    where roster.official_name = guest.official_name
  );

  update public.invited_guests as guest
  set status = roster.status
  from pg_temp.wedding_attendance_import as roster
  where guest.official_name = roster.official_name;

  update public.guest_groups as guest_group
  set status = case when exists (
    select 1
    from public.invited_guests as guest
    join pg_temp.wedding_attendance_import as roster on roster.official_name = guest.official_name
    where roster.status = 'confirmed'
      and (guest.id = guest_group.primary_guest_id or guest.id = guest_group.companion_guest_id)
  ) then 'confirmed'
  when exists (
    select 1
    from public.invited_guests as guest
    join pg_temp.wedding_attendance_import as roster on roster.official_name = guest.official_name
    where roster.status = 'declined'
      and (guest.id = guest_group.primary_guest_id or guest.id = guest_group.companion_guest_id)
  ) then 'declined' else 'pending' end;

  insert into public.guest_groups (primary_guest_id, primary_name, status)
  select guest.id, guest.official_name, 'confirmed'
  from public.invited_guests as guest
  join pg_temp.wedding_attendance_import as roster on roster.official_name = guest.official_name
  where roster.status = 'confirmed'
    and guest.official_name not in (
      'Carmen Rosa Mercado Soliz', 'Gaby Tereba Justiniano', 'Alexandra Peña Mendoza',
      'Liliana Buripoco Gomez', 'Daniela Cardozo Souza', 'Gabriela Guzman Carranza', 'Roberto Sugarai',
      'Raquel Elizabeth Guimaraes Soruco', 'Melissa Melgar Mercado',
      'Claudia Ferrufino', 'Ámbar Calvimonte', 'Lucerito Montaño Duran',
      'Mercedes Gomez Rivero', 'Juan Pablo Ortiz', 'Ciro Fuentes Arias',
      'Gina Guzman Carranza', 'Katerine Cayuba', 'Rolando', 'Yordi', 'Katerin Andrea Menacho',
      'Donny Toledo Ortiz', 'Ina', 'Jose Daniel Flores', 'Luana Flora Añez Chávez'
    )
    and not exists (
      select 1 from public.guest_groups as guest_group
      where guest_group.primary_guest_id = guest.id or guest_group.companion_guest_id = guest.id
    );

  update public.guest_groups as primary_group
  set companion_guest_id = companion_guest.id,
      companion_name = companion_guest.official_name,
      companion_is_unlisted = false
  from (values
    ('Erick Zelada Novay', 'Carmen Rosa Mercado Soliz'),
    ('Adalberto Solano', 'Gaby Tereba Justiniano'),
    ('Diego Tereba Justiniano', 'Alexandra Peña Mendoza'),
    ('Jose Alberto Yanamo Apinaye', 'Liliana Buripoco Gomez'),
    ('Vladymir Inarra Mallo', 'Daniela Cardozo Souza'),
    ('Ramiro Manuelo', 'Gabriela Guzman Carranza'),
    ('Edson Orihuela', 'Raquel Elizabeth Guimaraes Soruco'),
    ('Adrian Escalante', 'Melissa Melgar Mercado'),
    ('Karin Bejarano Villaroel', 'Roberto Sugarai'),
    ('Herman Buripoco Gomez', 'Mercedes Gomez Rivero'),
    ('Dalinda Buripoco Gomez', 'Juan Pablo Ortiz'),
    ('Dulia Cuellar Claros', 'Ciro Fuentes Arias'),
    ('Luis', 'Gina Guzman Carranza'),
    ('Jesus Lavadenz', 'Katerine Cayuba'),
    ('Damaris Guzman Carranza', 'Rolando'),
    ('Alexander Vazques Rimba', 'Katerin Andrea Menacho'),
    ('Katy Suarez Cuellar', 'Donny Toledo Ortiz'),
    ('Jose David', 'Ina'),
    ('Romi Ariana Guataica Suarez', 'Jose Daniel Flores'),
    ('Kenyi Shiosaqui', 'Luana Flora Añez Chávez')
  ) as pairs(primary_name, companion_name)
  join public.invited_guests as primary_guest on primary_guest.official_name = pairs.primary_name
  join public.invited_guests as companion_guest on companion_guest.official_name = pairs.companion_name
  where primary_group.primary_guest_id = primary_guest.id
    and primary_group.companion_guest_id is null;

  update public.invited_guests
  set extra_guest_allowance = 3
  where official_name in ('Daniela Cardozo Souza', 'Vladymir Inarra Mallo');

  update public.invited_guests
  set extra_guest_allowance = 1
  where official_name = 'Claudia Ferrufino';

  insert into public.guest_group_members (guest_group_id, invited_guest_id, invited_by_guest_id)
  select guest_group.id, member.id, daniela.id
  from public.guest_groups as guest_group
  join public.invited_guests as vlady on vlady.official_name = 'Vladymir Inarra Mallo'
  join public.invited_guests as daniela on daniela.official_name = 'Daniela Cardozo Souza'
  join public.invited_guests as member on member.official_name in (
    'Claudia Ferrufino', 'Ámbar Calvimonte', 'Lucerito Montaño Duran'
  )
  where guest_group.primary_guest_id = vlady.id
    and guest_group.companion_guest_id = daniela.id
  on conflict (invited_guest_id) do nothing;

  insert into public.guest_group_members (guest_group_id, invited_guest_id, invited_by_guest_id)
  select guest_group.id, yordi.id, claudia.id
  from public.guest_groups as guest_group
  join public.invited_guests as vlady on vlady.official_name = 'Vladymir Inarra Mallo'
  join public.invited_guests as daniela on daniela.official_name = 'Daniela Cardozo Souza'
  join public.invited_guests as claudia on claudia.official_name = 'Claudia Ferrufino'
  join public.invited_guests as yordi on yordi.official_name = 'Yordi'
  where guest_group.primary_guest_id = vlady.id
    and guest_group.companion_guest_id = daniela.id
  on conflict (invited_guest_id) do nothing;

  insert into public.wedding_attendance_seed_runs (seed_name) values ('initial-v1');
end;
$$;