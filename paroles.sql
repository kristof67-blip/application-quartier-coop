-- Quartier Coop · Étape 5 : paroles des habitants et modération
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ».
-- AVANT de l'exécuter : créez le compte du modérateur dans Authentication > Users
-- (« Add user », « Create new user », cochez « Auto Confirm User »), avec l'adresse ci-dessous.

-- 1. Désigner le modérateur (remplacez l'adresse si vous en utilisez une autre).
insert into membres (user_id, acteur_id, role)
select u.id, null::uuid, 'moderateur'
from auth.users u
where u.email = 'kristof67+modo@gmail.com'
  and not exists (select 1 from membres m where m.user_id = u.id and m.role = 'moderateur');

-- 2. Garde-fou : pas plus de 100 signalements en attente à la fois (évite le déluge de messages).
create or replace function limite_signalements() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from signalements where statut = 'en_attente') >= 100 then
    raise exception 'Trop de signalements en attente, réessayez plus tard';
  end if;
  return new;
end
$$;

drop trigger if exists limite_signalements_avant on signalements;
create trigger limite_signalements_avant
  before insert on signalements
  for each row execute function limite_signalements();

-- 3. Pour vérifier :
-- select u.email, m.role from membres m join auth.users u on u.id = m.user_id where m.role = 'moderateur';
-- select statut, count(*) from signalements group by statut;
