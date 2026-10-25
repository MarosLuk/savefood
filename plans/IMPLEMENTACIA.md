# Implementačný plán

## Cieľ a obmedzenia

Flutter monorepo s moderným modrým dizajnom a pokrytím funkčných oblastí z oboch nahrávok. Prázdny projekt, Flutter 3.38.1 / Dart 3.10.0, iOS simulátor dostupný. Externé kľúče ani backend nie sú dodané. Najväčšie riziko: zameniť klientské demo za funkčnú obchodnú infraštruktúru.

## Zvážené možnosti a rozhodnutie

A: Jedna veľká Flutter aplikácia — rýchly štart, slabé hranice a testovateľnosť. B: Flutter Pub workspace, čistá doména, samostatné dáta a dizajnový systém — mierne viac práce, ale testovateľnosť a pripravenosť na server. C: Kompletný server a klient od začiatku — vyžaduje voľby poskytovateľov a účty. Volíme B, lokálny repository s jasným rozhraním, peniaze v centoch, perzistentný demo checkout. Ak sa ukáže potreba vzdialených transakcií, pridá sa implementácia repository a server, doména a UI sa zachovajú.

## Kroky

- [x] Prezrieť 59 vzoriek prvej a 17 vzoriek druhej nahrávky.
- [x] Inventár funkcií, odlíšenie pozorovaného od predpokladaného.
- [x] Stiahnuť a preštudovať Apple HIG, rozhodnúť dizajnové tokeny.
- [x] Pub workspace a doména: ponuky, filtre, košík, ceny, objednávky.
- [x] Lokálny repository, vzorové dáta, perzistencia a riadenie stavu.
- [x] Dizajnový systém a fotografické assety.
- [x] Domov, katalóg, filtre, mapa, detail, obľúbené.
- [x] Košík, fakturácia, kupóny, demo objednávka a vyzdvihnutie.
- [x] Onboarding, profil, členstvo, kredit, preferencie, pomoc a jazyky.
- [x] Testy domény a obchodných tokov, analyzer, web build, iOS simulátor a vizuálna kontrola.
- [x] Aktualizovať README, maticu pokrytia a integračné obmedzenia.

## Rozšírenie po implementácii

Na splnenie plného nákupného toku pribudol samostatný Shelf/SQLite server, typovaný HTTP klient a zdieľané fixtures. Implementované serverové účty, transakčný sklad, idempotencia, Stripe checkout/refundácie/predplatné, overovanie OAuth a FCM outbox. Geocoder je konfigurovateľný Photon endpoint. Doména aj lokálny režim zostali oddelené.

Živé poskytovateľské operácie a verejné nasadenie vyžadujú účty a tajomstvá prevádzkovateľa. Konkrétne dokončené kontroly a hranice sú v README a docs/PREVADZKA.md.

## Overenie

Doménové testy: filtrovanie kombinácií, diakritika, čas a okruh; peniaze, kupóny a poplatok; sklad a množstvá. Testy stavu: perzistencia, rezervácia, vyzdvihnutie, zrušenie, kredit bez dvojitého účtovania. Widget testy: navigácia, obľúbené, checkout validácia a dostupné názvy. Vizuálna kontrola na iPhone simulátore a pri úzkej/širokej obrazovke; veľký text a tmavá téma. Produkčné integrácie sa nevydávajú za otestované.
