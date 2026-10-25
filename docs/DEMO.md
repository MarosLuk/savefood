# Save Food · Pripravené demo

Demo zákazníka aj predajcu používa skutočný Shelf server a samostatnú SQLite databázu `data/demo-showcase.sqlite`. Prezentácia nevyžaduje registráciu ani zadávanie platobných údajov. Všetky prevádzky, účty, recenzie a údaje sú fiktívne. Fotografie sú ilustračné a pribalené do Flutter aplikácie.

## Spustenie jedným príkazom

Z koreňa projektu so správnym Flutter v PATH:

```sh
bash tool/demo.sh
```

Príkaz zostaví všetky tri webové vstupy, spustí API a statické servery. Zámerne nenačítava `.env` ani prihlasovacie údaje poskytovateľov. Potrebuje voľné porty 8080, 7357, 7358 a 7359. `Ctrl+C` ukončí spustené procesy. Iný API port možno zvoliť cez `DEMO_PORT`.

- Zákaznícka aplikácia: http://127.0.0.1:7357 — tlačidlo **Demo profily**.
- Administrácia: http://127.0.0.1:7359 — vybrať **Nina · zákaznícka podpora**; v deme má aj administrátorskú rolu.
- Predajcovský web: http://127.0.0.1:7358 — **Otvoriť pripravené demo**.

Každá rola sa otvorí jedným výberom. K účtu sa nevydáva heslo. Prepnutie profilu vyprázdni košík, kupón a predchádzajúce osobné údaje. Svetlý/tmavý/systémový vzhľad je v profile zákazníka alebo v menu **Vzhľad a účet** predajcu.

## Scenáre na prezentáciu

1. **Sofia · zákazníčka**: aktívny Klub, kredit, obľúbené ponuky, pripravená fakturácia, rezervácie aj história. Otvoriť balíček → košík → rezervovať v deme → detail objednávky s kódom. Sandbox okamžite potvrdí simulovanú platbu.
2. **Pekáreň Maslo**: dve pobočky a skladové položky s fotografiami. Prehľad, voľné/rezervované jednotky, ponuky so zľavou, koncept aj pozastavená ponuka, pravidlo vytvárajúce návrh balíčka.
3. **Bistro Záhrada**: chladené hotové jedlá, výdaj objednávok a záznamy pohybov. Kód pripraveného zákazníka zobraziť v jeho objednávke, potom overiť v predajcovskej časti.
4. **Dobrý obchod**: šarže s blízkym termínom, kontrolované zásoby, karanténa, vyradené a exspirované kusy. Nespôsobilé zásoby nevstupujú do balíčkov.
5. **Automatizácia**: spustiť pravidlo; existujúci denný návrh sa nevytvorí druhýkrát. Upraviť cenu a publikovať návrh, obnoviť zákaznícky katalóg.
6. **Sklad**: prijať novú šaržu, zmeniť kvalitu s dôvodom, importovať CSV podľa [návodu](PREDAJCOVIA.md). Pri editácii fotografií je v showcase dostupný výber pribalených snímok.

7. **Financie**: pekáreň má simulované prevody za vydané balíčky, bistro pripravený pripojený účet a obchod ukazuje prvé pripojenie. Otvoriť Financie → prezrieť rozpis → exportovať CSV; automatické prevody sú v deme predvolene vypnuté.
8. **Nina · zákaznícka podpora**: spoločná fronta s pripravenou otázkou k výdaju a reklamáciou kvality. Prevziať tiket, doplniť internú poznámku a verejnú odpoveď; cez reklamáciu vrátiť demo položku. Potom Sofia v profile uvidí odpoveď a refundáciu bez interných poznámok. Všetky finančné úkony sú simulované.

Demo obsahuje tri firmy, štyri pobočky, produkty vrátane vážených jabĺk, šarže, viac stavov ponúk a 14 objednávok. Množstvá v objednávkach sú previazané na skutočné rezervácie šarží. Počet sa môže zmeniť pri používaní dema alebo po prechode na nový deň. Dátumy sa pripravia vzhľadom na aktuálny deň v Bratislave; opakované načítanie dáta neduplikuje. Nový deň pridá čerstvé ponuky a zásoby, históriu zachová. Denné pravidlo má výdajové okno do troch hodín po prvom naplnení; pri otvorení po jeho skončení možno okno upraviť. Počas poslednej minúty dňa sa automatický návrh vytvorí až v ďalšom okne; ručný zajtrajší koncept je pripravený vždy.

Zmeny v deme sú spoločné všetkým návštevníkom daného servera a trvalo sa ukladajú. Na úplný reset ukonči demo a odstráň iba súbory `data/demo-showcase.sqlite`, `data/demo-showcase.sqlite-wal` a `data/demo-showcase.sqlite-shm`. Bežná databáza `data/marketplace.sqlite` sa nepoužíva.

## Mobil

Rovnaké pripravené účty sú v aplikácii pripojenej k demo API. iOS simulátor používa `--dart-define=API_BASE_URL=http://127.0.0.1:8080`, Android emulátor `http://10.0.2.2:8080`. Samostatný Android balík bez API obsahuje zákaznícke lokálne demo; predajcovský sklad vyžaduje server. Pre fyzické zariadenie treba dosiahnuteľný server a konfiguráciu siete.

