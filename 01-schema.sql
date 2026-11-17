-- Quartier Coop · Étape 1 : structure de la base de données (Supabase / Postgres)
-- À coller dans Supabase > SQL Editor > New query, puis « Run ». Peut être relancé sans danger.

-- 1. TABLES -----------------------------------------------------------------
create table if not exists acteurs (
  id uuid primary key default gen_random_uuid(),
  nom text not null unique,
  categorie text not null check (categorie in ('restaurateur','commerce','lieu_culturel','institution','association')),
  created_at timestamptz not null default now()
);

-- Qui peut publier au nom de quel acteur (référent ou suppléant), et qui modère.
create table if not exists membres (
  user_id uuid not null references auth.users(id) on delete cascade,
  acteur_id uuid references acteurs(id) on delete cascade,
  role text not null check (role in ('referent','suppleant','moderateur')),
  unique (user_id, acteur_id)
);

create table if not exists plats (
  id uuid primary key default gen_random_uuid(),
  acteur_id uuid not null references acteurs(id) on delete cascade,
  titre text not null check (char_length(titre) between 2 and 120),
  prix text,
  photo_path text,
  publie_le date not null default current_date,
  vues integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists evenements (
  id uuid primary key default gen_random_uuid(),
  acteur_id uuid not null references acteurs(id) on delete cascade,
  titre text not null check (char_length(titre) between 2 and 120),
  debut timestamptz not null,
  lieu text,
  description text,
  vues integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists signalements (
  id uuid primary key default gen_random_uuid(),
  texte text not null check (char_length(texte) between 5 and 500),
  statut text not null default 'en_attente' check (statut in ('en_attente','publie','refuse')),
  created_at timestamptz not null default now()
);

-- « Moi aussi » : un soutien par navigateur (identifiant anonyme généré par le site).
create table if not exists soutiens (
  signalement_id uuid not null references signalements(id) on delete cascade,
  appareil text not null check (char_length(appareil) between 8 and 64),
  primary key (signalement_id, appareil)
);

-- 2. FONCTIONS D'AIDE -------------------------------------------------------
create or replace function est_moderateur() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from membres where user_id = auth.uid() and role = 'moderateur')
$$;

create or replace function peut_publier(a uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from membres where user_id = auth.uid() and acteur_id = a and role in ('referent','suppleant'))
$$;

create or replace function signalement_publie(s uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from signalements where id = s and statut = 'publie')
$$;

-- Signalements visibles par tous : publiés uniquement, avec leur nombre de soutiens.
-- (Vue volontairement exécutée avec les droits du propriétaire pour compter les soutiens.)
create or replace view signalements_publics as
  select s.id, s.texte, s.created_at,
         (select count(*) from soutiens o where o.signalement_id = s.id) as soutiens
  from signalements s
  where s.statut = 'publie';

-- 3. SÉCURITÉ (RLS) : qui a le droit de faire quoi ----------------------------
alter table acteurs enable row level security;
alter table membres enable row level security;
alter table plats enable row level security;
alter table evenements enable row level security;
alter table signalements enable row level security;
alter table soutiens enable row level security;

drop policy if exists "acteurs lisibles par tous" on acteurs;
create policy "acteurs lisibles par tous" on acteurs for select using (true);

drop policy if exists "chacun voit ses appartenances" on membres;
create policy "chacun voit ses appartenances" on membres for select to authenticated using (user_id = auth.uid());

drop policy if exists "plats lisibles par tous" on plats;
create policy "plats lisibles par tous" on plats for select using (true);
drop policy if exists "plats publiés par les référents" on plats;
create policy "plats publiés par les référents" on plats for insert to authenticated with check (peut_publier(acteur_id));
drop policy if exists "plats modifiés par les référents" on plats;
create policy "plats modifiés par les référents" on plats for update to authenticated using (peut_publier(acteur_id)) with check (peut_publier(acteur_id));
drop policy if exists "plats supprimés par les référents" on plats;
create policy "plats supprimés par les référents" on plats for delete to authenticated using (peut_publier(acteur_id));

drop policy if exists "événements lisibles par tous" on evenements;
create policy "événements lisibles par tous" on evenements for select using (true);
drop policy if exists "événements publiés par les référents" on evenements;
create policy "événements publiés par les référents" on evenements for insert to authenticated with check (peut_publier(acteur_id));
drop policy if exists "événements modifiés par les référents" on evenements;
create policy "événements modifiés par les référents" on evenements for update to authenticated using (peut_publier(acteur_id)) with check (peut_publier(acteur_id));
drop policy if exists "événements supprimés par les référents" on evenements;
create policy "événements supprimés par les référents" on evenements for delete to authenticated using (peut_publier(acteur_id));

drop policy if exists "tout le monde peut signaler" on signalements;
create policy "tout le monde peut signaler" on signalements for insert to anon, authenticated with check (statut = 'en_attente');
drop policy if exists "le modérateur lit les signalements" on signalements;
create policy "le modérateur lit les signalements" on signalements for select to authenticated using (est_moderateur());
drop policy if exists "le modérateur valide ou refuse" on signalements;
create policy "le modérateur valide ou refuse" on signalements for update to authenticated using (est_moderateur()) with check (est_moderateur());
drop policy if exists "le modérateur supprime" on signalements;
create policy "le modérateur supprime" on signalements for delete to authenticated using (est_moderateur());

drop policy if exists "soutenir un signalement publié" on soutiens;
create policy "soutenir un signalement publié" on soutiens for insert to anon, authenticated with check (signalement_publie(signalement_id));

-- 4. DROITS D'ACCÈS ---------------------------------------------------------
grant select on acteurs, plats, evenements to anon, authenticated;
grant select on signalements_publics to anon, authenticated;
grant select on membres to authenticated;
grant insert, update, delete on plats, evenements to authenticated;
grant insert on signalements, soutiens to anon, authenticated;
grant select, update, delete on signalements to authenticated;

-- 5. DONNÉES DE DÉPART ------------------------------------------------------
insert into acteurs (nom, categorie) values
  ('Le Bateau du Rhin','restaurateur'), ('Le Block','restaurateur'), ('Dékalé','restaurateur'),
  ('Boulangerie','commerce'),
  ('Kaleidoscope','lieu_culturel'), ('Galerie Kraemer','lieu_culturel'), ('Les ateliers éclairés','lieu_culturel'),
  ('SPL des Deux Rives','institution'), ('Élue de quartier','institution'),
  ('Associations de quartier','association')
on conflict (nom) do nothing;

-- Deux exemples pour vérifier la connexion (à supprimer plus tard).
insert into evenements (acteur_id, titre, debut, lieu)
  select id, 'Soirée jeux de société (exemple)', now() + interval '7 days', 'Kaleidoscope' from acteurs
  where nom = 'Kaleidoscope' and not exists (select 1 from evenements where titre like '%(exemple)');
insert into plats (acteur_id, titre, prix)
  select id, 'Plat du jour (exemple)', '[prix]' from acteurs
  where nom = 'Dékalé' and not exists (select 1 from plats where titre like '%(exemple)');

-- 6. PLUS TARD (étape 3) : relier un compte à un acteur -----------------------
-- Après avoir créé un utilisateur dans Authentication > Users, remplacez l'adresse e-mail :
-- insert into membres (user_id, acteur_id, role)
--   select u.id, a.id, 'referent' from auth.users u, acteurs a
--   where u.email = 'referent@exemple.fr' and a.nom = 'Dékalé';
-- Pour désigner le modérateur :
-- insert into membres (user_id, acteur_id, role)
--   select id, null, 'moderateur' from auth.users where email = 'moderateur@exemple.fr';
