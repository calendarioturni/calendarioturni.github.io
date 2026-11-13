begin;

create or replace function public.turni_prenota_admin(
  p_token text,
  p_turno uuid,
  p_utente uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_posti integer;
  v_prenotazione uuid;
begin
  perform public.turni_verifica_sessione(p_token, 'admin');

  select t.posti into v_posti
  from public.turni as t
  where t.id = p_turno
  for update;

  if not found then
    raise exception 'Turno non trovato.';
  end if;

  perform 1
  from public.utenti as u
  where u.id = p_utente and u.attivo is true
  for share;

  if not found then
    raise exception 'Collaboratore non trovato o non attivo.';
  end if;

  if exists (
    select 1 from public.prenotazioni as p
    where p.turno_id = p_turno and p.utente_id = p_utente
  ) then
    raise exception 'Il collaboratore è già prenotato per questo turno.';
  end if;

  if (
    select count(*) from public.prenotazioni as p where p.turno_id = p_turno
  ) >= v_posti then
    raise exception 'Turno completo.';
  end if;

  insert into public.prenotazioni (turno_id, utente_id)
  values (p_turno, p_utente)
  returning id into v_prenotazione;

  return v_prenotazione;
exception
  when unique_violation then
    raise exception 'Il collaboratore è già prenotato per questo turno.';
end;
$$;

revoke all on function public.turni_prenota_admin(text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.turni_prenota_admin(text, uuid, uuid)
  to anon;
notify pgrst, 'reload schema';

commit;
