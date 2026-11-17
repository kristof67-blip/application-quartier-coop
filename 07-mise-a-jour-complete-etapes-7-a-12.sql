-- Quartier Coop · MISE À JOUR COMPLÈTE (étapes 7 à 12) : à exécuter UNE SEULE FOIS dans Supabase.
-- Regroupe roles.sql, elue.sql, noms.sql, equipes.sql, medias.sql et bonsplans.sql, dans le bon ordre. Peut être relancé sans danger.
--
-- AVANT de l'exécuter : le compte du propriétaire (VOTRE_ADRESSE_EMAIL@exemple.fr) doit exister sur le site.
-- Pour un autre propriétaire, modifiez l'adresse dans la PARTIE 1 (ligne « proprietaire_email »).
--
-- Si Supabase affiche un avertissement sur des « opérations destructrices » (à cause des lignes
-- « drop policy / drop trigger if exists », qui ne suppriment aucune donnée), choisissez « Run this query ».

-- ======================================================================
-- PARTIE 1 : rôles, demandes d'accès pro, administrateurs, journal
-- ======================================================================
-- Quartier Coop · Étape 7 : rôles, demandes d'accès pro, administrateurs, journal
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ». Peut être relancé sans danger.
--
-- AVANT de l'exécuter : le compte du propriétaire doit exister. Si ce n'est pas déjà fait, créez-le
-- avec « Créer un compte habitant » sur le site (ou dans Authentication > Users > Add user).
-- Adresse du propriétaire : modifiez la ligne « proprietaire_email » ci-dessous si besoin.
--
-- Hiérarchie : propriétaire > administrateur > modérateur > référent / suppléant > habitant.
-- Toutes les règles sont appliquées par la base : même un site modifié ne peut pas les contourner.

-- 1. RÔLES ÉTENDUS ----------------------------------------------------------
do $$
declare c record;
begin
  for c in select conname from pg_constraint where conrelid = 'public.membres'::regclass and contype = 'c' loop
    execute format('alter table public.membres drop constraint %I', c.conname);
  end loop;
end $$;

alter table membres add constraint membres_role_check check (role in ('referent','suppleant','moderateur','administrateur','proprietaire'));
alter table membres add constraint membres_portee_check check (
  (role in ('referent','suppleant') and acteur_id is not null)
  or (role in ('moderateur','administrateur','proprietaire') and acteur_id is null)
);
-- Un seul rôle « général » (modérateur, administrateur ou propriétaire) par personne.
create unique index if not exists membres_un_role_general on membres (user_id) where acteur_id is null;

-- 2. FONCTIONS D'AIDE -------------------------------------------------------
create or replace function est_proprietaire() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from membres where user_id = auth.uid() and role = 'proprietaire')
$$;

create or replace function est_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from membres where user_id = auth.uid() and role in ('administrateur','proprietaire'))
$$;

-- Les administrateurs et propriétaires peuvent aussi modérer.
create or replace function est_moderateur() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from membres where user_id = auth.uid() and role in ('moderateur','administrateur','proprietaire'))
$$;

create or replace function est_referent_de(a uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from membres where user_id = auth.uid() and acteur_id = a and role in ('referent','suppleant'))
$$;

