-- Quartier Coop · Étape 6 (transports), partie 1 : la liste des arrêts à afficher
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ». Peut être relancé sans danger.
-- Les codes officiels des arrêts (colonne code_cts) seront ajoutés quand vous aurez le token de la CTS.

create table if not exists arrets (
  id uuid primary key default gen_random_uuid(),
  nom text not null unique,
  mode text not null check (mode in ('tram','bus')),
  code_cts text,                      -- code de l'arrêt dans l'API de la CTS (à renseigner plus tard)
  actif boolean not null default false,
  ordre integer not null default 0,
  created_at timestamptz not null default now()
);

alter table arrets enable row level security;

drop policy if exists "arrêts actifs lisibles par tous" on arrets;
create policy "arrêts actifs lisibles par tous" on arrets for select using (actif = true);
drop policy if exists "le modérateur lit tous les arrêts" on arrets;
create policy "le modérateur lit tous les arrêts" on arrets for select to authenticated using (est_moderateur());
drop policy if exists "le modérateur gère les arrêts" on arrets;
create policy "le modérateur gère les arrêts" on arrets for all to authenticated
  using (est_moderateur()) with check (est_moderateur());

grant select on arrets to anon, authenticated;
grant insert, update, delete on arrets to authenticated;

insert into arrets (nom, mode, ordre) values
  ('Starcoop', 'tram', 1),
  ('Capitainerie', 'bus', 2),
  ('Coopérative', 'bus', 3)
on conflict (nom) do nothing;

-- Pour vérifier :  select nom, mode, code_cts, actif from arrets order by ordre;
