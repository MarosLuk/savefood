# Prevádzka a integrácie

Potvrdený hosting je Hetzner, dočasne HTTPS na verejnej IP. Konkrétna konfigurácia a postup sú v [HETZNER.md](HETZNER.md); platby ostávajú vypnuté. Doklady za potraviny vystavuje predajňa, fakturačný model určuje `BILLING_SELLER_MODEL=merchantSeller`.

## API a dáta

`apps/api/.env.example` obsahuje všetky serverové premenné. Skopíruj ho do ignorovaného `apps/api/.env`; server číta prostredie, súbor nenačítava sám. `tool/dev.sh` ho načíta pri lokálnom spustení. V produkcii premenné nastav správcom tajomstiev hostingu.

- `APP_ENV=production`, `PAYMENT_MODE=stripe`, `SEED_DEMO=false`, `PUBLIC_URL` a `APP_URL` na HTTPS. Nesprávnu kombináciu server odmietne pri štarte.
- `HOST=0.0.0.0`, `PORT=8080`, `DATABASE_PATH` na trvalom disku; `ALLOWED_ORIGINS` presný zoznam webových originov oddelený čiarkami.
- SQLite WAL a transakcie sú určené pre jeden serverový proces s trvalým diskom. Neškáluj kópie s oddelenou databázou. Ďalším krokom pri väčšej záťaži je zdieľaná PostgreSQL databáza a samostatný worker.
- Zálohuj SQLite online backup mechanizmom alebo so zastaveným procesom vrátane potrebných WAL súborov. Obnovenie si vyskúšaj pred prevádzkou. Katalóg, účty, kredit aj objednávky sú serverové dáta.
- Reverzný proxy terminujúci TLS má limitovať požiadavky a odstrániť nedôveryhodné `X-Forwarded-For`; API obmedzuje veľkosť tela a pokusy o prihlásenie. Nasadenie nie je vykonané.

Server možno zabaliť z koreňa cez `docker build -f apps/api/Dockerfile -t nevyhadzuj-api .`; `docker compose up --build` spustí lokálny sandbox s trvalým volume. Docker súbory sú pripravené; samotný image nebol v tomto prostredí spustený. Samostatný natívny server bol zostavený cez `dart compile exe apps/api/bin/server.dart`.

## API rozhranie

JSON, UTC ISO 8601 dátumy, peniaze v celých centoch EUR. Chyba: `{"error":"správa"}` a príslušný HTTP status. Prihlásené požiadavky majú `Authorization: Bearer <token>`.

| Metóda a cesta | Správanie |
|---|---|
| `GET /health`, `GET /v1/config` | Stav a verejné schopnosti; tajné kľúče sa nevracajú |
| `GET /v1/catalog`, `GET /v1/places?q=...&lang=sk` | Dostupnosť a adresy |
| `POST /v1/auth/register` | `{name,email,password}`, relácia; heslo aspoň 10 znakov |
| `POST /v1/auth/login`, `POST /v1/auth/logout` | Prihlásenie heslom, revokácia aktuálnej relácie |
| `POST /v1/auth/oauth/<provider>` | URL, ID handoffu a tajomstvo pre jednorazové pollovanie |
| `GET/POST /v1/auth/oauth/<provider>/callback` | Registrovaný callback poskytovateľa |
| `POST /v1/auth/oauth/poll/<id>` | `{pollSecret}`, dokončenie prihlásenia v aplikácii |
| `GET/PATCH /v1/me` | Profil; iba povolené meno/fakturačné údaje/obľúbené/súhlasy |
| `GET/POST /v1/orders` | História alebo checkout `{idempotencyKey,items:[{offerId,quantity}],invoice,coupon,useCredit,paymentFlow?}`; `hosted` predvolene alebo `native` |
| `POST /v1/orders/<id>/payment-sheet` | Autorizované natívne platobné údaje, bez uloženia a cache |
| `POST /v1/orders/<id>/refresh` | Overenie platby na serveri |
| `POST /v1/orders/<id>/collect` | `{pickupCode,offerId?}`; bez offerId celá objednávka |
| `POST /v1/orders/<id>/cancel` | Storno + vrátenie kreditu a refundácia |
| `POST /v1/club/trial` | `{code}`; jedna skúška, prázdny kód alebo KLUB30 |
| `POST /v1/club/checkout`, `POST /v1/club/cancel` | Platený plán alebo vypnutie obnovovania |
| `GET/POST /v1/offers/<id>/reviews` | Overené recenzie; `{rating:1..5,comment}` po prevzatí; opakovanie upraví vlastnú recenziu |
| `POST /v1/devices`, `/v1/devices/remove` | `{token,platform}` a odregistrovanie relácie |
| `POST /v1/admin/offers` | JSON `FoodOffer`, samostatný admin bearer token |
| `POST /v1/payments/webhook` | Výhradne Stripe podpis nad pôvodným telom |

