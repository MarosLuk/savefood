# Save Food

Flutter aplikácia na záchranu jedla s vlastným Dart API. Modrý dizajn podľa schválených návrhov, svetlá/tmavá/systémová téma, iOS, Android a web. Referencia: dve dodané nahrávky; značka, prevádzky a fotografie aplikácie sú vlastné alebo ilustračné.

Názov aplikácie: **Save Food**. iOS Bundle ID a Android application ID: `com.dakoty.savefood`. Apple Developer Team: Dakoty Studio (`QQ3UCX8XGK`). [Hetzner a HTTPS na IP](docs/HETZNER.md) · [Firebase registrácia a prihlásenie](docs/FIREBASE.md).

## Naplnené demo

`bash tool/demo.sh` spustí zákaznícky web na http://127.0.0.1:7357 predajcovský portál na http://127.0.0.1:7358 a administráciu na http://127.0.0.1:7359. Vyber **Demo profily**: zákazníčka, pekáreň s dvoma pobočkami, bistro, obchod alebo operátorka podpory. Vlastný sklad, objednávky, fotografie, kredit a automatické návrhy sú pripravené na prezentáciu. Ukážka používa oddelenú databázu a sandbox bez skutočných platieb. [Návod na demo](docs/DEMO.md) · [Presný stav a zostávajúce oblasti](docs/STAV.md).

## Spustenie

Vyžaduje Flutter **3.38.1** / Dart **3.10.0**, pri iOS Xcode + CocoaPods a pri Androide Android SDK + Java 17. V tomto počítači je Flutter v `/Users/maroslukac/Desktop/flutter/bin`.

Z koreňa repozitára:

```sh
flutter pub get
dart run apps/api/bin/server.dart
```

V druhom termináli:

```sh
cd apps/mobile
flutter run -d chrome --web-port=7357 --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

Pripravený inštalovateľný Android debug balík bez potreby servera je `artifacts/save-food-demo.apk` (lokálny ukážkový režim).

Alebo `bash tool/dev.sh`, ktorý spustí API a Chrome spolu. Prihlás sa cez e-mail → vytvoriť účet. Heslo má aspoň 12 znakov. Ukážkový server používa fiktívne prevádzky a **sandbox platby bez účtovania peňazí**. Kupón `VITAJ10` alebo `DOBREJEDLO` dá 10 % zľavu; klubová skúška trvá 14 dní, s kódom `KLUB30` 30 dní. Prvý vstup zobrazí onboarding; na vývoj ho možno preskočiť cez `--dart-define=SKIP_ONBOARDING=true`.

Pre iOS simulátor použi `flutter run -d <ID> --dart-define=API_BASE_URL=http://localhost:8080`. Pre Android emulátor je adresa hostiteľa `http://10.0.2.2:8080`. Pre fyzické zariadenie spusti API s `HOST=0.0.0.0` a použi IP počítača v rovnakej sieti. HTTP je povolené iba v Android debug konfigurácii; distribučná verzia potrebuje HTTPS.

Bez `API_BASE_URL` sa zákaznícky web, predajca, administrácia aj iOS/Android pripájajú na Hetzner API `https://46.62.223.67:8453`. Samostatný lokálny režim zapne explicitné `--dart-define=API_BASE_URL=`; jeho údaje sa nemiešajú s jednotlivými API prostrediami. Aktuálne nasadenie a buildy opisuje [Hetzner](docs/HETZNER.md).

## Čo funguje

- Obnova/zmena hesla, overenie/zmena e-mailu, revokácia relácií, export a odstránenie účtu; e-mailová fronta a nastavenia.
- Priame nahrávanie fotografií, knižnica, recenzie so štyrmi dimenziami a fotografiami.
- Stránkované veľké sklady, kg/l, pozvánky, práva pobočiek a trvalý ERP/účtovný HTTP konektor.
- Samostatná administrácia, verzované podmienky, PDF faktúry a opravné doklady, refundácie jednotlivých kusov.
- Onboarding, hosť, registrácia a prihlásenie heslom, profil, fakturačné údaje, odhlásenie a trvalá relácia. Apple/Google/Facebook OAuth po konfigurácii poskytovateľov.
- Domov, tematické kolekcie, kategórie, dostupnosť, detail s galériou, alergénmi, navigáciou, zdieľaním a hodnoteniami overených nákupov.
- Vyhľadávanie bez diakritiky, kombinovateľné filtre kategórie, diéty, štítkov, prevádzok, typu ponuky, času a okruhu; radenie a spoločné dáta zoznamu/mapy.
- GPS, vyhľadávanie adries cez konfigurovateľný Photon geocoder, výber bodu na mape, obľúbené a upozornenia pri dostupnosti po zapojení Firebase.
- Košík, množstvá, fakturácia na osobu/firmu, kupóny, servisný poplatok 2 %, použitie kreditu a serverom vypočítané ceny v centoch.
- Transakčný sklad, opakovateľný checkout bez dvojitej objednávky, 30-minútová rezervácia na zaplatenie, natívne Stripe PaymentSheet s kartou VISA/Apple Pay/Google Pay, webový Stripe Checkout, podpísané webhooky, refundácia pri storne.
- Inventúry s počítaním a schválením rozdielov; presuny pobočka → cesta → príjem, sledovanie pôvodu šarže a prenesenie vyradenia.
- Podpora s fotografiami, stránkovanou históriou, priradením, auditom a centrom neprečítaných udalostí; pripravené samostatné FCM upozornenia.
- Financie vlastníka: Stripe Connect onboarding, vyúčtovanie vydaných položiek, nastavenie automatických prevodov, provízia, trvalý stav a účtovný CSV.
- Podpora: zákaznícke tikety, automatická triáž a odpovede, operátorská fronta, interné poznámky a refundácie aj jednotlivých kusov vrátane reverzie prevodov.
- História a aktívne objednávky, kód, vyzdvihnutie po prevádzkach, storno pred časom vyzdvihnutia, lokálne pripomienky. Kredit sa pripíše raz až po prevzatí celej objednávky.
- Klub: jedna skúška na účet, exkluzívne ponuky, 10 % cashback, platené predplatné cez Stripe a vypnutie obnovovania pri zachovaní zaplateného obdobia.
- Slovenské a anglické zákaznícke rozhranie (predajcovský portál zatiaľ po slovensky), nastavenia súkromia, pomoc, light/dark/system a väčší systémový text. Obsah prevádzok zostáva v pôvodnom jazyku.