-- Publier au nom d'une structure : son référent, son suppléant, ou un administrateur / propriétaire.
create or replace function peut_publier(a uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select est_referent_de(a) or est_admin()
$$;

-- 3. JOURNAL ----------------------------------------------------------------
create table if not exists journal (
  id bigint generated always as identity primary key,
  le timestamptz not null default now(),
  auteur uuid,
  auteur_email text,
  action text not null,
  cible text,
  detail text
);
alter table journal enable row level security;
drop policy if exists "les administrateurs lisent le journal" on journal;
create policy "les administrateurs lisent le journal" on journal for select to authenticated using (est_admin());
grant select on journal to authenticated;

create or replace function noter(p_action text, p_cible text, p_detail text default null) returns void
language sql security definer set search_path = public, auth as $$
  insert into journal (auteur, auteur_email, action, cible, detail)
  select auth.uid(), (select email from auth.users where id = auth.uid()), p_action, p_cible, p_detail
$$;
revoke all on function noter(text, text, text) from public, anon, authenticated;

-- 4. LE PROPRIÉTAIRE --------------------------------------------------------
do $$
declare
  proprietaire_email constant text := 'VOTRE_ADRESSE_EMAIL@exemple.fr';   -- <- à modifier si besoin
  u uuid;
begin
  select id into u from auth.users where lower(email) = lower(proprietaire_email);
  if u is null then
    raise notice 'Aucun compte pour %. Créez-le puis relancez ce script.', proprietaire_email;
  else
    delete from membres where user_id = u and acteur_id is null and role <> 'proprietaire';
    insert into membres (user_id, acteur_id, role) values (u, null, 'proprietaire') on conflict do nothing;
  end if;
end $$;

-- Le dernier propriétaire ne peut jamais être retiré (ni son compte supprimé).
create or replace function protege_dernier_proprietaire() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.role = 'proprietaire' and (tg_op = 'DELETE' or new.role <> 'proprietaire') then
    if not exists (select 1 from membres where role = 'proprietaire' and user_id <> old.user_id) then
      raise exception 'Le dernier propriétaire ne peut pas être retiré';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;
drop trigger if exists protege_dernier_proprietaire_avant on membres;
create trigger protege_dernier_proprietaire_avant before update or delete on membres
  for each row execute function protege_dernier_proprietaire();

-- 5. DEMANDES D'ACCÈS PRO ---------------------------------------------------
create table if not exists demandes_pro (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  email text,
  acteur_id uuid references acteurs(id) on delete set null,
  structure_nom text check (structure_nom is null or char_length(structure_nom) between 2 and 80),
  fonction text not null check (char_length(fonction) between 2 and 80),
  message text check (message is null or char_length(message) <= 500),
  statut text not null default 'en_attente' check (statut in ('en_attente','acceptee','refusee')),
  traite_par uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (acteur_id is not null or structure_nom is not null)
);
-- Une seule demande en attente par personne.
create unique index if not exists demandes_une_en_attente on demandes_pro (user_id) where statut = 'en_attente';

create or replace function demande_prepare() returns trigger
language plpgsql security definer set search_path = public, auth as $$
begin
  new.email := (select email from auth.users where id = new.user_id);
  new.statut := 'en_attente';
  new.traite_par := null;
  if (select count(*) from demandes_pro where user_id = new.user_id) >= 5 then
    raise exception 'Trop de demandes pour ce compte';
  end if;
  return new;
end
$$;
drop trigger if exists demande_prepare_avant on demandes_pro;
create trigger demande_prepare_avant before insert on demandes_pro
  for each row execute function demande_prepare();

alter table demandes_pro enable row level security;
drop policy if exists "déposer sa demande" on demandes_pro;
create policy "déposer sa demande" on demandes_pro for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "voir ses demandes ou administrer" on demandes_pro;
create policy "voir ses demandes ou administrer" on demandes_pro for select to authenticated using (user_id = auth.uid() or est_admin());
grant select, insert on demandes_pro to authenticated;

-- 6. NOMINATIONS D'ADMINISTRATEURS : DOUBLE VALIDATION -----------------------
-- Un administrateur propose ; un AUTRE administrateur (ou un propriétaire) confirme sous 7 jours.
-- Un propriétaire agit directement. Aucun accès direct à cette table : tout passe par les fonctions.
create table if not exists propositions_admin (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('nommer','retirer')),
  cible uuid not null references auth.users(id) on delete cascade,
  cible_email text not null,
  propose_par uuid references auth.users(id) on delete set null,
  propose_par_email text,
  statut text not null default 'en_attente' check (statut in ('en_attente','validee','refusee')),
  expire_le timestamptz not null default now() + interval '7 days',
  created_at timestamptz not null default now()
);
alter table propositions_admin enable row level security;

-- 7. ACTIONS (fonctions appelées par le site) ---------------------------------
create or replace function attribuer_role(p_email text, p_role text, p_acteur uuid default null) returns text
language plpgsql security definer set search_path = public, auth as $$
declare
  v_cible uuid;
  v_role text;
  mail text;
begin
  if not est_admin() then raise exception 'Réservé aux administrateurs'; end if;
  if p_role not in ('moderateur','referent','suppleant','administrateur','proprietaire') then
    raise exception 'Rôle inconnu';
  end if;
  select id, email into v_cible, mail from auth.users where lower(email) = lower(trim(p_email));
  if v_cible is null then raise exception 'Aucun compte avec cette adresse'; end if;
  select role into v_role from membres where user_id = v_cible and acteur_id is null;

  if p_role in ('referent','suppleant') then
    if p_acteur is null or not exists (select 1 from acteurs where id = p_acteur) then
      raise exception 'Choisissez une structure';
    end if;
    insert into membres (user_id, acteur_id, role) values (v_cible, p_acteur, p_role)
      on conflict (user_id, acteur_id) do update set role = excluded.role;
    perform noter('role_attribue', mail, p_role || ' · ' || (select nom from acteurs where id = p_acteur));
    return 'ok';

  elsif p_role = 'moderateur' then
    if v_role in ('administrateur','proprietaire') then raise exception 'Cette personne a déjà un rôle supérieur'; end if;
    insert into membres (user_id, acteur_id, role) values (v_cible, null, 'moderateur')
      on conflict (user_id) where acteur_id is null do nothing;
    perform noter('role_attribue', mail, 'moderateur');
    return 'ok';

  elsif p_role = 'administrateur' then
    if v_role = 'proprietaire' then raise exception 'Cette personne est déjà propriétaire'; end if;
    if v_role = 'administrateur' then raise exception 'Cette personne est déjà administrateur'; end if;
    if est_proprietaire() then
      insert into membres (user_id, acteur_id, role) values (v_cible, null, 'administrateur')
        on conflict (user_id) where acteur_id is null do update set role = 'administrateur';
      perform noter('admin_nomme', mail, 'par un propriétaire');
      return 'ok';
    end if;
    if exists (select 1 from propositions_admin pa where pa.cible = v_cible and pa.type = 'nommer'
               and pa.statut = 'en_attente' and pa.expire_le > now()) then
      raise exception 'Une proposition est déjà en attente pour cette personne';
    end if;
    insert into propositions_admin (type, cible, cible_email, propose_par, propose_par_email)
      values ('nommer', v_cible, mail, auth.uid(), (select email from auth.users where id = auth.uid()));
    perform noter('admin_propose', mail, 'en attente de confirmation');
    return 'proposition';

  else  -- propriétaire
    if not est_proprietaire() then raise exception 'Seul un propriétaire peut nommer un propriétaire'; end if;
    insert into membres (user_id, acteur_id, role) values (v_cible, null, 'proprietaire')
      on conflict (user_id) where acteur_id is null do update set role = 'proprietaire';
    perform noter('proprietaire_nomme', mail, null);
    return 'ok';
  end if;
