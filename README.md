# FlowsX — créateur d'APK

Interface française mobile-first pour envoyer un lien web, un fichier HTML ou un ZIP à un workflow GitHub Actions qui compile un APK Android de test.

## Architecture
- Frontend Vite statique déployable sur Vercel.
- `/api/build` reçoit le formulaire, place HTML/ZIP dans Vercel Blob et déclenche GitHub Actions.
- `.github/workflows/build-apk.yml` construit un APK debug avec Gradle et publie l'APK comme artefact GitHub Actions pendant 7 jours.

## Déploiement
1. Crée un dépôt GitHub nommé `flowsx`, ajoute tous les fichiers de ce projet et pousse la branche `main`.
2. Sur GitHub, crée un Fine-grained Personal Access Token limité à ce dépôt, avec **Actions: Read and write** et **Contents: Read-only**. Ne le mets jamais dans le code source.
3. Importe le dépôt dans Vercel. Framework preset : Vite. Build command `npm run build`; output directory `dist`.
4. Dans Vercel > Settings > Environment Variables, ajoute les variables de `.env.example`. Crée un Vercel Blob Store et copie son `BLOB_READ_WRITE_TOKEN`. Redéploie après les changements.
5. Dans GitHub, ouvre Actions et autorise les workflows si demandé. Lance un premier test avec un site HTTPS public.
6. Quand le workflow finit, ouvre son run, puis **Artifacts** pour télécharger l'APK.

## Important / limites actuelles
- L'APK est un **APK debug non signé pour distribution**, téléchargeable via l'artefact GitHub; le lien du run ne se télécharge pas automatiquement depuis l'interface FlowsX. Une prochaine version peut interroger GitHub et fournir un bouton de téléchargement.
- Le token GitHub reste côté serveur Vercel. N'ajoute jamais `VITE_GITHUB_TOKEN`.
- Les uploads passent par Vercel Blob public temporaire : évite les fichiers privés, secrets ou données personnelles. Configure une politique de rétention/suppression.
- Le workflow télécharge la source et exécute une compilation distante. N'accepte que des projets de confiance. Le ZIP est contrôlé contre les chemins de traversée et limité à 150 MiB décompressés.
- Le mode lien affiche un site distant dans Android WebView; il ne convertit pas magiquement le site en application native. Le site doit autoriser l'intégration et être compatible mobile.
- Le mode HTML copie un seul fichier HTML; les ressources externes doivent être accessibles par URL. Pour plusieurs fichiers, utilise ZIP avec `index.html` à la racine.
- Le mode ZIP sert les fichiers locaux via AndroidX WebViewAssetLoader. Teste les chemins relatifs de ton site; les applications web complexes peuvent nécessiter des adaptations.
- Pas de signature release, publication Play Store, icônes personnalisées, mises à jour automatiques, permissions caméra/notifications, ni vérification antivirus.
- L'API doit être durcie avant ouverture publique : authentification/rate limiting, quotas, validation MIME robuste et nettoyage automatique des blobs.
- Android SDK/Gradle version et actions GitHub peuvent évoluer; vérifie le workflow si les builds échouent.

## Page d'accès TikTok + YouTube
- Le modèle `public/unlock.html` présente les comptes TikTok `@kawaki227` et YouTube `@kawaki-227`.
- Pour l'utiliser, remplace `APK_DOWNLOAD_URL` dans ce fichier par le lien HTTPS direct vers l'APK que tu veux distribuer, puis redéploie sur Vercel.
- Après un clic sur chaque bouton, le délai de 10 secondes démarre et le bouton de téléchargement s'active.
- Limite importante : le modèle confirme seulement les clics et l'attente, il ne peut pas prouver qu'une personne s'est réellement abonnée. Ne présente pas cette étape comme une vérification réelle d'abonnement.

## Local development
```bash
npm install
npm run dev
```
L'API serverless nécessite Vercel (`vercel dev`) et les variables configurées.

## Licence
MIT — voir LICENSE.


## Page de soutien avant téléchargement
- Une page mobile est disponible à `/download.html`.
- Elle propose les profils TikTok `@kawaki227` et YouTube `@kawaki-227`, puis attend 10 secondes après l'ouverture des deux liens.
- Pour afficher un vrai bouton de téléchargement, passe une URL HTTPS vers l'APK : `/download.html?apk=https%3A%2F%2Fexample.com%2Fmon-app.apk`.
- **Cette page ne peut pas confirmer l'abonnement réel.** Elle se base sur les clics et le compte à rebours; un utilisateur peut contourner cette étape. L'API officielle YouTube permet de lire les abonnements d'un utilisateur authentifié avec autorisation, mais cela exige un flux OAuth et ne permet pas simplement de vérifier n'importe quel visiteur. Les accès TikTok sont également soumis aux produits/scopes et à l'approbation de l'application. Voir la documentation officielle YouTube: https://developers.google.com/youtube/v3/docs/subscriptions/list et TikTok: https://developers.tiktok.com/docs/en/getting-started-create-an-app.
- Ne publie pas la page avec un faux message indiquant que l'abonnement a été vérifié. La page indique clairement ce qu'elle contrôle.