Schéma ponuky je v `packages/marketplace_domain/lib/src/models.dart`; vzor možno získať z `/v1/catalog` v sandboxe. `ADMIN_TOKEN` nastav na náhodnú hodnotu aspoň 32 znakov, používaj iba zo správcovského prostredia. Pri reálnych ponukách používaj HTTPS URL vlastnej fotografie, platné súradnice, časy s pásmom, reálne ceny a alergény. `stock` je celková kapacita daného času vyzdvihnutia; API odpočíta rezervácie. Nový termín má nový `pickupStart`. Automatické seedovanie je v produkcii vypnuté.

## Stripe

Nastav `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`; pre klub aj `STRIPE_CLUB_PRICE_ID` aktívneho opakovaného EUR Price. UI číta cenu a interval zo servera, nemá natvrdo deklarovanú cenu predplatného. Na iOS/Androide je dostupné natívne platobné okno s kartou VISA a Apple Pay/Google Pay, web používa hosted pokladňu. Aktiváciu vrátane STRIPE_PUBLISHABLE_KEY a merchant nastavení opisuje [návod na platby](PLATBY.md); aplikácia nespracúva číslo karty. Wallet kredit je interný kredit, nie peňažný účet s výberom.

Zaregistruj webhook `https://<api>/v1/payments/webhook` pre `payment_intent.succeeded`, `payment_intent.canceled`, `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `customer.subscription.updated`, `customer.subscription.deleted`. Stav objednávky sa overuje aj návratom do aplikácie a tlačidlom overenia platby. Nezaplatené rezervácie sa pri ďalšom čítaní katalógu/účtu/objednávok uvoľnia po 30 minútach. Server pred uvoľnením skontroluje platobnú bránu. Platobný návrat sám nepotvrdzuje zaplatenie.

Storno pred začiatkom vyzdvihnutia odošle refundáciu kartovej platby; pripísanie na banku závisí od Stripe/banky. Čiastočne prevzatá objednávka sa nedá zrušiť naraz. Skúška Klubu sa sama nemení na platenú. Platené členstvo používa Stripe Subscription, obnovovanie sa dá vypnúť a výhody trvajú do konca obdobia. Cashback je 10 % balíčkov po kupóne, bez servisného poplatku; súčasná vlastná politika nemá mesačný limit.

Oficiálne podklady: [Checkout a plnenie](https://docs.stripe.com/checkout/fulfillment), [podpisy webhookov](https://docs.stripe.com/webhooks/signature), [predplatné](https://docs.stripe.com/billing/subscriptions/overview). HTTP formuláre, refundácia, podpis a predplatné sú testované náhradami poskytovateľa; ostrá transakcia nebola vykonaná.

## Google, Apple a Facebook

Nastav príslušný pár `GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET`, `APPLE_CLIENT_ID/APPLE_CLIENT_SECRET`, `FACEBOOK_APP_ID/FACEBOOK_APP_SECRET`. App ukáže iba nakonfigurovaných poskytovateľov. Callback pre každého je `${PUBLIC_URL}/v1/auth/oauth/<google|apple|facebook>/callback`; zapíš ho do jeho vývojárskej konzoly.

Google používa webový OAuth klient, Apple Services ID a podpísaný client-secret JWT, ktorý musí správca obnovovať pred expiráciou; Facebook webový OAuth. OAuth sa odohráva v systémovom prehliadači. Pri návrate alebo tlačidlom dokončenia aplikácia jednorazovo prevezme reláciu cez tajomstvo handoffu. Server kontroluje stav, nonce, issuer, audience, expiráciu, podpis tokenu a overenie e-mailu. Účty s rovnakým e-mailom sa automaticky nezlučujú. Živá autentifikácia nebola vykonaná bez príslušných účtov.

## Adresy, mapy a poloha

`GEOCODER_URL` je Photon kompatibilný `/api/` endpoint. Vývojový štart cez `fromEnvironment` používa `https://photon.komoot.io/api/`; požiadavky sú oneskorené o 600 ms a výsledky server cachuje. V produkcii nastav vlastný alebo zmluvný geocoder. Verejná Photon ukážka nemá garanciu dostupnosti a obmedzuje záťaž ([podmienky a API](https://github.com/komoot/photon)). Bez geocodera zostáva výber známej prevádzky, GPS a bodu na mape. Mapové dlaždice OpenStreetMap potrebujú internet, atribúcia je súčasťou mapy. Predvolený OSM podklad sa pre tmavý režim farebne upraví. V `config/app.json` možno nastaviť `MAP_TILE_URL`, `MAP_DARK_TILE_URL`, `MAP_ATTRIBUTION` a `MAP_ATTRIBUTION_URL` pre vlastného poskytovateľa. Na produkčnú záťaž použi vlastné/zmluvné podklady; verejný OSM server nemá SLA. Cache zabezpečuje flutter_map 8.3 na natívnych platformách a prehliadač na webe; bez sťahovania máp vopred. [Pravidlá OSM dlaždíc](https://operations.osmfoundation.org/policies/tiles/). Verejný Photon nepodporuje jazykový kód sk, preto sa žiadajú pôvodné miestne názvy cez lang=default; angličtina používa lang=en.