end
$$;

create or replace function retirer_role(p_user uuid, p_role text, p_acteur uuid default null) returns text
language plpgsql security definer set search_path = public, auth as $$
declare mail text;
begin
  if not est_admin() then raise exception 'Réservé aux administrateurs'; end if;
  select email into mail from auth.users where id = p_user;
  if not exists (select 1 from membres where user_id = p_user and role = p_role and acteur_id is not distinct from p_acteur) then
    raise exception 'Ce rôle n''existe plus';
  end if;

  if p_role = 'proprietaire' and not est_proprietaire() then
    raise exception 'Seul un propriétaire peut retirer un propriétaire';
  end if;

  if p_role = 'administrateur' and not est_proprietaire() then
    if exists (select 1 from propositions_admin pa where pa.cible = p_user and pa.type = 'retirer'
               and pa.statut = 'en_attente' and pa.expire_le > now()) then
      raise exception 'Une proposition est déjà en attente pour cette personne';
    end if;
    insert into propositions_admin (type, cible, cible_email, propose_par, propose_par_email)
      values ('retirer', p_user, mail, auth.uid(), (select email from auth.users where id = auth.uid()));
    perform noter('retrait_admin_propose', mail, 'en attente de confirmation');
    return 'proposition';
  end if;

  delete from membres where user_id = p_user and role = p_role and acteur_id is not distinct from p_acteur;
  perform noter('role_retire', mail, p_role || coalesce(' · ' || (select nom from acteurs where id = p_acteur), ''));
  return 'ok';
end
$$;

create or replace function repondre_proposition(p_id uuid, p_accepter boolean) returns text
language plpgsql security definer set search_path = public, auth as $$
declare pr propositions_admin%rowtype;
begin
  if not est_admin() then raise exception 'Réservé aux administrateurs'; end if;
  select * into pr from propositions_admin where id = p_id for update;
  if not found or pr.statut <> 'en_attente' then raise exception 'Proposition introuvable ou déjà traitée'; end if;
  if pr.expire_le < now() then raise exception 'Cette proposition a expiré'; end if;

  if not p_accepter then
    update propositions_admin set statut = 'refusee' where id = p_id;
    perform noter('proposition_refusee', pr.cible_email, pr.type);
    return 'refusee';
  end if;

  if pr.propose_par = auth.uid() and not est_proprietaire() then
    raise exception 'Un autre administrateur doit confirmer cette proposition';
  end if;

  if pr.type = 'nommer' then
    insert into membres (user_id, acteur_id, role) values (pr.cible, null, 'administrateur')
      on conflict (user_id) where acteur_id is null do update set role = 'administrateur'
      where membres.role <> 'proprietaire';
    perform noter('admin_nomme', pr.cible_email, 'double validation');
  else
    delete from membres where user_id = pr.cible and role = 'administrateur' and acteur_id is null;
    perform noter('admin_retire', pr.cible_email, 'double validation');
  end if;
  update propositions_admin set statut = 'validee' where id = p_id;
  return 'validee';
end
$$;

create or replace function traiter_demande(
  p_id uuid, p_accepter boolean,
  p_acteur uuid default null, p_role text default 'referent', p_categorie text default null
) returns text
language plpgsql security definer set search_path = public, auth as $$
declare d demandes_pro%rowtype; a uuid;
begin
  if not est_admin() then raise exception 'Réservé aux administrateurs'; end if;
  select * into d from demandes_pro where id = p_id for update;
  if not found or d.statut <> 'en_attente' then raise exception 'Demande introuvable ou déjà traitée'; end if;

  if not p_accepter then
    update demandes_pro set statut = 'refusee', traite_par = auth.uid() where id = p_id;
    perform noter('demande_refusee', d.email, coalesce(d.structure_nom, (select nom from acteurs where id = d.acteur_id)));
    return 'refusee';
  end if;

  if p_role not in ('referent','suppleant') then raise exception 'Rôle inconnu'; end if;
  a := coalesce(p_acteur, d.acteur_id);
  if a is null then
    if p_categorie is null or p_categorie not in ('restaurateur','commerce','lieu_culturel','institution','association') then
      raise exception 'Choisissez une catégorie pour la nouvelle structure';
    end if;
    insert into acteurs (nom, categorie) values (d.structure_nom, p_categorie)
      on conflict (nom) do update set nom = excluded.nom returning id into a;
  end if;
  insert into membres (user_id, acteur_id, role) values (d.user_id, a, p_role)
    on conflict (user_id, acteur_id) do update set role = excluded.role;
  update demandes_pro set statut = 'acceptee', traite_par = auth.uid(), acteur_id = a where id = p_id;
  perform noter('demande_acceptee', d.email, p_role || ' · ' || (select nom from acteurs where id = a));
  return 'acceptee';