## Monorepo

| Cesta | Zodpovednosť |
|---|---|
| `apps/mobile` | Flutter UI, stav a platformové integrácie |
| `apps/api` | Shelf API, SQLite, účty, sklad, objednávky, Stripe, OAuth a FCM |
| `packages/marketplace_domain` | Modely, filtre, geografické výpočty a ceny; čistý Dart |
| `packages/marketplace_api` | Typovaný HTTP klient a rozhranie úložiska tokenu |
| `packages/marketplace_data` | Perzistencia a pamäťový repository |
| `packages/marketplace_fixtures` | Spoločný ukážkový katalóg |
| `packages/design_system` | Témy, komponenty, typografia a jednotné Phosphor ikony |

Zdieľaný Pub workspace a jeden `pubspec.lock`. Natívny token sa ukladá cez Keychain/Keystore; web cez zabezpečené browserové úložisko na HTTPS. Preferencie a lokálna cache používajú SharedPreferences. Server ukladá ceny a kredit v centoch, hash hesla PBKDF2 a hash relácií; klient nemôže prepísať peňaženku ani členstvo.

## Overenie a buildy

```sh
bash tool/check.sh
cd apps/mobile
flutter build web --release
flutter build apk --debug
flutter run -d <iOS-simulator-ID>
```

Overenie 25. 10. 2026: **288 úspešných testov v hlavnej sade** vrátane nového Firebase toku a ochrany vystavovateľa, analyzer bez nálezov. Navyše prešli záťažový test 5 000 SKU a online záloha/obnova. Všetky tri weby boli zostavené v release režime. [Zostavenia, ručne overené toky a snímky](docs/OVERENIE_PREVADZKY.md).

`tool/check.sh` spúšťa analyzer celého monorepa a testy domény, servera, HTTP integrácie, perzistencie a Flutter obchodného toku. CI je v `.github/workflows/check.yml`. Skutočné obrazovky z Flutter renderera sú v `docs/screenshots`; reprodukcia:

```sh
cd apps/mobile
flutter test test/preview_test.dart --dart-define=CAPTURE_PREVIEWS=true
```

Pri Xcode 27 môže generický `flutter build ios --simulator` vo Flutter 3.38.1 zlyhať pri kontrole viacerých architektúr. Zostavenie pre konkrétny simulátor cez `flutter run -d <ID>` alebo Xcode `ONLY_ACTIVE_ARCH=YES` bolo overené. Návod je v [prevádzke](docs/PREVADZKA.md).

Podrobná analýza doplnených oblastí, testy a externé kroky: [DOKONCENIE.md](docs/DOKONCENIE.md).

## Zapojenie vlastnej služby

Platba kartou (vrátane VISA), Apple Pay a Google Pay idú cez jeden Stripe účet. Natívne okno, aktiváciu a testovanie opisuje [návod na platby](docs/PLATBY.md).

Kód integrácií je implementovaný, no účty a tajné kľúče prevádzkovateľa neboli dodané. Ostré platby, sociálne účty a doručenie FCM/APNs preto neboli skúšané na živých poskytovateľoch. Automatické testy používajú sandbox a HTTP náhrady poskytovateľov. Postup, endpointy, konfigurácia, nasadenie a podpisovanie sú v [docs/PREVADZKA.md](docs/PREVADZKA.md).

Pred verejným spustením treba pripojiť HTTPS server a poskytovateľov, vložiť reálny katalóg, nastaviť distribučné podpisy a doplniť údaje prevádzkovateľa a jeho podmienky. Predajcovský portál pre web aj mobil, viac prevádzok, sklad šarží, automatické balíčky a integračné rozhranie opisuje [návod pre predajcov](docs/PREDAJCOVIA.md). [Vyúčtovanie, Connect, účtovné podklady a zákaznícku podporu](docs/FINANCIE_A_PODPORA.md) dopĺňa vlastný modul. Ostrý Connect vyžaduje aktivované účty; konkrétny ERP/daňový systém ešte nebol určený.

[Analýza a pokrytie referencie](docs/ANALYZA.md) · [Dizajnový systém](DESIGN.md) · [Zdroje fotografií](docs/ASSETY.md)

## Predajca vo webe aj mobile

V mobile: **Profil → Moja prevádzka**. Priamy vstup v zákazníckom webe: `/?portal=merchant`. Samostatný webový build: `bash tool/build_merchant_web.sh --dart-define=API_BASE_URL=https://<api>`; výstup je `apps/mobile/build/merchant-web`. Oba vstupy zdieľajú účet, sklad aj rezervácie. [Postup, roly, CSV a ERP API](docs/PREDAJCOVIA.md).

[Inventúry, presuny, fotografie a upozornenia podpory](docs/SKLAD_A_REKLAMACIE.md). Ostré platby sa podľa zadania zapoja na záver.