Poloha sa vyžiada iba po aktivácii tlačidla používateľom. V produkčnom webe GPS vyžaduje HTTPS; localhost slúži na vývoj. Android/iOS oprávnenia sú pripravené. Sledovanie na pozadí sa nepoužíva.

## Firebase a pripomienky

Lokálne pripomienky vyzdvihnutia sú natívne a po povolení OS sa plánujú 30 minút pred začiatkom. Android používa nepresný režim, systém môže doručenie posunúť. Na webe sa natívne pripomienky neplánujú.

Pre nové obľúbené balíčky nastav serverový `FIREBASE_SERVICE_ACCOUNT_FILE` na súbor mimo repozitára s právom odosielať FCM. App zostav s vlastným `config/app.json` podľa `config/app.example.json`, napríklad `flutter run --dart-define-from-file=../../config/app.json` z `apps/mobile`. `FIREBASE_APP_ID` je pre každú platformu iné; použi samostatné konfiguračné súbory pre iOS/Android/web. **Tajný service account ani Stripe secret nepatrí do app konfigurácie.**

iOS: zapni Push Notifications pre svoj App ID, nahraj APNs `.p8` kľúč do Firebase, nastav Team a provisioning, pri distribúcii over produkčný `aps-environment` v podpise. Background remote notifications a entitlements sú pripravené. Android potrebuje Google Play Services a systémové povolenie notifikácií. FCM automatická inicializácia je do súhlasu vypnutá. Relácia sa pri odhlásení odregistruje a klient zruší token. Server pred doručením znova overuje súhlas, obľúbenú ponuku, dostupnosť a platnosť relácie.

Web: doplň verejný VAPID kľúč a pred buildom z koreňa spusti `dart run tool/configure_web_push.dart config/app.web.json`. Vygeneruje ignorovaný `firebase-messaging-sw.js` so správnou verejnou konfiguráciou. Nasadenie musí tento súbor sprístupniť na rovnakej doméne cez HTTPS. [Oficiálny postup FCM Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).

Publikovanie/obnovenie ponuky cez admin API vloží upozornenia do SQLite outboxu; worker každých 20 s pošle čakajúce správy, neopakuje úspešné doručenia a najviac päťkrát skúsi dočasné zlyhanie. Deduplikácia je zariadenie + ponuka + termín. Živé doručenie FCM/APNs nebolo bez projektových kľúčov vykonané.

## Distribúcia