end
$$;

-- Tableau de bord de l'administration : tout ce qu'il faut en un seul appel.
create or replace function admin_tableau() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
begin
  if not est_admin() then raise exception 'Réservé aux administrateurs'; end if;
  return jsonb_build_object(
    'moi', auth.uid(),
    'proprietaire', est_proprietaire(),
    'demandes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'email', d.email, 'structure', coalesce(a.nom, d.structure_nom),
        'acteur_id', d.acteur_id, 'nouvelle', d.acteur_id is null,
        'fonction', d.fonction, 'message', d.message, 'le', d.created_at) order by d.created_at)
      from demandes_pro d left join acteurs a on a.id = d.acteur_id where d.statut = 'en_attente'), '[]'::jsonb),
    'equipe', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', m.user_id, 'email', u.email, 'role', m.role, 'acteur_id', m.acteur_id, 'structure', a.nom)
        order by case m.role when 'proprietaire' then 1 when 'administrateur' then 2 when 'moderateur' then 3 else 4 end, u.email)
      from membres m join auth.users u on u.id = m.user_id left join acteurs a on a.id = m.acteur_id), '[]'::jsonb),
    'propositions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'type', p.type, 'cible_email', p.cible_email, 'propose_par', p.propose_par,
        'propose_par_email', p.propose_par_email, 'expire_le', p.expire_le) order by p.created_at)
      from propositions_admin p where p.statut = 'en_attente' and p.expire_le > now()), '[]'::jsonb),
    'journal', coalesce((
      select jsonb_agg(to_jsonb(j)) from (
        select le, auteur_email, action, cible, detail from journal order by id desc limit 50) j), '[]'::jsonb)
  );
end
$$;

revoke all on function attribuer_role(text, text, uuid) from public, anon;
revoke all on function retirer_role(uuid, text, uuid) from public, anon;
revoke all on function repondre_proposition(uuid, boolean) from public, anon;
revoke all on function traiter_demande(uuid, boolean, uuid, text, text) from public, anon;
revoke all on function admin_tableau() from public, anon;
grant execute on function attribuer_role(text, text, uuid) to authenticated;
grant execute on function retirer_role(uuid, text, uuid) to authenticated;
grant execute on function repondre_proposition(uuid, boolean) to authenticated;
grant execute on function traiter_demande(uuid, boolean, uuid, text, text) to authenticated;
grant execute on function admin_tableau() to authenticated;

-- 8. PUBLIER AU NOM D'UNE STRUCTURE : MARQUAGE ET JOURNAL ----------------------
alter table plats add column if not exists publie_par uuid;
alter table plats add column if not exists par_equipe boolean not null default false;
alter table evenements add column if not exists publie_par uuid;
alter table evenements add column if not exists par_equipe boolean not null default false;

create or replace function marque_equipe() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.publie_par := auth.uid();
  new.par_equipe := (auth.uid() is not null and not est_referent_de(new.acteur_id) and est_admin());
  return new;
end
$$;
drop trigger if exists marque_equipe_plats on plats;
create trigger marque_equipe_plats before insert or update on plats for each row execute function marque_equipe();
drop trigger if exists marque_equipe_evenements on evenements;
create trigger marque_equipe_evenements before insert or update on evenements for each row execute function marque_equipe();

create or replace function journalise_equipe() returns trigger
language plpgsql security definer set search_path = public, auth as $$
declare a uuid; t text; n text;
begin
  if tg_op = 'DELETE' then
    a := old.acteur_id; t := old.titre;
    if auth.uid() is null or est_referent_de(a) or not est_admin() then return old; end if;
    n := 'suppression_pour';
  else
    a := new.acteur_id; t := new.titre;
    if not new.par_equipe then return new; end if;
    n := case when tg_op = 'INSERT' then 'publication_pour' else 'modification_pour' end;
  end if;
  perform noter(n, (select nom from acteurs where id = a), t);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;
drop trigger if exists journalise_equipe_plats on plats;
create trigger journalise_equipe_plats after insert or update or delete on plats for each row execute function journalise_equipe();
drop trigger if exists journalise_equipe_evenements on evenements;
create trigger journalise_equipe_evenements after insert or update or delete on evenements for each row execute function journalise_equipe();

