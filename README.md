# Quartier Coop — la webapp des habitants

> Informer, relier et donner la parole à tout un quartier.

**Quartier Coop** est un projet de site web et d'application mobile (webapp) pour les habitants, les commerçants, les lieux culturels et les institutions du quartier Coop. Elle rassemble au même endroit ce qui est aujourd'hui dispersé : événements, plats du jour, actualités, transports, signalements d'habitants, marchés et fêtes à proximité.

**Simulation en ligne :** https://kristof67-blip.github.io/application-quartier-coop/

> ⚠️ **Ce dépôt contient une simulation, pas encore le site définitif.** Tous les contenus affichés (plats, dates, horaires, passages de transport, publications) sont **fictifs**. Rien de ce qui est saisi dans la simulation n'est enregistré : tout disparaît au rechargement de la page.

## Pour qui ?

- **Les habitants** : savoir ce qui se passe près de chez soi, signaler un problème, soutenir les idées des voisins.
- **Les commerçants** : Le Bateau du Rhin, Le Block, Dékalé, la boulangerie… publient leur plat du jour (avec photo), leurs événements et leurs bons plans.
- **Les lieux culturels et de fabrication** : Kaleidoscope (tiers lieu), galerie Kraemer, Les ateliers éclairés (fab lab, maker space, ateliers d'artistes) annoncent expositions, portes ouvertes et initiations.
- **Les institutions et associations** : la SPL des Deux Rives (réunions d'information, avancement des chantiers), l'élue de quartier (actualités, rendez-vous) et les associations de quartier (événements, réunions, appels à bénévoles).

## Ce que montre la simulation

| Rubrique | Contenu |
|---|---|
| **Accueil** | Alertes, plats du jour en photo, bons plans, prochains événements, élue de quartier, marchés et fêtes à proximité |
| **Agenda** | Événements de tous les acteurs, filtrables par lieu |
| **Transports** | Prochains passages aux arrêts du quartier (données d'exemple) |
| **Paroles** | Signalements d'habitants, bouton « Moi aussi », modération avant publication |
| **Plus** | Ateliers éclairés, galerie Kraemer, avancement des projets, annuaire pratique, abonnements, confort de lecture, règles |
| **Espace annonceur** | Un profil par acteur (restaurateurs, commerces, lieux culturels, institutions, associations de quartier, modérateur) : publier, modifier, supprimer, voir les vues |
| **Écran d'affichage** | Version paysage pour la télévision de Kaleidoscope, avec défilement automatique |
| **Langues** | Français, anglais, allemand (menus et boutons principaux) |

## Feuille de route

1. **Version 1 — démarrer simple** : agenda commun, plats du jour avec photos, actualités de l'élue et de la SPL des deux rives, annuaire pratique.
2. **Version 2 — faire participer** : parole des habitants, transports en commun, galerie et ateliers éclairés, marchés et fêtes.
3. **Version 3 — faire vivre** : écran d'affichage à Kaleidoscope ?, parcours d'art, mémoire du quartier, petites annonces et entraide.

**Prochaines étapes :** valider avec les acteurs pilotes, choisir l'outil de création de la version définitive, réserver le nom de domaine, désigner un modérateur.

## Principes du projet

- **Accessible à tous** : grandes polices, contrastes forts, mots simples ; options « texte agrandi » et « contraste renforcé ».
- **Données personnelles minimales** : aucun compte n'est nécessaire pour lire, pas de publicité, pas de revente de données. *(Cadre RGPD à faire valider — responsable du traitement : [à désigner].)*
- **Modération** : les signalements des habitants sont relus par un modérateur désigné par le collectif avant publication *(délai : [à définir])*.
- **Référents par structure** : chaque acteur désigne un référent et un suppléant autorisés à publier, pour que le site reste vivant si une personne part.
- **Charte de contribution** : sont refusés les propos injurieux ou discriminatoires, les données personnelles de tiers, la publicité extérieure au quartier et les informations non vérifiées.

## Contenu du dépôt

| Fichier | Rôle |
|---|---|
| `index.html` | La simulation complète (une seule page, sans installation) |
| `README.md` | Ce document |

## Tester la simulation

- **En ligne** : ouvrez le lien de la simulation ci-dessus, sur téléphone ou ordinateur.
- **En local** : téléchargez `index.html` et ouvrez-le dans un navigateur (Chrome, Firefox, Safari, Edge).

Pour essayer l'espace annonceur : touchez **« Espace pro »** dans le bandeau orange, choisissez un profil, puis publiez un plat ou un événement et retournez à l'accueil.

## Contribuer

Toutes les bonnes volontés sont bienvenues, avec ou sans compétences techniques.

- **Vous avez une idée, un défaut à signaler, une fonction à demander ?** Ouvrez une [issue](../../issues) en décrivant simplement votre besoin.
- **Vous codez ?** Faites un *fork* du dépôt, proposez vos changements dans une branche, puis ouvrez une *pull request*. Elle sera relue avant d'être intégrée : la branche `main` n'est pas modifiable directement.
- **Vous représentez un commerce, un lieu, une association ou une institution ?** Écrivez-nous pour devenir acteur pilote : christophe@quartiercoop.fr.

## Limites connues de la simulation

- Les publications ne sont pas conservées (pas de base de données).
- Les profils annonceurs n'ont ni mot de passe ni validation : ce sera prévu dans la version définitive.
- Les horaires de transports et des marchés sont des données d'exemple ou à confirmer.
- La traduction ne couvre pas les contenus publiés par les acteurs.
- Les polices sont chargées depuis Google Fonts ; la version définitive devra les héberger elle-même pour limiter les échanges avec des tiers.

## Licence

[À choisir ultérieuremenent — par exemple MIT pour le code, CC BY pour les textes et illustrations. Sans licence, personne n'a le droit de réutiliser le contenu.]

## Contact

Christophe DOUNIAU christophe@quartiercoop.fr
