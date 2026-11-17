# Scripts de la base de données (Supabase)

Ces fichiers permettent de reconstruire la structure de la base **sans données personnelles ni secrets**.
À exécuter dans l'ordre des numéros, dans Supabase > SQL Editor (chaque script peut être relancé sans danger).

| Fichier | Rôle |
|---|---|
| `01-schema.sql` | Tables de base, règles de sécurité (RLS), structures de départ |
| `02-storage.sql` | Espace de stockage des photos |
| `03-forum.sql` | Réponses des habitants, signalements d'abus |
| `04-paroles.sql` | Modération et garde-fou sur les sujets |
| `05-transports.sql` | Arrêts de transport |
| `06-comptes.sql` | Comptes et suppression de compte |
| `07-mise-a-jour-complete-etapes-7-a-12.sql` | Rôles, administrateurs, actualités, noms modifiables, équipes, photos et liens, bons plans |
| `08-securite-urgent.sql` | Vue des sujets en lecture seule, droits inutiles retirés |
| `09-lot1-securite.sql` | Quota des réponses, dates serveur, réponses d'un sujet dépublié, longueurs, plafonds, photos à 500 Ko |

**Avant l'étape 07** : remplacez `VOTRE_ADRESSE_EMAIL@exemple.fr` par l'adresse du propriétaire (le compte doit déjà exister sur le site).
**Avant l'étape 04** : remplacez `ADRESSE_DU_MODERATEUR@exemple.fr` si vous voulez désigner un modérateur de test.

Ne déposez jamais ici de sauvegarde de données, de mot de passe ni de clé secrète : ce dépôt est public.
