# Notch Buddy — intégrations

Règle d'or : **vérifier la doc officielle au moment d'implémenter**. Les formats ci-dessous sont le plan, pas une garantie. Sources à relire :
- API Claude (Messages, outil de recherche web, modèles) : https://docs.claude.com/en/api/overview
- API publique n8n : `{URL de l'instance}/api/v1/docs` (playground de l'instance de Louis)

---

## 1. Agents de code (retirés)

Claude Code, Codex, Cursor, Gemini CLI, Antigravity et les agents tiers (`coucou_agent`) passaient par un hook (`nb-hook` sur le Mac, `coucou-hook` sous Windows et Linux) et un socket vers l'app : sessions dans l'île, diff en direct, approbations, questions `AskUserQuestion`, saut au terminal. Tout cela a été retiré en novembre 2026, sur toutes les plateformes et sur les téléphones.

Ce qui reste, et pourquoi : celui qui avait ajouté les hooks à la main dans `~/.claude/settings.json` les a toujours. Ce fichier est à lui et l'app ne l'écrit jamais. Au lancement, le Mac remplace donc `~/Library/Application Support/Notchy/nb-hook` par un script qui sort tout de suite (`exit 0`), et efface `nb-hook.py` et `nb.sock` (`AppSupport.retireHookRelay`) : l'agent continue comme si Notchy n'était pas installé. Les entrées du hook peuvent être retirées à la main quand on veut, puis le fichier. Un `statusLine` qui passait par `nb-hook --statusline` (l'ancien relais Plan usage) lance toujours la ligne d'état d'avant, gardée dans `statusline-previous.json`.

Sous Windows et Linux, l'app ne copie plus `coucou-hook`. Une copie déjà dans `%LOCALAPPDATA%\Coucou\bin` (Linux : `~/.local/share/coucou/bin`) reste là où un `settings.json` peut la nommer : sans rien qui écoute, elle sort tout de suite avec 0, sans rien écrire. La désinstallation ne supprime plus ce dossier, sinon chaque événement deviendrait une erreur « command not found ».

---

## 2. n8n (workflows de Louis)

- Réglages : URL de l'instance (probablement `https://n8nlouis.dcsys.tech`, **à confirmer avec Louis**) et clé API n8n (Trousseau). La clé se crée dans n8n : Settings → n8n API.
- Le Mac joint n8n, pas l'inverse : **polling** toutes les 5 s de l'API publique :
  - noms des workflows : `GET /api/v1/workflows` (cache 10 min) ;
  - exécutions récentes : `GET /api/v1/executions` avec filtres de statut et `limit`.
- Mapping :
  - exécution en cours → tâche `working` (si l'API expose les exécutions en cours ; sinon n8n n'apparaît qu'aux erreurs et aux succès, c'est acceptable) ;
  - nouvelle exécution en erreur → alerte `error`, détail = nœud en échec + message (`GET /api/v1/executions/{id}?includeData=true`) ;
  - succès → mini-bonhomme `finished` 3 s en compact, **sans** ouvrir l'island (sinon trop de bruit), sauf réglage contraire.
- Boutons :
  - « Relancer » → endpoint de retry de l'API publique (vérifier sa présence et son chemin dans le playground de l'instance). S'il n'existe pas : ouvrir l'exécution dans n8n.
  - « Ouvrir dans n8n » → ouvrir `{URL}/workflow/{workflowId}/executions/{executionId}` dans le navigateur par défaut.
- Réglage « workflows suivis » : tous par défaut, liste à cocher.

---

## 3. Fichiers déposés

- Glisser-déposer natif sur la panel (types `fileURL`). Copier les fichiers dans `~/Library/Application Support/NotchBuddy/inbox/` (c'est la phase `uploading`).
- Vue `choose` :
  - **Poser une question dessus** → vue `prompt` avec une pastille du fichier. Envoi à l'API Claude (§5) : PDF en bloc `document`, images en bloc `image`, texte et code (≤ 200 Ko) en texte. Autres types : message « Je ne sais pas lire ce format, mais je peux l'envoyer par mail. »
  - **Envoyer par mail** → vue `mail` (§6).
- Nettoyer l'inbox après 7 jours.

---

## 4. Attacher le bonhomme à une fenêtre

1. Au lâcher, trouver la fenêtre sous le point : `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`, première fenêtre de couche 0 qui n'est pas la nôtre et contient le point. Récupérer app, titre, cadre.
2. Afficher le **halo** : une panel transparente, non cliquable, posée sur le cadre de la fenêtre. Bordure conique arc-en-ciel de 3 pt qui tourne en 3 s (`#FF6B5B → #F7B32B → #2DD4A7 → #38BDF8 → #A78BFA → #F472B6`), voile multicolore en mode multiply qui respire (voir `.attach` du prototype), fondu d'entrée 600 ms. Son `attach`, émote Clin d'œil.
3. Contexte envoyé à Claude :
   - capture de la fenêtre avec ScreenCaptureKit (`SCScreenshotManager`), redimensionnée à 1568 px de large max ;
   - si c'est Safari, Chrome, Arc ou Brave : URL et titre de l'onglet actif via AppleScript.
4. Vue `prompt` avec la pastille « Safari, escale.fr » (app + domaine), focus sur le champ.
5. Le halo reste pendant `searching`, disparaît quand le résultat s'affiche ou quand l'island se ferme.

Permissions : Enregistrement de l'écran (capture) et Automatisation (navigateur). Si refusées : on continue sans capture ou sans URL, et on le dit en une ligne dans la vue.

---

## 5. API Claude (recherche)

- `POST https://api.anthropic.com/v1/messages`, en-têtes `x-api-key`, `anthropic-version`, `content-type: application/json` (versions à vérifier dans la doc).
- Modèle par défaut : `claude-sonnet-4-6`, choisi dans Settings → Anthropic API **ou depuis la puce de modèle dans la vue `.prompt`**. La liste est récupérée à l'ouverture des réglages via `GET /v1/models?limit=100` (en-têtes `x-api-key` et `anthropic-version: 2023-06-01`) ; si l'appel échoue ou qu'il n'y a pas de clé, une liste de secours est utilisée (`claude-sonnet-4-6`, `claude-sonnet-5-5`, `claude-opus-5-5`, `claude-haiku-4-5-20251001`). Un champ libre permet d'entrer n'importe quel identifiant. Si le modèle sauvegardé n'est pas dans la liste, le sélecteur reste sur « Custom… ». Dans le chat, si le modèle enregistré n'est pas dans la liste reçue, le premier dont l'identifiant contient « sonnet », sinon le premier de la liste.
- Erreurs de l'API : affiche `error.message` au lieu du JSON brut. Pour un `not_found_error`, affiche « Model not found: \<id\>. Pick another one in Settings. »
- Outil de recherche web côté serveur de l'API : l'identifiant de type à jour est dans la doc (au moment d'écrire, `web_search_20250305`) ; `max_uses` 5.
- Prompt système (français) : répondre court, pour un affichage dans le notch, au format JSON strict :
  ```json
  { "title": "…", "items": [ { "label": "…", "detail": "…", "url": "…" } ], "note": "…" }
  ```
  3 items maximum. Si le JSON est invalide : afficher le texte brut (3 lignes max) dans la vue `result`.
- Contenu du message utilisateur : capture (bloc image) + « URL : … / Titre : … / Demande : … », ou fichier (§3) + demande, ou demande seule (onglet Demander).
- Pendant l'appel : état `searching`, vue `searching`, texte scintillant. Réponse : état `finished`, vue `result`, émote Fier, son `finish`.
- Boutons du résultat : « Ouvrir » (premier lien, seulement s'il est en http ou https ; sinon le bouton est grisé), « Copier » (texte), « Fermer ».
- Erreur réseau ou clé invalide : état `error`, vue `note` avec la raison en une phrase et « Ouvre les réglages pour vérifier la clé ».
- Micro (bouton du champ) : dictée `SFSpeechRecognizer` en `fr-FR`, sur l'appareil si possible. Optionnel (M9). Si la permission est refusée, masquer le bouton.

---

## 5bis. Autres fournisseurs du chat (Google AI, OpenAI)

Clés dans Settings → Chat — other providers (Trousseau : `google-api-key`, `openai-api-key`). La liste des modèles est récupérée à l'ouverture du chat selon le fournisseur :

- **Google AI (Gemini)** : `GET https://generativelanguage.googleapis.com/v1beta/openai/models` (en-tête `Authorization: Bearer <clé>`) — on retire le préfixe `models/`, on filtre les modèles dont l'identifiant contient `embed`, `imagen`, `veo`, `aqa`, `tts`, `audio` ou `live`. Dans le chat, si le modèle enregistré n'est pas dans la liste reçue, le premier dont l'identifiant contient « flash », sinon le premier de la liste. Endpoint du chat : `POST https://generativelanguage.googleapis.com/v1beta/openai/chat/completions`.
- **OpenAI** : `GET https://api.openai.com/v1/models` (en-tête `Authorization: Bearer <clé>`) — triés par champ `created` décroissant, on filtre les modèles dont l'identifiant contient `embed`, `tts`, `whisper`, `dall-e`, `audio`, `realtime`, `moderat`, `codex`, `computer-use`, `transcribe`, `image`, `sora`, `babbage`, `davinci` ou `instruct`. Dans le chat, si le modèle enregistré n'est pas dans la liste reçue, le premier dont l'identifiant contient « mini », sinon le premier de la liste. Endpoint du chat : `POST https://api.openai.com/v1/chat/completions`.

Ce qui est envoyé au fournisseur lors d'un échange : le texte saisi et la conversation en cours. Si une fenêtre est attachée : nom de l'app, titre et URL. Si un fichier est attaché : son nom seulement (le contenu d'un fichier ne part que chez Anthropic).

Voir le catalogue de pastilles dans `docs/SPEC.md` (section « Catalogue de pastilles ») pour les pastilles `ai_google` et `ai_openai`.

---

## 5ter. Modèles locaux (Ollama / LM Studio)

**IDs de pastilles** : `ai_ollama` (jaune `#FACC15`), `ai_lmstudio` (vert citron `#A3E635`)  
**Catégorie** : AI for the chat  
**Plateforme** : macOS uniquement

Connexion à un serveur local compatible OpenAI. Aucune clé d'API requise.

### Connexion

Réglages → Chat → Local models → **Connect**. Coucou envoie une requête `GET /v1/models` au serveur. Si le serveur répond avec des modèles, l'URL est sauvegardée et le fournisseur apparaît dans le sélecteur de modèle. Les modèles d'embedding (`nomic-embed-text`, `bge-*`, etc.) sont filtrés automatiquement.

### Streaming

Les messages sont diffusés token par token via `POST /v1/chat/completions` avec `"stream": true`. Les blocs de raisonnement (`<think>…</think>`, utilisés par des modèles comme DeepSeek-R1) sont masqués dans la bulle de chat tant que le bloc est ouvert, puis retirés de la réponse finale.

### Pièces jointes

Les fichiers texte sont envoyés en ligne, tronqués à 24 000 caractères. Images et PDF : seul le nom du fichier est envoyé.

### Déconnexion

Réglages → Chat → Local models → **Disconnect**. Efface l'URL sauvegardée et le cache des modèles. Si un fournisseur local était actif dans le chat, le chat revient sur Anthropic.

---

## 6. Mail (app Mail du Mac)

- Vue `mail` : À (obligatoire, validation d'adresse), Objet (prérempli : nom du fichier), Message (optionnel, une ligne).
- Envoi uniquement au clic sur « Envoyer », via AppleScript (`NSAppleScript`) sur Mail :
  ```applescript
  tell application "Mail"
    set m to make new outgoing message with properties {subject:"…", content:"…", visible:false}
    tell m
      make new to recipient at end of to recipients with properties {address:"…"}
      make new attachment with properties {file name:(POSIX file "…")} at after the last paragraph of content
    end tell
    delay 1
    send m
  end tell
  ```
  Le `delay` laisse le temps à la pièce jointe d'être prise en compte (comportement connu de Mail). `Info.plist` : `NSAppleEventsUsageDescription`.
- Succès : vue `note` « Mail envoyé à … », émote Clin d'œil, son `send`. Échec : état `error` avec la raison.

---

## 6bis. Le site dans le notch

Une intégration sans pastille : une icône posée à côté du notch ouvre un site dans l'island.

- URL : `https://caus-macbook-pro.tail8e18f9.ts.net/` — une machine du tailnet, donc rien ne sort vers un service tiers. Elle est écrite une seule fois, dans `NotchSite.url` (`NotchBuddy/Sources/App/NotchSite.swift`).
- Pas d'entrée dans `PillCatalog` : la vue ne s'ouvre pas depuis l'island mais depuis l'icône, et aucune vue existante ne change.
- Rendu par `WKWebView`, API publique uniquement (`underPageBackgroundColor` pour le fond autour de la page, jamais `drawsBackground` en KVC). Magasin de données par défaut : une connexion survit à la fermeture de la page.
- Schémas suivis dans l'island : `http`, `https`, `about`, `blob`. Tout le reste est annulé et remis au système — et seulement si la navigation vient d'un clic, pour qu'une page ne puisse pas lancer une app toute seule.
- Aucune permission macOS supplémentaire. Pas de réseau vers autre chose que le site.
- Forme, place et fermeture : §5bis de `SPEC.md`.

---

## 6ter. WhatsApp (le compte de l'utilisateur)

WhatsApp n'a pas d'API pour un compte personnel. L'intégration est donc WhatsApp Web lui-même, gardé ouvert hors de la vue, et un script injecté qui en fait une source de messages comme Mattermost et Ato : carte dans le notch, liste, Home, bannière, réponse.

- **Lien.** Réglages → WhatsApp → « Connect WhatsApp » ouvre la page dans une fenêtre pour scanner le QR code avec le téléphone (Réglages → Appareils connectés → Connecter un appareil). La fenêtre se ferme toute seule une fois l'appareil lié. Pas de mot de passe : la session est celle de WhatsApp Web, dans un magasin de données à elle (`WKWebsiteDataStore(forIdentifier:)` sur le Mac, un profil WebView2 à part sous Windows). « Unlink » efface ce magasin.
- **Quand ça tourne.** Uniquement quand la pastille `integration_whatsapp` est allumée et que la machine a déjà été liée. Sinon rien n'est chargé (`about:blank` sous Windows). Coût assumé : un processus WebKit/WebView2 (~300 Mo) tant que la pastille est allumée, et donc pas 0 % CPU dans ce cas-là. Sur le Mac la page n'est dans aucune fenêtre ; `inactiveSchedulingPolicy = .none` empêche WebKit de la suspendre.
- **Le pont.** `shared/whatsapp-bridge.js`, un seul fichier pour les deux plateformes, injecté au début du document :
  - remplace `Notification` par une version toujours « granted » qui transmet chaque notification au lieu de l'afficher ;
  - dit à la page qu'elle est dans un onglet en arrière-plan (`visibilityState`, `hasFocus`) : c'est ce qui la fait notifier, et ce qui évite de marquer les messages comme lus avant la réponse ;
  - signale `qr` / `connected` / `loading` par un `MutationObserver`, sans polling ;
  - répond : ouvre la conversation (via le `onclick` de la notification, sinon par la recherche), tape le texte et l'envoie, puis colle une image ou dépose tout autre fichier sur la conversation et l'envoie. Un message vocal part comme fichier audio (`.m4a` sur le Mac, `.wav` sous Windows), pas comme note vocale enregistrée dans WhatsApp, qui demanderait de l'Ogg/Opus et l'API interne.
  - Tous les sélecteurs sont dans la table `SELECTORS` en tête du fichier : WhatsApp change son HTML sans prévenir, c'est là qu'on répare.
- **Canal vers l'app.** Mac : `WKScriptMessageHandler` « notchy », et `callAsyncJavaScript` pour répondre. Windows : **aucune IPC** donnée à la page — une capability Tauri pour web.whatsapp.com en ferait une origine distante avec accès aux commandes. Le pont garde ses événements dans une boîte d'envoi et « sonne » en basculant un caractère invisible à la fin du titre ; Rust entend `on_document_title_changed` et vide la boîte avec `eval_with_callback`.
- **Navigation.** Seuls `web.whatsapp.com`, `whatsapp.com`, `whatsapp.net` (et `about:`, `blob:`, `data:`) restent dans la page ; un lien d'un message s'ouvre dans le navigateur. Micro et caméra refusés à la page.
- **Ce n'est pas un client officiel.** C'est de l'automatisation de WhatsApp Web ; Réglages le dit.
- Code : `WhatsAppWebController.swift`, `WhatsAppRules.swift` (pur, testé par `scripts/test-whatsapp-rules.sh`), `windows/src-tauri/src/whatsapp.rs`, et le jumeau Rust dans `message_proto.rs`.

### Pièces jointes vers Ato

Comme dans la console d'agent : chaque fichier part d'abord vers `storageservice-api…/FileUpload/Upload?folder=19` (le dossier `Chat`), champs `file` et `contentType`, qui répond un `StorageObjectId` ; le message porte ensuite le texte et les fichiers dans `Attachments` (`StorageFileId`, `FileName`, `ContentType`, `SizeBytes`). 25 Mo au plus par fichier, comme la console. Un message vocal est un fichier audio parmi les autres.

## 6quater. Agenda (le panneau commercial d'Actuar)

Un onglet de l'île avec les réunions du jour de la personne connectée, lues dans l'Agenda du panneau commercial (`dash-comercial.pages.dev/agenda`, Onboarding et Backoffice), et un rappel qui ouvre l'île avant chacune.

- **Compte.** Celui d'Actuar que garde déjà Ato : le panneau se connecte avec le même e-mail et le même condensat `md5(e-mail + mot de passe)`. Mais avec son propre `AppSource` (`Actuar,FacilFit,Ediz`), donc dans une paire de jetons à lui (`AgendaTokenStore`, clés `agenda-token` sous Windows) : deux clients qui rafraîchissent depuis le même `TokenId` s'invalideraient l'un l'autre. Mêmes garde-fous qu'Ato : une connexion complète par minute au plus, pas de nouvel essai d'un mot de passe refusé tant qu'il ne change pas.
- **Lecture.** Une passerelle façon PostgREST : `POST https://query-gateway.actuar.group/rest/v1/rpc/<nom>` avec le jeton en `Bearer`. `get_current_organization_context` donne le `person_id`, puis les deux listes que lit l'Agenda du panneau, filtrées sur la personne comme le bouton « Eu » : `get_onboarding_board_cards_v1` et `get_backoffice_cases`, paginées. Toutes les dix minutes tant que l'Agenda est allumée, au réveil, juste après minuit et à l'ouverture de l'onglet — le panneau, lui, relit chaque minute.
- **La règle.** Une réunion est à toi aujourd'hui quand sa tentative *effective* (`isEffective`) commence aujourd'hui et que le responsable de la réunion est toi ; les autres tentatives sont l'historique (« remarcada ») et ne s'affichent pas. Le processus est celui de l'étape (`contact` = Backoffice, le reste = Onboarding), pas de la liste. Le titre est `customer_name` sans le code de cas (« GM3941 »), qui devient la puce. Vérifié contre ce que l'Agenda dessinait le 2026-11-19 : `tests/fixtures/agenda/`, noms et identifiants remplacés.
- **Le rappel.** Une seule échéance, sur l'horloge murale, pour la prochaine réunion (15 minutes avant par défaut : 5, 10, 15, 30 ou 60 au choix). Si la dernière lecture a plus de deux minutes, on relit d'abord, pour ne pas annoncer une réunion annulée ou déplacée. Chaque tentative n'est annoncée qu'une fois par jour, même après un redémarrage. Les deux processus sont toujours listés ; Réglages choisit lesquels ouvrent l'île.
- **Rien ne tourne** tant que l'Agenda est éteinte (c'est le cas par défaut : c'est un outil Actuar). Entre deux lectures, rien qu'une échéance.
- Code : `AgendaRules.swift` (pur, testé par `scripts/test-agenda-rules.sh`), `AgendaClient.swift`, `AgendaView.swift`, et sous Windows `agenda_proto.rs` (le jumeau, mêmes fixtures), `agenda.rs`, `windows/src/core/agendaRules.ts` (l'horloge, testée sous Node), `windows/src/island/agenda.ts`, `windows/src/views/agenda.ts`.

---

## 7. Permissions macOS demandées (récapitulatif pour Louis)

| Permission | Pourquoi | Quand |
|---|---|---|
| Automatisation → Mail | envoyer les mails | premier envoi |
| Automatisation → navigateur | lire l'URL de l'onglet | première utilisation |
| Enregistrement de l'écran | capturer la fenêtre attrapée | première attache |
| Micro + Reconnaissance vocale (optionnel) | dictée | premier clic sur le micro |

Aucune permission Accessibilité nécessaire.


