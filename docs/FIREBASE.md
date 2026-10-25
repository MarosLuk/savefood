# Save Food · Firebase Authentication

Aplikácia používa názov **Save Food**, iOS Bundle ID aj Android application ID **com.dakoty.savefood** a potvrdený Apple Developer Team **Dakoty Studio / QQ3UCX8XGK**. Projekt Firebase a jeho skutočné konfiguračné súbory používateľ dodá neskôr. Kód je pripravený; žiadne živé Firebase prihlásenie ešte neprebehlo.

Firebase poskytuje Apple/Google identitu a existujúce FCM upozornenia. Objednávky, zásoby, účtovníctvo a oprávnenia ostávajú v Dart API na Hetzneri. Nie je potrebné presúvať ich do Firestore.

## Implementovaný tok

- Google: natívny google_sign_in 7.2.0 na iOS/Androide, Firebase popup na webe. Apple: Firebase Apple provider na mobiloch a popup na webe. Firebase Auth 6.7.1 používa už prítomný Firebase Core 4.15.1.
- Registrácia aj prihlásenie používajú rovnaké tlačidlo. Nová identita v aplikácii vyžaduje aktuálne podmienky; pri odmietnutí nevznikne účet ani relácia v databáze aplikácie. Firebase môže vytvoriť vlastný autentifikačný záznam už počas poskytovateľského prihlásenia.
- Backend overí RS256 podpis z oficiálneho Google X.509 endpointu, kid, projekt/issuer/audience, UID, časy a Google/Apple poskytovateľa. Pri výmene vyžaduje prihlásenie z posledných 10 minút.
- accounts:lookup overí aktuálneho používateľa, poskytovateľa, e-mail, deaktiváciu a validSince. Vymazaná, pozastavená alebo odvolaná identita nevytvorí novú aplikačnú reláciu. Kľúče sa cachujú podľa Cache-Control; stav používateľa sa kontroluje pri každej výmene.
- Identita sa viaže na Firebase projekt + UID. Rovnaký e-mail sa automaticky nespája s existujúcim e-mailovým/priamym OAuth účtom. Používateľ dostane pokyn použiť pôvodné prihlásenie. Google a Apple prepojené pod rovnakým UID vstúpia do rovnakého účtu.
- Firebase ID token sa odošle iba serveru cez HTTPS, neukladá sa do aplikačnej databázy ani vaultu. Klient uloží bežnú odvolateľnú reláciu marketplace. Firebase sa po dokončení alebo zrušení toku odhlási; nemá spustiť tiché prihlásenie do marketplace.
- Zrušenie okna, chyby siete, zamietnuté domény a oneskorené odpovede majú spracovanie. Odpoveď po odhlásení neobnoví účet. Lokálne pozastavenie a serverové roly platia aj pre Firebase používateľov.
- Tlačidlá sa aktivujú iba pri zhode projektu na klientovi/serveri a povolení príslušného poskytovateľa. Bez konfigurácie sa živé úspešné prihlásenie nesimuluje. Priamy OAuth je dostupný aj naďalej podľa pôvodnej serverovej konfigurácie.

Serverový endpoint je `POST /v1/auth/firebase` s `provider`, `idToken` a pri novom účte `legalConsent`. Odpoveď 428 vyžiada aktuálny súhlas a následne sa zopakuje rovnaká výmena bez druhého poskytovateľského okna.

## Čo vytvoriť v projekte

1. V jednom Firebase projekte pridaj **iOS aplikáciu com.dakoty.savefood**, **Android aplikáciu com.dakoty.savefood** a webovú aplikáciu. Názov Save Food. Bundle/package ID musia presne sedieť.
2. Authentication → Sign-in method: povoľ Google a Apple. Google Android potrebuje správne SHA-1/SHA-256 pre vývojový a neskôr produkčný podpis. iOS Google potrebuje client ID a reverznú URL schému z konfigurácie.
3. Apple potrebuje aktivovaný Sign in with Apple pre App ID v tíme QQ3UCX8XGK. Pre web/Android aj Services ID a správny Firebase callback `https://PROJECT_ID.firebaseapp.com/__/auth/handler`. Apple Team ID, Key ID a privátny kľúč poskytovateľa sa nastavujú v bezpečnej konfigurácii Firebase, nie v klientskom JSON.
4. Vo Firebase Authentication nastav Authorized domains pre vlastnú webovú adresu. Pri dočasnej verejnej IPv4 ju treba pridať bez schémy a portu; oficiálny Firebase JS SDK porovnáva IPv4 presne. Skutočný projekt musí túto konfiguráciu akceptovať a popup tok treba overiť. Auth handler používa Firebase doménu, API a web ostávajú na Hetzneri.
5. Dodané GoogleService-Info.plist, google-services.json a webová Firebase konfigurácia sa zapracujú až po kontrole zhodného projektu a identifikátorov. Súbory už sú ignorované v repozitári. iOS má pripravený Sign in with Apple entitlement; certifikát/profil ho musí povoľovať. Reálnu Google reverznú URL schému doplníme z dodaného súboru.

