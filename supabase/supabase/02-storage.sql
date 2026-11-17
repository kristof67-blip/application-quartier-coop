-- Quartier Coop · Étape 4 : stockage des photos de plats (Supabase Storage)
-- À coller dans SQL Editor > « Create a new snippet », puis « Run ». Peut être relancé sans danger.

-- 1. Espace « photos-plats » : lecture publique, une seule image JPEG de 500 Ko maximum par fichier.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos-plats', 'photos-plats', true, 524288, array['image/jpeg'])
on conflict (id) do update
  set public = true, file_size_limit = 524288, allowed_mime_types = array['image/jpeg'];

-- 2. Qui peut déposer ou supprimer : uniquement un référent ou suppléant, et seulement dans le
--    dossier de sa structure (le premier dossier du chemin est l'identifiant de l'acteur).
drop policy if exists "photos plats : dépôt par les référents" on storage.objects;
create policy "photos plats : dépôt par les référents" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'photos-plats'
    and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and peut_publier(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "photos plats : suppression par les référents" on storage.objects;
create policy "photos plats : suppression par les référents" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'photos-plats'
    and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and peut_publier(((storage.foldername(name))[1])::uuid)
  );

-- La lecture n'a pas besoin de règle : le bucket est public, chaque photo a une adresse publique.
-- Pour vérifier :  select id, public, file_size_limit, allowed_mime_types from storage.buckets;