-- 9. POUR VÉRIFIER ------------------------------------------------------------
-- select u.email, m.role, a.nom from membres m join auth.users u on u.id = m.user_id left join acteurs a on a.id = m.acteur_id order by m.role;
-- select * from journal order by id desc limit 20;

-- ======================================================================
-- PARTIE 2 : actualités et réponses officielles (élue, SPL, associations)
-- ======================================================================
-- Quartier Coop · Étape 8 : actualités de l'élue, de la SPL et des associations sur l'accueil + réponses officielles aux sujets des habitants
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ». Peut être relancé sans danger.
-- À exécuter APRÈS roles.sql (il utilise ses fonctions et son journal).

-- 1. ACTUALITÉS (bloc « Votre élue de quartier » de l'accueil) -------------------
create table if not exists actualites (
  id uuid primary key default gen_random_uuid(),
  acteur_id uuid not null references acteurs(id) on delete cascade,
  titre text not null check (char_length(titre) between 2 and 120),
  detail text check (detail is null or char_length(detail) <= 200),
  publie_par uuid,
  par_equipe boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists actualites_recentes on actualites (acteur_id, created_at desc);

-- 2. RÉPONSES OFFICIELLES (une par structure et par sujet, réservées aux institutions et associations) ----
create table if not exists reponses_officielles (
  id uuid primary key default gen_random_uuid(),
  signalement_id uuid not null references signalements(id) on delete cascade,
  acteur_id uuid not null references acteurs(id) on delete cascade,
  texte text not null check (char_length(texte) between 2 and 800),
  publie_par uuid,
  par_equipe boolean not null default false,
  created_at timestamptz not null default now(),
  unique (signalement_id, acteur_id)
);

create or replace function est_institution(a uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from acteurs where id = a and categorie in ('institution','association'))
$$;

-- 3. MARQUAGE « ÉQUIPE » ET JOURNAL (même principe que pour les plats et événements) ------
drop trigger if exists marque_equipe_actualites on actualites;
create trigger marque_equipe_actualites before insert or update on actualites
  for each row execute function marque_equipe();
drop trigger if exists journalise_equipe_actualites on actualites;
create trigger journalise_equipe_actualites after insert or update or delete on actualites
  for each row execute function journalise_equipe();

drop trigger if exists marque_equipe_reponses_off on reponses_officielles;
create trigger marque_equipe_reponses_off before insert or update on reponses_officielles
  for each row execute function marque_equipe();

create or replace function journalise_equipe_texte() returns trigger
language plpgsql security definer set search_path = public, auth as $$
declare a uuid; t text; n text;
begin
  if tg_op = 'DELETE' then
    a := old.acteur_id; t := left(old.texte, 60);
    if auth.uid() is null or est_referent_de(a) or not est_admin() then return old; end if;
    n := 'suppression_pour';
  else
    a := new.acteur_id; t := left(new.texte, 60);
    if not new.par_equipe then return new; end if;
    n := case when tg_op = 'INSERT' then 'reponse_officielle_pour' else 'modification_pour' end;
  end if;
  perform noter(n, (select nom from acteurs where id = a), t);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;
drop trigger if exists journalise_equipe_reponses_off on reponses_officielles;
create trigger journalise_equipe_reponses_off after insert or update or delete on reponses_officielles
  for each row execute function journalise_equipe_texte();

-- 4. SÉCURITÉ (RLS) ---------------------------------------------------------------
alter table actualites enable row level security;
alter table reponses_officielles enable row level security;

drop policy if exists "actualités lisibles par tous" on actualites;
create policy "actualités lisibles par tous" on actualites for select using (true);
drop policy if exists "actualités publiées par la structure" on actualites;
create policy "actualités publiées par la structure" on actualites for insert to authenticated
  with check (peut_publier(acteur_id));
drop policy if exists "actualités modifiées par la structure" on actualites;
create policy "actualités modifiées par la structure" on actualites for update to authenticated
  using (peut_publier(acteur_id)) with check (peut_publier(acteur_id));
drop policy if exists "actualités supprimées par la structure" on actualites;
create policy "actualités supprimées par la structure" on actualites for delete to authenticated
  using (peut_publier(acteur_id));

drop policy if exists "réponses officielles lisibles par tous" on reponses_officielles;
create policy "réponses officielles lisibles par tous" on reponses_officielles for select using (true);
drop policy if exists "réponse officielle par une institution" on reponses_officielles;
create policy "réponse officielle par une institution" on reponses_officielles for insert to authenticated
  with check (peut_publier(acteur_id) and est_institution(acteur_id) and signalement_publie(signalement_id));
drop policy if exists "réponse officielle modifiée" on reponses_officielles;
create policy "réponse officielle modifiée" on reponses_officielles for update to authenticated
  using (peut_publier(acteur_id)) with check (peut_publier(acteur_id) and est_institution(acteur_id));
drop policy if exists "réponse officielle supprimée" on reponses_officielles;
create policy "réponse officielle supprimée" on reponses_officielles for delete to authenticated
  using (peut_publier(acteur_id) or est_moderateur());

-- 5. DROITS D'ACCÈS ---------------------------------------------------------------
grant select on actualites, reponses_officielles to anon, authenticated;
grant insert, update, delete on actualites, reponses_officielles to authenticated;

-- Pour vérifier :  select count(*) from actualites;  select count(*) from reponses_officielles;

-- ======================================================================
-- PARTIE 3 : intitulés de structures modifiables
-- ======================================================================
-- Quartier Coop · Étape 9 : intitulés de structures modifiables (par exemple « Élue » devient « Élu » de quartier)
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ». Peut être relancé sans danger.
-- À exécuter APRÈS roles.sql (il utilise le journal et les droits d'administration).

-- 1. IDENTIFIANT INTERNE STABLE ---------------------------------------------------
-- Le site reconnaît une structure par son code, jamais par son nom affiché : renommer ne casse rien.
alter table acteurs add column if not exists code text;

update acteurs a set code = v.code
from (values
  ('Le Bateau du Rhin','bateau'), ('Le Block','block'), ('Dékalé','dekale'), ('Boulangerie','boulangerie'),
  ('Kaleidoscope','kaleidoscope'), ('Galerie Kraemer','kraemer'), ('Les ateliers éclairés','ateliers'),
  ('SPL des Deux Rives','spl'), ('Élue de quartier','elue'), ('Associations de quartier','assos')
) as v(nom, code)
where a.nom = v.nom and a.code is null;

-- Les autres structures (créées depuis les demandes d'accès) reçoivent un code automatique.
update acteurs set code = 'a' || replace(id::text, '-', '') where code is null;

create or replace function acteur_code_auto() returns trigger
language plpgsql as $$
begin
  if new.code is null then new.code := 'a' || replace(new.id::text, '-', ''); end if;
  return new;
end
$$;
drop trigger if exists acteur_code_auto_avant on acteurs;
create trigger acteur_code_auto_avant before insert on acteurs for each row execute function acteur_code_auto();

create unique index if not exists acteurs_code_unique on acteurs (code);

-- Le code ne peut pas être modifié (ni par le site, ni par erreur).
create or replace function acteur_code_fige() returns trigger
language plpgsql as $$
begin
  if old.code is not null and new.code is distinct from old.code then raise exception 'Le code interne d''une structure est fixe'; end if;
  return new;
end
$$;
drop trigger if exists acteur_code_fige_avant on acteurs;
create trigger acteur_code_fige_avant before update on acteurs for each row execute function acteur_code_fige();

-- 2. RENOMMER UNE STRUCTURE (administrateurs et propriétaires) ----------------------
create or replace function renommer_acteur(p_id uuid, p_nom text) returns text
language plpgsql security definer set search_path = public as $$
declare ancien text; nouveau text := btrim(p_nom);
begin
  if not est_admin() then raise exception 'Réservé aux administrateurs'; end if;
  if nouveau is null or char_length(nouveau) not between 2 and 80 then
    raise exception 'Le nom doit faire entre 2 et 80 caractères';
  end if;
  select nom into ancien from acteurs where id = p_id;
  if not found then raise exception 'Structure introuvable'; end if;
  if ancien = nouveau then return 'ok'; end if;
  if exists (select 1 from acteurs where lower(nom) = lower(nouveau) and id <> p_id) then
    raise exception 'Ce nom est déjà utilisé';
  end if;
  update acteurs set nom = nouveau where id = p_id;
  perform noter('structure_renommee', ancien, nouveau);
  return 'ok';
end
$$;
revoke all on function renommer_acteur(uuid, text) from public, anon;
grant execute on function renommer_acteur(uuid, text) to authenticated;

-- 3. PSEUDOS : « élu » est réservé comme « élue », « modérateur » et « admin » -----------
do $$
declare c record;
begin
  for c in select conname from pg_constraint where conrelid = 'public.profils'::regclass and contype = 'c' loop
    execute format('alter table public.profils drop constraint %I', c.conname);
  end loop;
end $$;
alter table profils add constraint profils_pseudo_check check (
  char_length(pseudo) between 3 and 24
  and pseudo ~ '^[A-Za-zÀ-ÿ0-9 _.-]+$'
  and pseudo !~* '(mod[eé]rat|admin|[eé]lue|(^|[^a-zà-ÿ])[eé]lu([^a-zà-ÿ]|$))'
) not valid;  -- « not valid » : les pseudos déjà créés ne sont pas contrôlés, les nouveaux le sont.

-- Pour vérifier :  select code, nom from acteurs order by nom;

-- ======================================================================
-- PARTIE 4 : les référents désignent leurs suppléants
-- ======================================================================
-- Quartier Coop · Étape 10 : les référents désignent eux-mêmes leurs suppléants
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ». Peut être relancé sans danger.
-- À exécuter APRÈS roles.sql.
--
-- Règles :
--   · le référent d'une structure peut désigner et retirer ses suppléants (5 au maximum) ;
--   · un suppléant peut publier pour la structure, voir l'équipe, et se retirer lui-même ;
--   · seuls les administrateurs nomment ou retirent un référent (écran « Administration ») ;
--   · tout est inscrit au journal.

-- Voir l'équipe d'une structure (référent, suppléants, administrateurs).
create or replace function equipe_structure(p_acteur uuid) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
begin
  if not (est_referent_de(p_acteur) or est_admin()) then raise exception 'Accès refusé'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'email', u.email, 'role', m.role)
                     order by case m.role when 'referent' then 1 else 2 end, u.email)
    from membres m join auth.users u on u.id = m.user_id
    where m.acteur_id = p_acteur), '[]'::jsonb);
