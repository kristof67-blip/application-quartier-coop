-- Quartier Coop · Étape 3 : relier les comptes aux structures
-- 1) Dans Supabase > Authentication > Users, créez un compte par référent (« Add user » > « Create new user »,
--    cochez « Auto Confirm User ») ou invitez-le par e-mail (« Invite user »).
-- 2) Remplacez ci-dessous les adresses e-mail d'exemple par les vraies, supprimez les lignes inutiles,
--    puis collez le tout dans SQL Editor > « Run ».
-- Un référent et un suppléant peuvent être reliés à la même structure (même nom, deux e-mails).

insert into membres (user_id, acteur_id, role)
select u.id, a.id, v.role
from (values
  ('referent.bateau@exemple.fr',  'Le Bateau du Rhin',        'referent'),
  ('referent.block@exemple.fr',   'Le Block',                 'referent'),
  ('referent.dekale@exemple.fr',  'Dékalé',                   'referent'),
  ('referent.boulangerie@exemple.fr', 'Boulangerie',          'referent'),
  ('referent.kaleidoscope@exemple.fr', 'Kaleidoscope',        'referent'),
  ('referent.kraemer@exemple.fr', 'Galerie Kraemer',          'referent'),
  ('referent.ateliers@exemple.fr', 'Les ateliers éclairés',   'referent'),
  ('referent.spl@exemple.fr',     'SPL des Deux Rives',       'referent'),
  ('referent.elue@exemple.fr',    'Élue de quartier',         'referent'),
  ('referent.assos@exemple.fr',   'Associations de quartier', 'referent'),
  ('suppleant.dekale@exemple.fr', 'Dékalé',                   'suppleant')
) as v(email, nom, role)
join auth.users u on u.email = v.email
join acteurs a on a.nom = v.nom
on conflict do nothing;

-- Le modérateur (utilisé à l'étape 5) :
-- insert into membres (user_id, acteur_id, role)
--   select id, null, 'moderateur' from auth.users where email = 'moderateur@exemple.fr';

-- Pour vérifier qui est relié à quoi :
-- select u.email, a.nom, m.role from membres m join auth.users u on u.id = m.user_id left join acteurs a on a.id = m.acteur_id order by a.nom;
