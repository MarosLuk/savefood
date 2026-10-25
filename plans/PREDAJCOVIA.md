# Predajcovia, sklad a automatické balíčky

Cieľ: samoobslužný účet prevádzkovateľa s viacerými prevádzkami, ponukami a zľavami, interným skladom a automatizáciou; zákaznícke objednávky a platby musia ďalej fungovať bez dvojitého predaja.

Známe: Shelf/SQLite, transakcie BEGIN IMMEDIATE, serverové ceny a rezervácie, Flutter monorepo a spoločná modrá svetlá/tmavá téma. Neznáme: konkrétne ERP/POS a či „podpora“ znamená aj chat/reklamácie; otázky sú položené. Predpoklad do odpovede: interný sklad + CSV a integračné API; balíčky sú najprv návrhy, automatické publikovanie je výslovná voľba pravidla. Nepripájame neznámy externý systém.

Možnosti: A) samostatná aplikácia s duplikovaným skladom; B) predajcovská časť existujúcej Flutter aplikácie s oddelenými modulmi a jedným serverovým skladom; C) minimálne rozšírenie admin endpointu. Volíme B: zdieľaná identita a dizajn, oprávnenia oddelené na serveri, bez druhej pravdy o zásobách.

Najväčšie riziko: rezervácie rôznych ponúk nad rovnakým SKU a šaržou. Najprv overíme testom atómové FEFO pridelenie, storno a spotrebu. Fyzický stav sa zníži pri prevzatí, rezervované množstvo sa zablokuje pri objednávke; storno ho uvoľní. Publikovaná ponuka ukazuje dynamicky najviac dostupný sklad. Návrh neblokuje zásoby a schválenie vždy overí aktuálny stav. Pri väčšej záťaži či viacerých serverových procesoch bude potrebná migrácia databázy a load test, nie obídenie transakcií.

Sklad eviduje SKU/EAN, kus/balenie/porciu, šaržu, dátum a typ dátumu, skladovaciu zónu a kontrolu kvality. Automatizácia nikdy sama neurčuje bezpečnú trvanlivosť hotového jedla. Vychádza z dátumu/hodiny určených prevádzkovateľom; vylúči zablokované, nepreverené a expirované položky. Dátum spotreby a minimálna trvanlivosť sú odlišné; predvolené pravidlo aplikácie neponúka ani jeden typ po zadanom termíne. Dokumentácia EFSA: https://www.efsa.europa.eu/enIE/safe2eat/food-date-labelling.

- [x] Schéma, vlastníctvo a roly, viac prevádzok.
- [x] Sklad, pohyby, FEFO, rezervácia/storno/prevzatie a kontrola dátumov.
- [x] Manuálne ponuky s receptúrou a zľavou; návrhy/publikovanie/pozastavenie.
- [x] Automatické denné pravidlá, bezpečný plánovač, opakovanie bez duplicít.
- [x] CSV a idempotentné API s obmedzeným, odvolateľným tokenom.
- [x] Flutter portál: prehľad, sklad, ponuky, automatizácia, výdaj, nastavenia.
- [x] Kontraktové a obchodné testy, migrácia, analyzer, vizuálna kontrola oboch tém a buildy.

Bez dodaného ERP sa otestuje štandardné integračné rozhranie náhradou. Vyplácanie predajcom a daňová fakturácia nie sú automaticky aktivované týmto rozšírením.

Doplnené podľa používateľa: samostatný webový vstup pre predajcov, plná správa skladu/prepojení vo webe a rovnaké funkcie pre malú reštauráciu v mobilnej aplikácii. Web: main_merchant.dart a samostatný build.
