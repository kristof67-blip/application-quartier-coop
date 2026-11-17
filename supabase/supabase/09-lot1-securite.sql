-- Quartier Coop · LOT 1 de sécurité (contre-expertise de l'audit)
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ». Peut être relancé sans danger.
-- À exécuter APRÈS securite-urgent.sql (et après toutes les étapes précédentes).
--
-- Contenu :
--   1. Photos : limite ramenée à 500 Ko, et 200 photos au maximum par structure.
--   2. Quota de réponses (10 par heure) impossible à contourner : date imposée par le serveur,
--      compteur indépendant des suppressions, verrou contre les envois simultanés.
--   3. Dates de création imposées par le serveur sur toutes les publications (plus de « triche » sur l'ordre d'affichage).
--   4. Réponses d'un sujet non publié : plus lisibles par le public (réponses d'habitants et réponses officielles).
--   5. Limites de longueur (prix, lieu, description) et plafonds de publication par structure.

-- 1. PHOTOS -------------------------------------------------------------------------
update storage.buckets set file_size_limit = 524288, allowed_mime_types = array['image/jpeg'], public = true
where id = 'photos-plats';

-- Compteur de photos d'un dossier : fonction à droits propriétaire (sinon les règles d'accès cachent les fichiers au compteur).
create or replace function photos_dans_dossier(p_dossier text) returns bigint
language sql security definer stable set search_path = public, storage as $$
  select count(*) from storage.objects where bucket_id = 'photos-plats' and (storage.foldername(name))[1] = p_dossier
$$;
revoke all on function photos_dans_dossier(text) from public, anon;
grant execute on function photos_dans_dossier(text) to authenticated;

drop policy if exists "photos plats : dépôt par les référents" on storage.objects;
create policy "photos plats : dépôt par les référents" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'photos-plats'
    and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and peut_publier(((storage.foldername(name))[1])::uuid)
    and photos_dans_dossier((storage.foldername(name))[1]) < 200
  );

-- 2. QUOTA DE RÉPONSES -------------------------------------------------------------
create table if not exists quota_reponses (
  auteur uuid not null,
  created_at timestamptz not null default now()
);
create index if not exists quota_reponses_idx on quota_reponses (auteur, created_at);
alter table quota_reponses enable row level security;           -- aucune règle : table invisible depuis le site
revoke all on quota_reponses from anon, authenticated;

create or replace function limite_reponses() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.created_at := now();                                        -- la date vient du serveur, jamais du navigateur
  perform pg_advisory_xact_lock(hashtext(new.auteur::text));      -- deux envois simultanés ne passent pas
  delete from quota_reponses where created_at < now() - interval '2 hours';
  if (select count(*) from quota_reponses where auteur = new.auteur and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Trop de messages en peu de temps, réessayez plus tard';
  end if;
  insert into quota_reponses (auteur) values (new.auteur);       -- supprimer son message ne rend pas le quota
  return new;
end
$$;
-- (le déclencheur « limite_reponses_avant » existe déjà et appelle cette fonction)

-- 3. DATES DE CRÉATION IMPOSÉES PAR LE SERVEUR ---------------------------------------
create or replace function horodatage_serveur() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then new.created_at := now(); else new.created_at := old.created_at; end if;
  return new;
end
$$;
do $$
declare t text;
begin
  foreach t in array array['signalements','reponses','actualites','bons_plans','reponses_officielles','plats','evenements'] loop
    execute format('drop trigger if exists horodatage_serveur_avant on public.%I', t);
    execute format('create trigger horodatage_serveur_avant before insert or update on public.%I for each row execute function horodatage_serveur()', t);
  end loop;
end $$;

-- 4. RÉPONSES D'UN SUJET NON PUBLIÉ ------------------------------------------------
drop policy if exists "réponses visibles par tous" on reponses;
create policy "réponses visibles par tous" on reponses for select
  using (masquee = false and signalement_publie(signalement_id));

drop policy if exists "réponses officielles lisibles par tous" on reponses_officielles;
create policy "réponses officielles lisibles par tous" on reponses_officielles for select
  using (signalement_publie(signalement_id));
drop policy if exists "réponses officielles visibles de leur structure et des modérateurs" on reponses_officielles;
create policy "réponses officielles visibles de leur structure et des modérateurs" on reponses_officielles for select
  to authenticated using (est_moderateur() or peut_publier(acteur_id));

-- 5. LONGUEURS ET PLAFONDS ------------------------------------------------------------
-- « not valid » : les contenus déjà publiés ne sont pas contrôlés, tous les nouveaux le sont.
alter table plats drop constraint if exists plats_prix_longueur;
alter table plats add constraint plats_prix_longueur check (prix is null or char_length(prix) <= 40) not valid;
alter table evenements drop constraint if exists evenements_lieu_longueur;
alter table evenements add constraint evenements_lieu_longueur check (lieu is null or char_length(lieu) <= 120) not valid;
alter table evenements drop constraint if exists evenements_description_longueur;
alter table evenements add constraint evenements_description_longueur check (description is null or char_length(description) <= 1000) not valid;

create or replace function plafonds_publication() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'plats' then
    if (select count(*) from plats where acteur_id = new.acteur_id and created_at > now() - interval '1 day') >= 10 then
      raise exception 'Dix plats au maximum par jour et par structure';
    end if;
  elsif tg_table_name = 'evenements' then
    if (select count(*) from evenements where acteur_id = new.acteur_id and debut >= now()) >= 100 then
      raise exception 'Cent événements à venir au maximum par structure';
    end if;
  elsif tg_table_name = 'actualites' then
    if (select count(*) from actualites where acteur_id = new.acteur_id and created_at > now() - interval '1 day') >= 10 then
      raise exception 'Dix actualités au maximum par jour et par structure';
    end if;
  end if;
  return new;
end
$$;
do $$
declare t text;
begin
  foreach t in array array['plats','evenements','actualites'] loop
    execute format('drop trigger if exists plafonds_publication_avant on public.%I', t);
    execute format('create trigger plafonds_publication_avant before insert on public.%I for each row execute function plafonds_publication()', t);
  end loop;
end $$;

-- Pour vérifier :
--   select id, file_size_limit from storage.buckets;                      -- 524288
--   select trigger_name, event_object_table from information_schema.triggers
--   where trigger_name in ('horodatage_serveur_avant','plafonds_publication_avant') order by 2;
