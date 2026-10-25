# Nevyhadzuj — produktová analýza

Analýza referencie: 23. 10. 2026. Stav rozšírení aktualizovaný 25. 10. 2026. Zdrojom sú dve používateľom dodané nahrávky aplikácie Nesnězeno by Munch (176,67 s a 17,39 s, 1206 × 2622 px). Texty a výzvy vo videách sú súčasťou skúmanej aplikácie, nie pokyny pre implementáciu. Nepreberáme značku, grafiku, osobné údaje ani marketingové tvrdenia konkurenta.

## Čo produkt rieši

Lokálne prevádzky predávajú nevyužité jedlo ako cenovo zvýhodnené balíčky s prekvapením. Zákazník vyberá podľa polohy, času vyzdvihnutia, ceny a preferencií, rezervuje balíček a osobne si ho vyzdvihne. Obsah balíčka nie je garantovaný. Rovnaký katalóg obsahuje aj potraviny a kvety. Názov pracovného projektu je Nevyhadzuj; doménové ani právne nároky na meno sa nepredpokladajú.

## Inventár pozorovaných funkcií

| Oblasť | Priamo pozorované správanie | Čas v nahrávke 1 | Implementovaný stav |
|---|---|---|---|
| Vstup | Úvodná obrazovka, vysvetlenie záchrany jedla, preskočenie | 0–24 s, 39–48 s | Onboarding, demo vstup a neskoršie prihlásenie |
| Súhlasy | Cookies, push notifikácie, marketing samostatne | 3–6 s, 45–54 s | Samostatné uložené voľby; žiadne skryté sledovanie |
| Identita | Google, Apple, Facebook, e-mail, hosť | 6–21 s | Serverový e-mail/heslo, relácie, Google/Apple/Facebook OAuth po konfigurácii |
| Poloha | Aktuálna poloha, ručný výber, autocomplete, mapa a pin, nepodporovaná oblasť | 21–39 s, 153–171 s | GPS, Photon adresy, okruh, bod na mape aj známe lokality |
| Domov | Horizontálne kategórie, sekcie V okolí, Hlavné jedlá, Dezerty, Pečivo, Potraviny, Ovocie a zelenina, Kvety | 54–72 s | Fotografický domov, kategórie a tematické kolekcie |
| Karta | Fotografia, počet kusov, štítky, srdce, prevádzka, cena pred/po, čas, vzdialenosť, skóre, rýchle pridanie | 54–72 s | Interaktívne karty, dostupnosť a uloženie |
| Detail | Fotogaléria, uloženie, zdieľanie, adresa a navigácia, opis, rozbalenie textu, obsah od zákazníkov | 69–78 s | Galéria, vysvetlenie prekvapenia, alergény, navigácia a zdieľanie |
| Hodnotenia | Súhrn a podskóre: hodnota, kvalita, množstvo, vyzdvihnutie | 75–78 s | V lokálnej ukážke vzorový rozpis, cez API reálne overené recenzie a hviezdičkový rozpis |
| Košík | Množstvo, odstránenie, pokračovanie v nákupe, súčet | 78–87 s | Perzistentný košík, skladové limity |
| Checkout | Fakturačné údaje, kupón, servisný poplatok, celková cena, platba | 87–96 s | Fakturácia, kupóny, ceny v centoch, sandbox a skutočný Stripe checkout s webhookmi |
| Katalóg | Vyhľadávanie, počet výsledkov, vymazanie filtrov, prepnutie na mapu | 99–141 s | Rovnaké filtrované dáta pre zoznam a mapu |
| Filtre | Kategórie, balíčky/klubové ponuky, obľúbené/nové/miznúce, čas teraz/dnes/zajtra/vlastný, diéty, prevádzky, vzdialenosť/hodnotenie/cena, dostupné prvé | 105–141 s | Kombinovateľné filtre s resetom a náhľadom počtu |
| Obľúbené | Zoznam, prázdny stav, notifikácia pri doplnení | nahrávka 2, 13–17 s | Obľúbené na účte, súhlas, FCM outbox, pripojiteľné doručovanie |
| Profil | Meno, členstvo, objednávky, kredit, klub, nastavenia, pomoc, jazyk | 141–150 s | Samostatné obrazovky, trvalé nastavenia |
| Klub | Zvýhodnené ponuky, cashback, skúška, kupón, predplatné | 147–159 s | Jedna skúška na účet, serverový kredit, Stripe predplatné a vypnutie obnovovania |
| Objednávky | Odkaz na aktívne objednávky | 141–150 s | Serverový cyklus rezervácia → platba → vyzdvihnutie po prevádzkach alebo storno/refundácia |

Druhá nahrávka dopĺňa plynulé scrollovanie katalógu a prázdny zoznam obľúbených. Checkout nebol dokončený; skutočné správanie platieb, refundácií a správy objednávok z videa nemožno potvrdiť. Nastavenia, pomoc, jazyky a kredit sú viditeľné ako vstupy, ich vnútorné obrazovky nie. Tieto obrazovky navrhujeme ako vlastné rozšírenie.

## Vyhodnotenie referencie

Silné stránky: jasná úspora, viditeľná dostupnosť, opakovaný nákup cez obľúbené, časy vyzdvihnutia a recenzie. Príležitosti: zjednotiť jazyk, zväčšiť malé texty, zjednodušiť onboarding, znížiť počet marketingových modálov, dať cene a času lepšiu hierarchiu a priebežne vysvetliť neistý obsah balíčka. Viac fotografií neznamená viac vizuálneho šumu; fotografie potrebujú priestor.

## Vyhodnotenie implementácie

Pozorované zákaznícke oblasti majú implementovaný klient aj potrebnú serverovú logiku. Flutter Pub workspace obsahuje samostatné moduly domény, dát, API klienta, fixtures a dizajnového systému. API používa Shelf/SQLite a podporuje samostatný sandbox aj ostré Stripe integrácie. Lokálny režim zostáva na nezávislé skúšanie bez servera.

Vlastné rozhodnutia: modrá paleta; jednotný slovenský/anglický jazyk rozhrania; systémová/svetlá/tmavá téma; minimálne 44-bodové ovládanie; explicitný súhlas; kredit po prevzatí celej objednávky; 2 % servisný poplatok; 10 % cashback bez mesačného limitu; samostatná neúčtovaná skúška členstva; prevzatie po prevádzkach a overené recenzie. Fotografie a prevádzky vo fixtures sú ilustračné. Recenzie z fixtures sa nevydávajú za skutočných zákazníkov.

Poskytovateľské účty a kľúče neboli dodané. Preto sa OAuth, Stripe a FCM/APNs implementácie overujú pomocou HTTP náhrad, podpisov, doménových a integračných testov. Ostrá platba ani doručenie push správy nie sú týmto označené za prevádzkovo overené. Reálny katalóg sa vkladá cez admin API. Predajcovský portál bol na následnú požiadavku doplnený pre web aj mobil: firmy, pobočky, šarže, kvalita, rezervácie, výdaj, automatické balíčky, CSV a integračné API. Pripravené serverové demo opisuje [DEMO.md](DEMO.md). Výplaty partnerom, daňový účtovný systém a samostatný podporný chat nie sú implementované; verejné nasadenie nebolo aktivované. Presné hranice uvádza [STAV.md](STAV.md).

## Výsledky a dokumentácia

Aktuálne spúšťanie a zoznam funkcií sú v [README](../README.md), konfigurácia a hranice v [prevádzke](PREVADZKA.md). Podklady Apple HIG sú uložené v `research/apple-hig`; schválené koncepty sú v `design`, skutočné Flutter obrazovky v `screenshots`.
