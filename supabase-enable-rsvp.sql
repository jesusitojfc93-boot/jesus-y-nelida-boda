-- Restaura el RPC usado por el formulario público de confirmación.
begin;

drop function if exists public.confirm_guest_group(uuid, text, uuid, text);
drop function if exists public.confirm_guest_group(uuid, text, uuid, text, boolean);

create function public.confirm_guest_group(
  p_primary_id uuid,
  p_primary_name text,
  p_companion_id uuid default null,
  p_companion_name text default null,
  p_companion_is_unlisted boolean default false
)
returns public.guest_groups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_primary public.invited_guests;
  v_companion public.invited_guests;
  v_group public.guest_groups;
begin
  if (now() at time zone 'America/La_Paz')::date > date '2026-09-30' then
    raise exception 'El plazo para confirmar asistencia ya finalizó';
  end if;

  select * into v_primary
  from public.invited_guests
  where id = p_primary_id
  for update;
  if v_primary.id is null then raise exception 'El invitado principal no existe'; end if;
  if v_primary.status <> 'pending' then raise exception 'El invitado principal ya tiene una respuesta'; end if;
  if p_primary_name is null or btrim(p_primary_name) = '' then raise exception 'El nombre principal es obligatorio'; end if;

  if p_companion_id is not null then
    if p_companion_id = p_primary_id then raise exception 'El acompañante debe ser diferente'; end if;
    select * into v_companion
    from public.invited_guests
    where id = p_companion_id
    for update;
    if v_companion.id is null then raise exception 'El acompañante no existe'; end if;
    if v_companion.status <> 'pending' then raise exception 'El acompañante ya tiene una respuesta'; end if;
    if p_companion_name is null or btrim(p_companion_name) = '' then raise exception 'Falta el nombre del acompañante'; end if;
  elsif p_companion_is_unlisted and (p_companion_name is null or btrim(p_companion_name) = '') then
    raise exception 'Falta el nombre del acompañante';
  end if;

  insert into public.guest_groups (
    primary_guest_id, companion_guest_id, primary_name, companion_name,
    companion_is_unlisted, status
  )
  values (
    p_primary_id, p_companion_id, btrim(p_primary_name),
    nullif(btrim(p_companion_name), ''), p_companion_is_unlisted, 'confirmed'
  )
  returning * into v_group;

  update public.invited_guests
  set status = 'confirmed'
  where id = p_primary_id or id = p_companion_id;

  return v_group;
end;
$$;

grant execute on function public.confirm_guest_group(uuid, text, uuid, text, boolean) to anon, authenticated;

commit;