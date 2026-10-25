# Naplnené demo a audit funkcií · 25. 10. 2026

Používateľ chce overiť úplnosť a predviesť krásne, naplnené zákaznícke aj predajcovské rozhranie.

- [x] Audit: zákaznícke lokálne dáta existujú, predajcovské ukážky boli iba vo widget testoch. Reálne platby a ERP potrebujú konfiguráciu.
- [x] Pridať výslovne zapínaný serverový showcase v oddelenej databáze. Štyri persony, tri firmy, štyri pobočky, sklad, automatické návrhy, ponuky a objednávky cez skladové služby.
- [x] Jedným kliknutím otvoriť pripravený profil; bezpečne prepínať persony bez prenesenia košíka a údajov.
- [x] Fotografie skladu, zmysluplná galéria bez duplicít, responzívny výber dema, svetlý a tmavý vzhľad.
- [x] Testy ochrany demo režimu, opakovateľnosti seedu, skladových invariantov a prepínania účtov. Existujúce kontroly a zostavenia.
- [x] Spustiť oddelené demo, preveriť skutočný web a uložiť snímky. Aktualizovať presný stav a návod.

Demo má skutočnú serverovú perzistenciu a skladové rezervácie. Nevytvára reálne platby ani nepredstiera pripojený ERP. Verejný vstup do pripravených účtov je dostupný iba pri DEMO_SHOWCASE=true, sandbox platbách, bez produkcie a bez Stripe/Firebase poverení. Demo účty sú výlučne fiktívne. Bežné prihlasovanie zostáva dostupné.

Overenie: automatické API testy s in-memory SQLite, Flutter testy svetlého/tmavého a mobilného/desktopového rozhrania, úplný tool/check.sh, web release zostavenia, kontrola v prehliadači skutočne naplneným API.

Overenie: tool/check.sh prešiel (28 doména + 67 API + 3 HTTP klient + 3 perzistencia + 55 Flutter = 156). Po vizuálnej úprave hodnotení znovu prešiel analyzer, všetkých 55 Flutter testov a 5 showcase API scenárov. Fotografie sa dekódujú, existujú a galérie nemajú duplicity.

Finálna kontrola: opakovaný tool/check.sh (156 úspešných testov), analyzer po poslednej úprave bez nálezov, 11 predajcovských responzívnych testov znovu úspešných. Release customer web, release merchant web a aktuálny Android debug APK zostavené. Ručný webový výdaj s kódom overený a zaznamenaný. Server teraz používa čisté ukážkové dáta s unikátnymi zobrazovanými číslami objednávok. Snímky demo-profily-dark, demo-predajca-web-light a demo-predajca-mobile-light pochádzajú z finálnej bežiacej verzie.