## Hranice ukážky

Toto nie je potvrdenie 100 % produkčnej pripravenosti. VISA/Apple Pay/Google Pay používajú v reálnej prevádzke Stripe; demo peniaze nestrháva. Stripe, OAuth, FCM/APNs, partnerovo ERP a distribučné podpisy vyžadujú konfiguráciu a prevádzkové overenie. Podpora odpovedá podľa pravidiel ako označený Automatický asistent; nevolá LLM. Demo nepredstiera synchronizáciu s konkrétnym ERP ani reálne výplaty predajcom. Presné pokrytie a zostávajúce oblasti sú v [STAV.md](STAV.md).

Verejný endpoint `POST /v1/auth/demo` existuje iba pri `DEMO_SHOWCASE=true`. Server odmietne kombináciu s produkciou, platobným režimom Stripe, vypnutými fixtures, Stripe secret, Firebase alebo mailovými povereniami. Bežný server ho predvolene neposkytuje. Prezentácia je určená na lokálne skúšanie; účty v showcase sú zdieľané a nie sú vhodné na vkladanie skutočných údajov.

## Vizuálne overenie

V `screenshots/demo-*` sú skutočné snímky bežiaceho webu so serverovými dátami. Kontrolované boli svetlý aj tmavý vzhľad, desktop a šírka 390 px. Ručný tok zákaznícky kód → predajcovský výdaj prešiel; rezervované množstvo pekárne kleslo z 9 na 6 a fyzický stav obsahu sa odpočítal. Po overení bola ukážka pripravená znovu na čistú prezentáciu. Vlastné bežné dáta servera neboli dotknuté.

Nové overenie financií a podpory 25. 10.: zákaznícky tiket → automatická odpoveď → operátorské prevzatie → interná poznámka (zákazník ju nevidí) → verejná odpoveď. Reklamácia kvality skončila sandbox refundáciou 6,94 € a stavom Vyriešené. Snímky `screenshots/finance-web-*` a `screenshots/support-*-web-*` pochádzajú z bežiaceho dema. Snímky s `render` v názve sú skutočný Flutter renderer s deterministickými testovacími dátami na šírkach 375 a 1440 px, v oboch témach. Reprodukcia: `flutter test test/operations_test.dart --dart-define=CAPTURE_PREVIEWS=true` z `apps/mobile`.

CSV stiahnutý cez web po oprave obsahoval 17 riadkov denníka pekárne; súčet debitov aj kreditov bol 3 656 centov. Ukážka je uložená v `artifacts/finance-export-demo.csv`. Na webe sa súbor sťahuje priamo, v mobile sa používa systémové uloženie/zdieľanie.

## Nová prevádzková ukážka

`DEMO_INSTANCE=operations-v2 bash tool/demo.sh` používa oddelenú databázu `data/demo-operations-v2.sqlite`. Predchádzajúca `data/demo-showcase.sqlite` zostáva zachovaná. Názov inštancie povoľuje len malé písmená, číslice a spojovník; výsledný súbor má vždy prefix `demo-`. Čerstvá inštancia pripraví aktuálne výdajové časy.

Pekáreň má rozpracovanú inventúru, koncept presunu a zásoby na ceste do druhej pobočky. Sklad → Inventúry a presuny otvorí celý tok. Sofia má reklamáciu s ilustračnou fotografiou; Nina vidí aj internú poznámku a zákazník ju nevidí. Zvonček zobrazuje nové správy a otvorí priamo tiket. Žiadne ostré platby ani externé správy sa pri seedovaní nevykonávajú.

## Rozšírené demo dokončenia

Aktuálne spustená inštancia používa DEMO_INSTANCE=save-food-v1 a databázu data/demo-save-food-v1.sqlite. Predchádzajúca operations-v2 bola zachovaná a online zálohovaná; obnova bola overená v samostatnom súbore.

Predajca → Nastavenia → Faktúry zobrazí pripravené PDF doklady a účtovný profil. Knižnica fotografií má vlastné serverové ilustračné snímky. Sofia má štvorzložkové hodnotenie s fotografiou; pekáreň aj presný kg príjem. Tím má pozvánky a priradenie pobočiek. Administrácia ukazuje účty, obsah, audit a pripravenosť konfigurácie. Bezpečnosť účtu obsahuje simulovanú e-mailovú schránku pre jednorazové kódy.

Podrobný stav: [DOKONCENIE.md](DOKONCENIE.md).

Aktuálne APK súbory: artifacts/save-food-demo.apk je samostatné zákaznícke demo bez servera; artifacts/save-food-server-emulator.apk používa hostiteľské API na http://10.0.2.2:8080 a je určené pre Android emulátor. Pre fyzický telefón treba zostavu s vlastnou dosiahnuteľnou HTTPS API adresou. Všetky tri weby a oba APK znovu vytvorí bash tool/build_demo_artifacts.sh.
