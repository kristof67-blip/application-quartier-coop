-- Quartier Coop · Étape 5 bis : échanges entre habitants (réponses sous les signalements)
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ». Peut être relancé sans danger.
-- Principe : lecture libre ; pour répondre, un compte (e-mail privé) et un pseudo public.
-- Modération après publication : bouton « Signaler » ; à 3 signalements différents, le message est masqué
-- automatiquement jusqu'à décision du modérateur.

-- 1. TABLES -----------------------------------------------------------------
create table if not exists profils (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pseudo text not null check (
    char_length(pseudo) between 3 and 24
    and pseudo ~ '^[A-Za-zÀ-ÿ0-9 _.-]+$'
    and pseudo !~* '(mod[eé]rat|admin|[eé]lue)'
  ),
  created_at timestamptz not null default now()
);
create unique index if not exists profils_pseudo_unique on profils (lower(pseudo));

create table if not exists reponses (
  id uuid primary key default gen_random_uuid(),
  signalement_id uuid not null references signalements(id) on delete cascade,
  auteur uuid not null default auth.uid() references profils(user_id) on delete cascade,
  texte text not null check (char_length(texte) between 2 and 500),
  masquee boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists reponses_fil on reponses (signalement_id, created_at);

create table if not exists alertes (
  reponse_id uuid not null references reponses(id) on delete cascade,
  auteur uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (reponse_id, auteur)
);

-- 2. GARDE-FOUS -------------------------------------------------------------
-- Au plus 10 réponses par heure et par habitant.
create or replace function limite_reponses() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from reponses where auteur = new.auteur and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Trop de messages en peu de temps, réessayez plus tard';
  end if;
  return new;
end
$$;
drop trigger if exists limite_reponses_avant on reponses;
create trigger limite_reponses_avant before insert on reponses
  for each row execute function limite_reponses();

-- Masquage automatique à 3 signalements d'habitants différents.
create or replace function masque_si_signale() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from alertes where reponse_id = new.reponse_id) >= 3 then
    update reponses set masquee = true where id = new.reponse_id;
  end if;
  return new;
end
$$;
drop trigger if exists masque_si_signale_apres on alertes;
create trigger masque_si_signale_apres after insert on alertes
  for each row execute function masque_si_signale();

-- Droit à l'effacement : chacun peut supprimer son compte (et ses réponses) en un clic.
create or replace function supprimer_mon_compte() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'Non connecté'; end if;
  delete from auth.users where id = auth.uid();
end
$$;
revoke all on function supprimer_mon_compte() from public, anon;
grant execute on function supprimer_mon_compte() to authenticated;

-- 3. SÉCURITÉ (RLS) ---------------------------------------------------------
alter table profils enable row level security;
alter table reponses enable row level security;
alter table alertes enable row level security;

drop policy if exists "pseudos lisibles" on profils;
create policy "pseudos lisibles" on profils for select using (true);
drop policy if exists "créer son pseudo" on profils;
create policy "créer son pseudo" on profils for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "modifier son pseudo" on profils;
create policy "modifier son pseudo" on profils for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "réponses visibles par tous" on reponses;
create policy "réponses visibles par tous" on reponses for select using (masquee = false);
drop policy if exists "le modérateur lit toutes les réponses" on reponses;
create policy "le modérateur lit toutes les réponses" on reponses for select to authenticated using (est_moderateur());
drop policy if exists "répondre à un signalement publié" on reponses;
create policy "répondre à un signalement publié" on reponses for insert to authenticated
  with check (auteur = auth.uid() and masquee = false and signalement_publie(signalement_id));
drop policy if exists "le modérateur modère les réponses" on reponses;
create policy "le modérateur modère les réponses" on reponses for update to authenticated
  using (est_moderateur()) with check (est_moderateur());
drop policy if exists "supprimer sa réponse ou modérer" on reponses;
create policy "supprimer sa réponse ou modérer" on reponses for delete to authenticated
  using (auteur = auth.uid() or est_moderateur());

drop policy if exists "signaler une réponse" on alertes;
create policy "signaler une réponse" on alertes for insert to authenticated with check (auteur = auth.uid());
drop policy if exists "le modérateur lit les alertes" on alertes;
create policy "le modérateur lit les alertes" on alertes for select to authenticated using (est_moderateur());
drop policy if exists "le modérateur supprime les alertes" on alertes;
create policy "le modérateur supprime les alertes" on alertes for delete to authenticated using (est_moderateur());

-- 4. DROITS D'ACCÈS ---------------------------------------------------------
grant select on profils, reponses to anon, authenticated;
grant insert, update on profils to authenticated;
grant insert, update, delete on reponses to authenticated;
grant select, insert, delete on alertes to authenticated;

-- Pour vérifier :  select count(*) from profils;  select count(*) from reponses;
