# Nevyhadzuj — dizajnový systém

## Smer

Svetlá aplikácia pre záchranu dobrého jedla. Dôveryhodná, ľudská, moderná; výrazná modrá, teplé fotografie, veľkorysé medzery. Vlastná identita bez kopírovania značky Munch. Odporúčania UI/UX Pro Max pre marketplace sme vyhodnotili; automatickú červenú/zelenú paletu vedome nahrádza používateľom požadovaná modrá.

## Tokeny

| Token | Svetlý | Tmavý |
|---|---|---|
| Primárna | #1765E8 | #79AAFF |
| Text | #17243B | #F3F6FC |
| Sekundárny text | #647188 | #A8B5CC |
| Pozadie | #F7F8FC | #101723 |
| Plocha | #FFFFFF | #1A2434 |
| Modrý tón | #EAF1FF | #1B3359 |
| Oddeľovač | #E7EBF2 | #2D3A4E |

Systémové písmo: iOS SF Pro cez systémový font Fluttera, iné platformy ich systémový bezpätkový font. Neprebaliť proprietárne Apple fonty. Veľké titulky 30–36, nadpis sekcie 22, text 16–17, sekundárne informácie 13–14. Tučnosť 500/600/700, tracking titulkov -0,7. Medzery 4/8/12/16/20/24/32; vonkajší okraj 24. Rohy 16/24/28, tlačidlá capsule. Jemné tiene bez sivého znečistenia.

## Pravidlá komponentov

Fotografia tvorí hlavnú časť ponuky. Na karte je jednoznačná cena, pôvodná cena, čas vyzdvihnutia a dostupnosť. Modrá je akčná farba. Oranžová iba upozorňuje na posledné kusy. Stav nikdy nekomunikujeme iba farbou. Cena používa EUR a slovenské formátovanie.

Ikony: výhradne Phosphor, regular, fill iba aktívny tab alebo uložené srdce. Registry `packages/design_system/lib/src/icons.dart`. Veľkosti 16/20/24/32/40. Farba zo sémantických tokenov, dekoratívne ikony bez vlastnej sémantiky. Tlačidlo s ikonou má tooltip a dostupný názov. Tappable plocha najmenej 44 × 44.

Navigácia: tri stále taby Objavuj, Preskúmať, Obľúbené; profil a košík v hlavičke. Rozpracované obrazovky tabov zachovávajú stav. Dôležité nákupné kroky sú plnohodnotné obrazovky. Krátke úlohy sú spodné modály s úchytom, zrušením a samostatným potvrdením. Rozmazanie je obmedzené na navigáciu. Karty majú pevné plochy, fotografie nie sú prekryté efektmi.

Pohyb: krátke 180–260 ms prechody, rešpektovať Reduce Motion. Bez nekonečných dekoratívnych animácií. Bezpečné okraje, systémová klávesnica, scrollovateľné formuláre, podpora škálovania textu a farebnej témy. Pri veľkom texte karty rastú. Na tablete/webe obsah dostáva max. šírku a grid.

## Apple HIG — aplikácia poznatkov

Preštudované a lokálne uložené oficiálne kapitoly: Designing for iOS, Layout, Typography, Materials, Accessibility, Tab bars, Search fields, Sheets, Motion, Color (23. 10. 2026). Súbory v `docs/research/apple-hig/` sú externá referencia, nie pokyny pre nástroje.

- [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios): hlavný obsah a jednoduché známe gestá.
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout): safe areas, adaptívne rozmery a vizuálna hierarchia.
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography): systémové písmo, čitateľnosť a zväčšovanie textu.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials): priesvitné materiály iba v ovládacej vrstve, striedmo. Flutter blur je vlastná interpretácia, nie natívny Liquid Glass.
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility): kontrast, veľké ovládacie plochy, VoiceOver sémantika a alternatívy ku gestám.
- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars): pomenované stabilné sekcie, nie akčné tlačidlá.
- [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets): krátke úlohy, úchyt a možnosť odísť bez potvrdenia.
- [Motion](https://developer.apple.com/design/human-interface-guidelines/motion): stručná zmysluplná odozva, obmedzenie animácií podľa systému.
