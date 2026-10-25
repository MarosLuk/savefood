# Podklady pre sklad

- SQLite transakcie a BEGIN IMMEDIATE: https://www.sqlite.org/lang_transaction.html — zapisovacie operácie zostávajú v jednej atómovej transakcii bez await.
- EFSA, dátumy potravín: https://www.efsa.europa.eu/enIE/safe2eat/food-date-labelling — use-by sa týka bezpečnosti, best-before kvality. Automatické ponuky aplikácie majú konzervatívne pravidlo neprekročiť zadaný termín pri oboch typoch.
- Európska komisia, dátumy a plytvanie: https://food.ec.europa.eu/food-safety/food-waste/eu-actions-against-food-waste_en.
- CSV 6.0.0 API: https://pub.dev/packages/csv/versions/6.0.0 — CsvToListConverter(shouldParseNumbers:false).convert, dynamické typovanie vypnuté pre zachovanie úvodných núl SKU/EAN.

Odporúčania UI/UX Pro Max prešli porovnaním s existujúcim DESIGN.md. Zachovávame schválenú typografiu Inter/SF, modrú paletu a existujúce komponenty; adaptívna NavigationRail pri širšom zobrazení, mobilná navigácia, formuláre s viditeľnými popismi a stavy chýb bez straty vstupu.

Verzia CSV 8 vyžaduje Dart 3.10.1; projekt má Dart 3.10.0. Používa sa kompatibilná 6.0.0 bez aktualizácie SDK.
