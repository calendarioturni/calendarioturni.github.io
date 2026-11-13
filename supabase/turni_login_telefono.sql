begin;

-- The RPC keeps its current parameter name so PostgREST callers can migrate.
-- p_pin now receives the collaborator's phone number.
create or replace function public.turni_login_utente(
  p_nome text,
  p_cognome text,
  p_pin text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nome text := lower(btrim(coalesce(p_nome, '')));
  v_cognome text := lower(btrim(coalesce(p_cognome, '')));
  v_telefono text := regexp_replace(coalesce(p_pin, ''), '[^0-9]', '', 'g');
  v_match record;
  v_token text;
  v_errore constant jsonb := '{"errore":"Accesso non riuscito. Verifica nome, cognome e numero di telefono oppure riprova tra 15 minuti."}'::jsonb;
begin
  if v_nome = '' or v_cognome = '' or v_telefono !~ '^[0-9]{6,15}$' then
    return v_errore;
  end if;

  if not coalesce(public.turni_limita_accessi('u:' || v_nome || ':' || v_cognome), false) then
    return v_errore;
  end if;

  -- Accept the local Italian mobile number with or without the country prefix.
  v_telefono := regexp_replace(v_telefono, '^(0039|39)(3[0-9]{9})$', '\2');

  begin
    select u.id, u.nome, u.cognome into strict v_match
    from public.utenti as u
    where u.attivo is true
      and lower(btrim(u.nome)) = v_nome
      and lower(btrim(u.cognome)) = v_cognome
      and regexp_replace(
        regexp_replace(u.telefono, '[^0-9]', '', 'g'),
        '^(0039|39)(3[0-9]{9})$', '\2'
      ) = v_telefono;
  exception
    when no_data_found or too_many_rows then
      return v_errore;
  end;

  v_token := public.turni_nuova_sessione('utente', v_match.id);
  return jsonb_build_object(
    'token', v_token, 'utente_id', v_match.id,
    'nome', v_match.nome, 'cognome', v_match.cognome
  );
end;
$$;

revoke all on function public.turni_login_utente(text, text, text)
  from public, anon, authenticated;
grant execute on function public.turni_login_utente(text, text, text)
  to anon, authenticated;

notify pgrst, 'reload schema';
commit;