Android: vytvor vlastný keystore, vyplň ignorovaný `apps/mobile/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); release nepoužíva debug podpis. Potom `flutter build appbundle --release --dart-define-from-file=../../config/app.android.json`.

iOS: otvor `apps/mobile/ios/Runner.xcworkspace`, nastav Team, bundle ID a capabilities na vlastný účet; zostav archive pre App Store. V CocoaPods pri prvom použití môže byť potrebné `pod install --repo-update`. Overené bolo natívne zostavenie pre iPhone 17 Pro simulátor (iOS 26.2) v Xcode 27:

```sh
cd apps/mobile/ios
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -destination 'id=<ID>' ONLY_ACTIVE_ARCH=YES build
```

Apple HIG podklady sú uložené v `docs/research/apple-hig`. Verejné spustenie vyžaduje vlastné údaje prevádzkovateľa, zásady a podmienky v aplikácii; súčasná Privacy obrazovka otvorene uvádza stav projektu. Žiadna verejná služba ani platený účet neboli touto implementáciou aktivované.

## Overenie tejto implementácie (23. 10. 2026)

- Analyzer celého workspace: bez nálezov.
- 26 doménových, 30 serverových, 2 HTTP integračné, 3 perzistenčné a 27 Flutter testov: **88 úspešných**; samostatný vizuálny export: 1 úspešný. Bežná sada vizuálny export úmyselne preskakuje.
- Release web build a Android debug APK: úspešné. iOS natívny build pre konkrétny iPhone 17 Pro simulátor: úspešný.
- V prehliadači skontrolované skutočné zobrazenie, obľúbené, profil, zmena svetlej/tmavej témy, skutočné adresné výsledky Photon a načítaný OpenStreetMap podklad. Skutočné obrázky sú v `docs/screenshots`; pôvodné schválené návrhy v `docs/design`.
- Stripe, OAuth a FCM poskytovateľské kontrakty testované náhradami. Ostré účty, živé peniaze, APNs/FCM doručenie, distribučný podpis a verejné nasadenie neboli aktivované.

## Doplnenie platieb (24. 10. 2026)

Natívne PaymentSheet a webový Checkout majú oddelený, nemenný platobný tok. VISA, Apple Pay a Google Pay spracuje jeden Stripe účet. Podrobnosti a kroky aktivácie sú v [PLATBY.md](PLATBY.md).

- Analyzer bez nálezov; 28 doménových, 40 serverových, 2 HTTP integračné, 3 perzistenčné a 37 Flutter testov: **110 úspešných**. Samostatný vizuálny export svetlej aj tmavej pokladne: úspešný.
- Overené: autorizácia platobných údajov, serverová suma a mena, opakovanie po prerušení, stav po návrate aplikácie, webhook, storno, refundácia, expirácia a platba kreditom bez otvorenia SDK.
- Release web, Android debug APK a iOS build pre iPhone 17 Pro simulátor: úspešné. Aktualizovaný lokálny demo APK je v `artifacts/nevyhadzuj-demo.apk`.
- Živá kartová ani peňaženková transakcia nebola vykonaná; vyžaduje účty, kľúče a merchant konfiguráciu prevádzkovateľa.

## Predajcovia a sklad (24. 10. 2026)

Webový aj mobilný portál, jeho roly, dátumové pravidlá a integračný kontrakt sú v [PREDAJCOVIA.md](PREDAJCOVIA.md). Samostatný web sa zostavuje cez `tool/build_merchant_web.sh`; lokálny port 7358 je v predvolených CORS origin.

Overenie: 30 doménových, 95 serverových, 3 HTTP integračné, 3 perzistenčné a 70 Flutter testov — **201 úspešných**. Analyzer bez nálezov. Dva opt-in vizuálne exporty sú mimo bežnej sady; predajcovský export vytvára webové aj mobilné obrazovky v oboch témach. Samostatný merchant web, zákaznícky web, Android debug a iOS simulátor build prešli. Živý ERP/POS a veľkosť celej obchodnej siete zatiaľ neboli overované.

Financie, Connect, účtovný export a oprávnenia operátorov: [Financie a zákaznícka podpora](FINANCIE_A_PODPORA.md).

## Produkčná príprava bez aktívnych platieb

Aktuálny návod a hranice sú v [DOKONCENIE.md](DOKONCENIE.md). compose.production.yaml spúšťa API s PAYMENT_MODE=disabled, tri HTTPS weby a lokálne online zálohy. Vytvor .env.production podľa .env.production.example a nastav vlastné DNS/domény, mail a povolené originy. Weby zostav s verejnou HTTPS API adresou. Šablóna sa nesmie spustiť s ilustračnými doménami.

Prvý správca musí byť existujúci overený účet: aktivovať mail, registrovať/overiť účet, potom nastaviť PLATFORM_ADMIN_EMAILS a reštartovať. Bootstrap neprihlasuje používateľa a nevytvára overený účet za neho. Administrácia → Prevádzka a pripravenosť ukazuje chýbajúce nastavenia; podmienky a fakturačné údaje sa nastavujú v samostatných častiach.

Online záloha: python3 tool/backup.py backup data/marketplace.sqlite --target backups/nvp-UNIKATNY-CAS.sqlite. Overenie: python3 tool/backup.py verify backups/nvp-UNIKATNY-CAS.sqlite --manifest backups/nvp-UNIKATNY-CAS.sqlite.json. Obnova vždy do nového súboru cez restore --target; neprepíše živú databázu. Následné prepnutie servera na obnovenú databázu rob až po jeho zastavení a kontrole. Lokálny backup volume nenahrádza vzdialenú šifrovanú zálohu mimo hostiteľa.

Docker bol lokálne zostavený a spustený, Caddy konfigurácia validovaná. Pri použití Colima musí byť projektový adresár zdieľaný do VM pre bind mount webov a Caddyfile; samotný docker build zdieľanie nevyžaduje. Verejné nasadenie, DNS/TLS a offsite služba neboli aktivované.