GoogleService-Info.plist ani google-services.json nenahrádzajú Apple provider nastavenie, SHA podpisy, webové povolené domény alebo APNs kľúč. Pred spustením treba v schválených textoch uviesť Firebase ako spracovateľa autentifikačných údajov a určiť postup vymazania aj Firebase autentifikačného záznamu; odstránenie dát aplikácie samo neruší používateľov účet u Apple/Google.

## Konfigurácia po dodaní súborov

Serverové premenné v súkromnej `.env.hetzner` alebo prostredí služby:

~~~dotenv
FIREBASE_AUTH_PROJECT_ID=SKUTOCNY_PROJEKT
FIREBASE_AUTH_API_KEY=WEB_API_KEY_PROJEKTU
FIREBASE_AUTH_GOOGLE_ENABLED=true
FIREBASE_AUTH_APPLE_ENABLED=true
~~~

Toto nie je Firebase Admin private key. Pre accounts:lookup je potrebný API kľúč príslušného projektu; jeho obmedzenia musia povoľovať serverový tok. FCM naďalej používa oddelený serverový service-account súbor. Privátne kľúče nepatria do Flutter konfigurácie.

V ignorovaných `config/app.ios.json`, `app.android.json` a `app.web.json` vyplň podľa `config/app.example.json`:

- API_BASE_URL: verejná HTTPS API adresa na Hetzneri.
- FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_PROJECT_ID, FIREBASE_MESSAGING_SENDER_ID: z príslušnej platformy rovnakého projektu.
- FIREBASE_AUTH_ENABLED: true; FIREBASE_AUTH_DOMAIN: skutočná doména auth handlera projektu.
- GOOGLE_SIGN_IN_CLIENT_ID: príslušné iOS client ID; GOOGLE_SIGN_IN_SERVER_CLIENT_ID: webový OAuth client ID pre natívny tok.
- FIREBASE_VAPID_KEY pre webové FCM, ak bude zapnuté. Prihlásenie samo nevyžaduje povolenie upozornení.

Príklady zostavenia z koreňa projektu:

~~~sh
bash tool/build_hetzner_web.sh PUBLIC_IPV4 config/app.web.json
cd apps/mobile
flutter build apk --release --dart-define-from-file=../../config/app.android.json
flutter build ipa --release --dart-define-from-file=../../config/app.ios.json
~~~

Posledné dva príkazy vyžadujú produkčné podpisy. iOS Firebase konfigurácia a profil musia byť vydané pre nový com.dakoty.savefood; stará aplikácia s pôvodným identifikátorom predstavuje samostatnú inštaláciu. Existujúce aplikačné databázy a interné integračné schémy sa premenovaním nemenia.

## Overenie a zostávajúce kroky

Automatické testy podpisujú lokálne testovacie RSA JWT a simulujú iba oficiálne endpointy. Overujú zlý projekt/podpis/čas/tenant, neoverený e-mail, deaktiváciu/odvolanie/vymazanie, kolíziu e-mailu, Apple relay, súhlas a neskoré odpovede. Testovacie PEM súbory nie sú produkčné poverenia.

Živá aktivácia čaká na projekt, súbory a provider nastavenia. Následne sa overí prvá registrácia aj opakované prihlásenie, zrušenie a odhlásenie na fyzickom iPhone/Androide a webe, Apple skrytý e-mail, Firebase zakázanie/odvolanie účtu, správa údajov a callbacky. Samotný build tieto externé testy nenahrádza.

Oficiálne podklady: [Flutter federated auth](https://firebase.google.com/docs/auth/flutter/federated-auth), [overovanie Firebase ID tokenov](https://firebase.google.com/docs/auth/admin/verify-id-tokens), [REST accounts:lookup](https://firebase.google.com/docs/reference/rest/auth#section-get-account-info), [Apple konfigurácia](https://firebase.google.com/docs/auth/web/apple), [oficiálne overenie IPv4 originu](https://github.com/firebase/firebase-js-sdk/blob/main/packages/auth/src/core/util/validate_origin.ts).
