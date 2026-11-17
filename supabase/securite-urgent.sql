
-- Quartier Coop · CORRECTIF DE SÉCURITÉ URGENT (vue « signalements_publics » ouverte en écriture)
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ». Peut être relancé sans danger.
--
-- PROBLÈME : par défaut, Supabase accorde TOUS les droits (modifier, supprimer…) aux visiteurs sur chaque
-- objet du schéma public, y compris la vue « signalements_publics ». Cette vue s'exécute avec les droits du
-- propriétaire pour compter les soutiens, donc elle ignore les règles de sécurité des tables : un visiteur
-- muni de la clé publique pouvait modifier ou supprimer tous les sujets publiés en passant par elle.
-- CORRECTIF : la vue n'est plus accessible qu'en LECTURE. Le site n'utilise que la lecture de cette vue.
--
-- On retire aussi à tous les visiteurs et habitants les droits techniques inutiles (vider une table, etc.).
-- Les règles de sécurité (RLS) restent le seul garde-fou pour lire, ajouter, modifier ou supprimer des lignes.

-- 1. La vue : lecture seule.
revoke insert, update, delete, truncate, references, trigger on public.signalements_publics from anon, authenticated;
grant select on public.signalements_publics to anon, authenticated;

-- 2. Toutes les tables : plus de droits « vider », « référencer » ni « déclencheur » pour le public.
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('revoke truncate, references, trigger on public.%I from anon, authenticated', t.tablename);
  end loop;
end $$;

-- 3. Pour vérifier (la vue ne doit plus afficher que SELECT) :
--    select grantee, string_agg(privilege_type, ',') from information_schema.role_table_grants
--    where table_name = 'signalements_publics' and grantee in ('anon','authenticated') group by grantee;