end
$$;

-- Désigner un suppléant (la personne doit déjà avoir un compte sur le site).
create or replace function ajouter_suppleant(p_acteur uuid, p_email text) returns text
language plpgsql security definer set search_path = public, auth as $$
declare v_user uuid; v_mail text; v_role text;
begin
  if not (est_admin() or exists (
    select 1 from membres where user_id = auth.uid() and acteur_id = p_acteur and role = 'referent'
  )) then
    raise exception 'Seul le référent peut désigner un suppléant';
  end if;
  select id, email into v_user, v_mail from auth.users where lower(email) = lower(btrim(p_email));
  if v_user is null then
    raise exception 'Aucun compte avec cette adresse : la personne doit d''abord créer un compte habitant';
  end if;
  select role into v_role from membres where user_id = v_user and acteur_id = p_acteur;
  if v_role = 'referent' then raise exception 'Cette personne est déjà référente'; end if;
  if v_role = 'suppleant' then raise exception 'Cette personne est déjà suppléante'; end if;
  if (select count(*) from membres where acteur_id = p_acteur and role = 'suppleant') >= 5 then
    raise exception 'Cinq suppléants au maximum';
  end if;
  insert into membres (user_id, acteur_id, role) values (v_user, p_acteur, 'suppleant');
  perform noter('suppleant_ajoute', v_mail, (select nom from acteurs where id = p_acteur));
  return 'ok';
end
$$;

-- Retirer un suppléant (par le référent, un administrateur, ou par le suppléant lui-même).
create or replace function retirer_suppleant(p_acteur uuid, p_user uuid) returns text
language plpgsql security definer set search_path = public, auth as $$
declare v_mail text;
begin
  if not (est_admin() or p_user = auth.uid() or exists (
    select 1 from membres where user_id = auth.uid() and acteur_id = p_acteur and role = 'referent'
  )) then
    raise exception 'Action non autorisée';
  end if;
  if not exists (select 1 from membres where user_id = p_user and acteur_id = p_acteur and role = 'suppleant') then
    raise exception 'Cette personne n''est plus suppléante';
  end if;
  select email into v_mail from auth.users where id = p_user;
  delete from membres where user_id = p_user and acteur_id = p_acteur and role = 'suppleant';
  perform noter('suppleant_retire', v_mail, (select nom from acteurs where id = p_acteur));
  return 'ok';
end
$$;

revoke all on function equipe_structure(uuid) from public, anon;
revoke all on function ajouter_suppleant(uuid, text) from public, anon;
revoke all on function retirer_suppleant(uuid, uuid) from public, anon;
grant execute on function equipe_structure(uuid) to authenticated;
grant execute on function ajouter_suppleant(uuid, text) to authenticated;
grant execute on function retirer_suppleant(uuid, uuid) to authenticated;

-- ======================================================================
-- PARTIE 5 : photos et liens web sur les événements et les actualités
-- ======================================================================
-- Quartier Coop · Étape 11 : photos et liens web sur les événements et les actualités
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ». Peut être relancé sans danger.
-- À exécuter APRÈS roles.sql et elue.sql (la table « actualites » doit exister).
--
-- Les photos réutilisent l'espace de stockage « photos-plats » (JPEG, 500 Ko maximum, un dossier par structure) :
-- aucune configuration supplémentaire. Les liens sont limités à des adresses https:// (pas de http, pas de javascript:).

alter table evenements add column if not exists photo_path text;
alter table evenements add column if not exists lien text;
alter table evenements add column if not exists lien_texte text;

alter table actualites add column if not exists photo_path text;
alter table actualites add column if not exists lien text;
alter table actualites add column if not exists lien_texte text;

-- Règles de validité (appliquées par la base, même si le site était modifié).
alter table evenements drop constraint if exists evenements_medias_check;
alter table evenements add constraint evenements_medias_check check (
  (lien is null or (lien ~* '^https://[^[:space:]"''<>]+$' and char_length(lien) <= 300))
  and (lien_texte is null or char_length(lien_texte) <= 40)
  and (photo_path is null or photo_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9._-]+\.jpg$')
);

alter table actualites drop constraint if exists actualites_medias_check;
alter table actualites add constraint actualites_medias_check check (
  (lien is null or (lien ~* '^https://[^[:space:]"''<>]+$' and char_length(lien) <= 300))
  and (lien_texte is null or char_length(lien_texte) <= 40)
  and (photo_path is null or photo_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9._-]+\.jpg$')
);

-- Pour vérifier :  select titre, photo_path, lien from evenements where lien is not null;

-- =====================================================================================
-- PARTIE 6 : rubrique « Bons plans » (restaurateurs et commerces)
-- =====================================================================================
-- Quartier Coop · Étape 12 : rubrique « Bons plans » (restaurateurs et commerces uniquement)
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ». Peut être relancé sans danger.
-- À exécuter APRÈS roles.sql et medias.sql.
--
-- Principes :
--   · seuls le référent ou le suppléant d'un restaurateur ou d'un commerce (ou un administrateur, à sa place)
--     peuvent publier un bon plan pour cette structure ;
--   · une structure ne peut ni modifier ni supprimer le bon plan d'une autre : publier un nouveau bon plan
--     ne remplace jamais celui d'un voisin, ils s'affichent tous côte à côte, triés par date de fin ;
--   · deux bons plans en cours au maximum par structure, durée de 30 jours au maximum ;
--   · un bon plan disparaît seul après sa date de fin.

-- 1. Structures autorisées : restaurateurs et commerces.
create or replace function est_commerce(a uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from acteurs where id = a and categorie in ('restaurateur','commerce'))
$$;

-- 2. Table ------------------------------------------------------------------
create table if not exists bons_plans (
  id uuid primary key default gen_random_uuid(),
  acteur_id uuid not null references acteurs(id) on delete cascade,
  titre text not null check (char_length(titre) between 2 and 80),
  prix text check (prix is null or char_length(prix) <= 40),
  detail text check (detail is null or char_length(detail) <= 200),
  fin date not null,
  photo_path text,
  lien text,
  lien_texte text,
  publie_par uuid,
  par_equipe boolean not null default false,
  created_at timestamptz not null default now(),
  check (lien is null or (lien ~* '^https://[^[:space:]"''<>]+$' and char_length(lien) <= 300)),
  check (lien_texte is null or char_length(lien_texte) <= 40),
  check (photo_path is null or photo_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9._-]+\.jpg$')
);
create index if not exists bons_plans_en_cours on bons_plans (fin, acteur_id);

-- 3. Règles métier (durée, nombre, structure non modifiable) -----------------------
create or replace function bons_plans_regles() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then new.acteur_id := old.acteur_id; end if;
  if new.fin < current_date or new.fin > current_date + 30 then
    raise exception 'La date de fin doit être comprise entre aujourd''hui et dans 30 jours';
  end if;
  if tg_op = 'INSERT' and new.fin >= current_date and (
    select count(*) from bons_plans where acteur_id = new.acteur_id and fin >= current_date
  ) >= 2 then
    raise exception 'Deux bons plans en cours au maximum par structure : supprimez-en un ou attendez sa fin';
  end if;
  return new;
end
$$;
drop trigger if exists bons_plans_regles_avant on bons_plans;
create trigger bons_plans_regles_avant before insert or update on bons_plans
  for each row execute function bons_plans_regles();

-- Marquage « publié par l'équipe » et journal (mêmes fonctions que pour les plats et événements).
drop trigger if exists marque_equipe_bons_plans on bons_plans;
create trigger marque_equipe_bons_plans before insert or update on bons_plans
  for each row execute function marque_equipe();
drop trigger if exists journalise_equipe_bons_plans on bons_plans;
create trigger journalise_equipe_bons_plans after insert or update or delete on bons_plans
  for each row execute function journalise_equipe();

-- 4. Sécurité (RLS) -----------------------------------------------------------------
alter table bons_plans enable row level security;

drop policy if exists "bons plans en cours lisibles par tous" on bons_plans;
create policy "bons plans en cours lisibles par tous" on bons_plans for select using (fin >= current_date);
drop policy if exists "une structure voit tous ses bons plans" on bons_plans;
create policy "une structure voit tous ses bons plans" on bons_plans for select to authenticated using (peut_publier(acteur_id));

drop policy if exists "bon plan publié par sa structure" on bons_plans;
create policy "bon plan publié par sa structure" on bons_plans for insert to authenticated
  with check (peut_publier(acteur_id) and est_commerce(acteur_id));
drop policy if exists "bon plan modifié par sa structure" on bons_plans;
create policy "bon plan modifié par sa structure" on bons_plans for update to authenticated
  using (peut_publier(acteur_id)) with check (peut_publier(acteur_id) and est_commerce(acteur_id));
drop policy if exists "bon plan supprimé par sa structure ou modéré" on bons_plans;
create policy "bon plan supprimé par sa structure ou modéré" on bons_plans for delete to authenticated
  using (peut_publier(acteur_id) or est_moderateur());

grant select on bons_plans to anon, authenticated;
grant insert, update, delete on bons_plans to authenticated;

-- Pour vérifier :  select a.nom, b.titre, b.fin from bons_plans b join acteurs a on a.id = b.acteur_id order by b.fin;
