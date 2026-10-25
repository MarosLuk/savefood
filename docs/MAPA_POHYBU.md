# Mapa pohybu v Save Food

Audit pracovného stromu k 26. 10. 2026. Pokrýva 38 verejných tried obrazoviek v 27 súboroch používateľského rozhrania vo `features/`, ich dialógy a spoločné komponenty. Zahrnuté sú zákazník, predajca, podpora aj administrácia. `merchant/controller.dart` tvorí dátovú vrstvu; pohyb patrí do rozhrania, ktoré zobrazuje jej výsledky.

**Schválený smer:** pri významnej akcii sa tá istá karta alebo predmet presunie, otočí a zmení na výsledok. Malé interakcie používajú krátky pružný pohyb. Výrazná choreografia má jeden hlavný objekt a čitateľný začiatok aj koniec.

[Prehrateľný návrh platby](prototypes/payment-motion.html) ukazuje 3D flip, rozloženie kariet, orbitálne rotácie, potvrdenie s časticami a dosadnutie do objednávok. [Zdroj návrhu](prototypes/payment-motion.source.html) zostáva editovateľný. Toto je návrh v prehliadači; nový 3D pohyb ešte nie je implementovaný v natívnom Flutter toku.

## Čo už existuje

Nasledujúci stav bol overený v aktuálnom pracovnom strome. Časť aplikačnej implementácie je zatiaľ rozpracovaná mimo commitu s týmto návrhom a mapou.

| Oblasť | Existujúci základ | Čo sa dá rozvinúť |
|---|---|---|
| Spoločné prvky | `AppPressScale`, `AppHaptics`, `AppMotion`; stlačenie 140 ms, zmeny 220 ms, vstup 260 ms | Zdieľané pružiny, rotácie ikon a animácia meniaceho sa čísla. |
| Navigácia | `AppPageRoute`, `MotionTabStack`; prechod obrazovky a zachovanie tabov | Kontinuita fotografie/karty medzi zoznamom, obchodom a detailom. |
| Pridanie do košíka | `CartTarget` + `showCartAdded`; fotografia letí po krivke k viditeľnému košíku, 420 ms | Malá rotácia počas letu a jedno dosadnutie ikonky aj počítadla. |
| Hodnoty a výsledky | `MotionSwitcher`, `MotionEntrance`; cena, počet a stav objednávky | Smerové preklopenie číslic a plynulé preskupenie kariet. |
| Demo platba | `DemoPaymentScreen`: waiting → processing → paid/failed; pulz, kruh a zmena symbolu | Preniesť schválenú 3D choreografiu pri zachovaní existujúceho spracovania výsledkov. |
| Predajca a mapa | Vstup sekcie portálu; animovaná farba vybraného mapového bodu | Výber pinu → náhľad ponuky; vizuálny presun tovaru medzi pobočkami. |

Podrobnosti haptiky a aktuálneho demo toku sú v pracovnom súbore `docs/HAPTIKA_A_POHYB.md`. Mapa nižšie je návrh ďalších úprav, nie zoznam už dokončených animácií.

## Priority

P0 = hlavný nákupný tok. P1 = časté zákaznícke interakcie. P2 = rozšírenia zákazníka a predajcu. P3 = účelová odozva v pomocných a správcovských častiach.

| Priorita | Balík | Výsledok |
|---|---|---|
| P0 | Platba → uložená objednávka | Karta balíčka sa zdvihne, preklopí na platobnú kartu, po potvrdení sa zloží do novej objednávky. |
| P0 | Pridať do košíka → množstvo → súčet | Predmet preletí k skutočnému cieľu; počítadlo a suma dosadnú spolu s výsledkom. |
| P1 | Obchod → produkt → košík | Fotografia a karta držia kontinuitu pri otvorení aj návrate. |
| P1 | Objednávka → kód → vyzdvihnuté | Lístok sa rozvinie, po potvrdenom prevzatí dostane pečiatku a stav sa presunie do histórie. |
| P1 | Obľúbené, filtre, mapa, navigácia | Krátka pružná odozva a preskupenie obsahu bez straty polohy v zozname. |
| P2 | Členstvo, kredit, profil, onboarding | Karta členstva, pripísanie odmeny a jednorazový oslávny moment pri skutočnom úspechu. |
| P2 | Predajca: ponuky, sklad, presuny | Publikovanie ponuky a pohyb tovaru majú vlastnú zrozumiteľnú choreografiu. |
| P3 | Formuláre, podpora, financie, administrácia | Krátky pohyb pri potvrdení, chybe, pridaní riadka a zmene stavu. |

## Zákaznícky tok

Časy sú návrhové rozsahy pre jednotlivú reakciu. Čakanie na server má vlastný stav; jeho trvanie neurčuje animácia.

| ID | Miesto a spúšťač | Malý pohyb | Výraznejší prechod | Priorita / zdroj |
|---|---|---|---|---|
| C01 | Spodná navigácia, poloha, košík | Ikona sa stlačí, indikátor plynulo prejde pod vybranú sekciu; badge krátko dosadne, 140–220 ms. | Zachovať zobrazenú sekciu aj scroll pri prepnutí. | P1 · [AppShell](../apps/mobile/lib/app.dart) |
| C02 | Prvý vstup a posun onboardingu | Indikátor stránky sa natiahne smerom pohybu. | Fotografie balíčkov sa rozložia do 2–3 vrstiev s miernou rotáciou a pri swipe sa zložia do ďalšej scény, 450–700 ms. | P2 · [OnboardingScreen](../apps/mobile/lib/features/onboarding.dart) |
| C03 | Domov, kategórie a hlavný banner | Jemný náklon vybranej kategórie a pružné uvoľnenie, 160–220 ms. | Banner otvorí katalóg cez spoločnú fotografiu; prvý viditeľný rad sa ukáže s krátkym odstupom. | P1 · [HomeScreen](../apps/mobile/lib/features/home.dart) |
| C04 | Karta obchodu → ponuka prevádzky | Karta reaguje na stlačenie a vráti sklon na nulu. | Fotografia sa roztiahne do hlavičky obchodu, produkty sa rozložia pod ňu, 350–550 ms. | P1 · [StorefrontCard, StorefrontScreen](../apps/mobile/lib/features/storefront.dart) |
| C05 | Katalóg, vyhľadávanie, zoradenie | Počet výsledkov sa preklopí; zmenené položky preskupia polohu, 180–260 ms. | Prepnutie zoznam/mapa zachová vybranú ponuku. | P1 · [CatalogScreen](../apps/mobile/lib/features/catalog.dart) |
| C06 | Filtre a kategórie | Chip pružne dosadne, aktívny počet sa zmení spolu s výberom; slider má odozvu pri zmene hodnoty. | Panel sa otvorí ako jedna plocha a výsledky sa po potvrdení preskupia, 250–350 ms. | P1 · [FiltersSheet](../apps/mobile/lib/features/catalog.dart) |
| C07 | Výber mapového pinu | Vybraný pin sa zväčší a ostatné ustúpia, 180–240 ms. | Karta konkrétnej ponuky sa zdvihne od pinu; kamera sa presunie iba pri výbere, 350–500 ms. | P1 · [OfferMap](../apps/mobile/lib/widgets/offer_map.dart) |
| C08 | Získanie alebo zmena polohy | Jednorazová vlna okolo nového pinu; prechod názvu lokality. | Vyhľadávanie/GPS prejde z čakajúceho stavu do vybranej polohy a ponúk v okolí. | P2 · [LocationScreen](../apps/mobile/lib/features/location.dart) |
| C09 | Detail produktu, cena, dostupnosť | Množstvo, zľava a cena sa menia smerovo, 160–240 ms. | Fotografia nadviaže na otvorenú kartu; spodná nákupná plocha dosadne po obsahu, 350–500 ms. | P1 · [OfferDetailScreen](../apps/mobile/lib/features/offer_detail.dart) |
| C10 | Galéria produktu a fotografie | Indikátor stránky sleduje swipe; ovládanie reaguje na dotyk. | Otvorenie a zatvorenie cez spoločnú fotografiu, 250–350 ms; pinch ostáva priamo viazaný na gesto. | P2 · [PhotoGallery](../apps/mobile/lib/features/offer_detail.dart) |
| C11 | Uložiť/odobrať obľúbenú ponuku | Srdce sa krátko otočí a dosadne; odobratie zmenší kartu a uzavrie medzeru, 200–300 ms. | Prvé uloženie môže presunúť malú siluetu do tabu Obľúbené. | P1 · [OfferCard](../apps/mobile/lib/widgets/offer_card.dart), [FavoritesScreen](../apps/mobile/lib/features/home.dart) |
| C12 | Pridať produkt do košíka | Fotografia počas existujúceho preletu jemne rotuje, počítadlo košíka sa pružne zväčší. | Z jedného predmetu sa stane prírastok v košíku; 420–550 ms vrátane dosadnutia. | P0 · `widgets/cart_feedback.dart`, [OfferCard](../apps/mobile/lib/widgets/offer_card.dart) |
| C13 | Košík: množstvo, odstránenie, suma | Číslice sa odrolujú podľa smeru zmeny, súčet sa zmení naraz; odstránená karta sa zloží, 180–280 ms. | Posledný odstránený produkt prejde do prázdneho košíka; ponúknuť návrat späť pri vratnej akcii. | P0 · [CartScreen, CartLine](../apps/mobile/lib/features/commerce.dart) |
| C14 | Kupón a potvrdená zľava | Vloženie/odmietnutie kódu má lokálnu odozvu; chyba mierny posun a čitateľný text. | Úspešný kupón sa preklopí na malý potvrdený lístok a zľava prejde do súhrnu, 400–600 ms. | P2 · [CouponSheet](../apps/mobile/lib/features/commerce.dart) |
| C15 | Fakturačné údaje a validácia | Fokus a chyba sa zobrazia pri poli; uložený súhrn plynulo nahradí formulár. | Potvrdená kartička údajov dosadne do checkoutu, 250–350 ms. | P1 · [InvoiceScreen](../apps/mobile/lib/features/commerce.dart) |
| C16 | Zaplatiť a spracovať platbu | Tlačidlo sa stlačí a prejde do blokovaného stavu. | Schválená choreografia: zdvihnutie balíčka → flip → orbitálne spracovanie → potvrdenie → dosadnutie do objednávok. | P0 · [CheckoutScreen](../apps/mobile/lib/features/commerce.dart), pracovný `features/demo_payment.dart` |
| C17 | Nová objednávka v zozname | Nový riadok dostane jednorazový vstup, stavový štítok pružne dosadne, 250–450 ms. | Tá istá karta z platby pristane na svojom mieste; ďalšie návštevy zobrazia stabilný zoznam. | P0 · [OrdersScreen](../apps/mobile/lib/features/orders.dart) |
| C18 | Otvoriť rezerváciu a kód | Stavový symbol a text sa zmenia spolu. | Lístok s kódom sa rozvinie s jedným otočením okolo osi X, 350–550 ms; potom zostáva pokojný a čitateľný. | P1 · [OrderDetailScreen](../apps/mobile/lib/features/orders.dart) |
| C19 | Potvrdiť vyzdvihnutie | Zaškrtnutá položka krátko dosadne; pri viacerých balíčkoch sa aktualizuje správna položka. | Po uloženom prevzatí príde pečiatka, krátky rozlet častíc a presun do dokončených, 700–1 100 ms. | P1 · [OrderDetailScreen.finish](../apps/mobile/lib/features/orders.dart) |
| C20 | Hviezdičky, recenzia, fotografia | Hviezdičky sa aktivujú postupne po vybranú hodnotu; fotografia dosadne do príloh, 120–220 ms. | Odoslaná recenzia sa zloží do potvrdenej karty v histórii; zlyhanie zachová rozpracovaný obsah. | P2 · [ReviewsSheet, ReviewPhoto](../apps/mobile/lib/features/reviews.dart), [RatingsSheet](../apps/mobile/lib/features/offer_detail.dart) |

## Účet, členstvo a systémové plochy

| ID | Miesto | Malý pohyb | Výraznejší prechod | Priorita / zdroj |
|---|---|---|---|---|
| A01 | Prihlásenie, registrácia, úprava profilu | Formulár plynulo zmení výšku; úspech/chyba sa ukáže pri odoslaní. | Úspešné prihlásenie prejde na profil cez avatar a meno, 300–450 ms. | P1 · [AuthScreen](../apps/mobile/lib/features/account.dart) |
| A02 | Profil a štatistiky záchrany | Čísla sa dopočítajú iba pri potvrdenom prírastku. | Dosiahnutý míľnik dostane krátku otočenú pečiatku, najviac raz na udalosť. | P2 · [ProfileScreen](../apps/mobile/lib/features/account.dart) |
| A03 | Aktivácia členstva | Zvolený plán pružne vystúpi nad ostatné karty. | Digitálna karta členstva sa otočí, prejde cez ňu svetlo a dosadne do profilu, 700–1 000 ms. | P2 · [ClubScreen](../apps/mobile/lib/features/account.dart) |
| A04 | Kredit a pripísaná odmena | Zostatok smerovo prejde na potvrdenú hodnotu. | Malý token preletí od dokončenej objednávky k zostatku, 500–700 ms. | P2 · [WalletScreen](../apps/mobile/lib/features/account.dart) |
| A05 | Nastavenia, téma, jazyk, súkromie | Prepínače, zvolený jazyk a farby prejdú na nový stav, 150–220 ms. | Téma môže použiť krátke prelínanie zachovávajúce scroll a fokus. | P3 · [SettingsScreen, PrivacyScreen](../apps/mobile/lib/features/account.dart) |
| A06 | Bezpečnosť, zmena e-mailu/hesla, export, zmazanie účtu | Jasný krokový stav, lokálna validácia a pokojné potvrdenie výsledku. | Pri potvrdení kódu plynulo zmeniť krok formulára; zachovať explicitné potvrdenie citlivej akcie. | P3 · [AccountSecurityScreen, AccountActionScreen, DemoMailScreen](../apps/mobile/lib/features/account_security.dart) |
| A07 | Právne dokumenty a správa verzií | Označenie výberu, otvorenie sekcie, potvrdenie uloženia. | Dlhý text zostáva počas čítania stabilný; dialóg má bežný krátky vstup. | P3 · [LegalScreen, LegalAdminScreen](../apps/mobile/lib/features/legal.dart) |
| A08 | Pomoc a odpovede | Odpoveď sa rozbalí do vlastnej výšky, 180–250 ms. | Prechod do podpory zachová súvislosť s vybranou témou. | P3 · [HelpScreen](../apps/mobile/lib/features/account.dart) |
| A09 | Výber demo profilu | Vybraná karta sa zdvihne a ostatné ustúpia. | Balíček kariet sa zloží do zvoleného profilu až po úspešnej zmene identity, 400–600 ms. | P2 · [DemoAccessCard, showDemoPicker](../apps/mobile/lib/features/demo.dart) |
| A10 | Faktúry, exporty a účtovné pripojenia | Riadok dokumentu ukáže prípravu a potvrdené uloženie súboru. | Krátke vysunutie listu z ikony pri dokončenom exporte, 250–400 ms. | P3 · [BillingScreen](../apps/mobile/lib/features/billing.dart) |
| A11 | Štart, obnovovanie a chybový stav aplikácie | Zástupný obsah drží rozmery; výsledok nahradí iba potrebnú plochu. | Úvodný znak môže raz dosadnúť; opakovaný pokus zachová obsah aj akcie. | P3 · [Bootstrap](../apps/mobile/lib/main.dart) |

## Podpora a administrácia

| ID | Miesto | Malý pohyb | Výraznejší prechod | Priorita / zdroj |
|---|---|---|---|---|
| S01 | Aktivita a neprečítané udalosti | Badge sa zvýrazní pri novej udalosti, označený riadok plynulo zoslabne, 180–240 ms. | Karta udalosti otvorí súvisiacu požiadavku cez krátky presun. | P3 · [SupportActivityButton, SupportActivityScreen](../apps/mobile/lib/features/support/activity.dart) |
| S02 | Zoznam požiadaviek a pracovná fronta | Filter preskupí riadky so stabilnými identifikátormi. | Nová požiadavka sa po vytvorení zaradí do zoznamu, 250–350 ms. | P3 · [SupportScreen](../apps/mobile/lib/features/support/support.dart) |
| S03 | Správa, príloha, interná poznámka | Nová bublina príde zospodu; príloha sa presunie do rozpracovanej správy, 160–250 ms. | Zmena stavu uzavrie alebo znovu otvorí iba hlavičku prípadu; zachová prečítanú pozíciu. | P3 · [TicketScreen](../apps/mobile/lib/features/support/support.dart) |
| S04 | Vrátenie peňazí a finančné uvoľnenie | Krokový stav a výsledok sa zmenia po odpovedi služby. | Rozbaliť časovú os priebehu; čakajúci prevod zostáva viditeľne čakajúci. | P3 · [RefundSheet](../apps/mobile/lib/features/support/support.dart) |
| S05 | Fotografie v podpore | Stlačenie náhľadu, plynulý návrat. | Spoločná fotografia pri otvorení na celú plochu, 250–350 ms. | P3 · [SupportPhotoView](../apps/mobile/lib/features/support/photo.dart) |
| S06 | Správa používateľov, firiem, pobočiek, ponúk, recenzií, operátorov, auditu a doručovania | Výber sekcie, filter a aktualizácia konkrétneho riadka, 150–220 ms. | Potvrdená zmena krátko zvýrazní dotknutý záznam a jeho nový stav. | P3 · [PlatformAdminScreen](../apps/mobile/lib/features/platform/admin.dart) |
| S07 | Kontrola pripravenosti | Výsledok každej skutočnej kontroly prejde do zodpovedajúcej ikony. | Súhrn sa rozbalí po dokončení; existujúce chyby ostanú čitateľné. | P3 · [PlatformReadinessScreen](../apps/mobile/lib/features/platform/readiness.dart) |

## Predajca

`MerchantPortalScreen` obsahuje šesť samostatných pracovných sekcií. Každá je zmapovaná aj napriek tomu, že nemá vlastnú verejnú triedu obrazovky.

| ID | Miesto | Malý pohyb | Výraznejší prechod | Priorita / zdroj |
|---|---|---|---|---|
| M01 | Prepnutie sekcie alebo aktívnej pobočky | Indikátor a obsah sa posunú v smere navigácie, 180–260 ms; zachovať kontext práce. | Pri pobočke sa plynulo vymení súhrn a potvrdený obsah. | P2 · [MerchantPortalScreen._shell](../apps/mobile/lib/features/merchant/portal.dart) |
| M02 | Prehľad a metriky | Potvrdené zmeny počtov sa dopočítajú; obnovenie rovnakých údajov zostáva stabilné. | Nová dnešná objednávka krátko doplní príslušný súhrn. | P2 · [MerchantPortalScreen._overview](../apps/mobile/lib/features/merchant/portal.dart) |
| M03 | Sklad, príjem, skladový pohyb, kvalita | Počet položiek a stav šarže sa zmenia spolu s uložením. | Prijatá šarža dosadne ako karta do skladu; zmena kvality zvýrazní konkrétny štítok, 350–600 ms. | P2 · [MerchantPortalScreen._stock](../apps/mobile/lib/features/merchant/portal.dart) |
| M04 | Zoznam a detail inventúr | Uložený počet krátko zvýrazniť; zmeny rozbaliť pri dotknutých riadkoch. | Uzavretá inventúra zloží rozpracovaný súhrn do potvrdeného záznamu, 350–500 ms. | P2 · [WarehouseScreen, WarehouseDetailScreen](../apps/mobile/lib/features/merchant/warehouse.dart) |
| M05 | Presun medzi pobočkami | Krok a množstvo sa aktualizujú podľa výsledku operácie. | Karta zásielky sa presunie od zdroja do stavu „odoslané“; do cieľa dosadne až po potvrdení fyzického príjmu, 500–900 ms. | P2 · [WarehouseDetailScreen](../apps/mobile/lib/features/merchant/warehouse.dart) |
| M06 | Vytvoriť, upraviť, publikovať alebo pozastaviť ponuku | Zmenený štítok dostupnosti a počet krátko dosadnú. | Potvrdená ponuka sa vysunie z editora ako karta do zoznamu, 400–650 ms. | P2 · [MerchantPortalScreen._offers](../apps/mobile/lib/features/merchant/portal.dart) |
| M07 | Automatizácie a spustenie pravidiel | Aktívne pravidlo a priebeh majú lokálny stav. | Vstupné položky sa zložia do skutočne vytvorených balíčkov; počet vychádza z výsledku operácie. | P2 · [MerchantPortalScreen._automation](../apps/mobile/lib/features/merchant/portal.dart) |
| M08 | Objednávky: výdaj, zrušenie | Potvrdená objednávka sa presunie do správneho stavu alebo filtra, 180–300 ms. | Pri výdaji krátka pečiatka; obsluha môže okamžite pokračovať ďalšou objednávkou. | P2 · [MerchantPortalScreen._orders](../apps/mobile/lib/features/merchant/portal.dart) |
| M09 | Nastavenia firmy, pobočky a skladové pripojenia | Uložený riadok alebo stav spojenia sa zmení na mieste. | Nová pobočka sa zaradí do zoznamu a jej karta dosadne, 250–400 ms. | P3 · [MerchantPortalScreen._settings](../apps/mobile/lib/features/merchant/portal.dart) |
| M10 | Univerzálny editor a výbery | Závislé polia a validačné správy plynulo zmenia výšku; vybraná položka zostáva čitateľná. | Uložený formulár nadviaže na kartu v rodičovskom zozname. | P3 · [MerchantEditor](../apps/mobile/lib/features/merchant/editor.dart), [MerchantChoicePage](../apps/mobile/lib/features/merchant/choices.dart) |
| M11 | Knižnica médií a nahrávanie fotografie | Náhľad sa mierne preklopí a po dokončení nahradí zástupný obsah. | Nová fotografia dosadne do mriežky; odstránenie uzavrie medzeru, 250–450 ms. | P2 · [MerchantMediaScreen](../apps/mobile/lib/features/merchant/media_library.dart) |
| M12 | Tím, pozvánka, práva, vlastníctvo | Zmena roly alebo stavu pozvánky dostane krátke potvrdenie. | Odoslaná pozvánka môže dostať skladací motív obálky; prenos vlastníctva používa pokojný krokový stav. | P3 · [MerchantTeamScreen, MerchantInviteScreen](../apps/mobile/lib/features/merchant/team.dart) |
| M13 | Tržby, účet, vyúčtovanie, export | Čísla a štítky sa zmenia až podľa potvrdených dát. | Otvorenie detailu vyúčtovania rozbalí jeho časovú os; odoslanie a prijatie ostávajú odlíšené. | P3 · [MerchantFinanceScreen](../apps/mobile/lib/features/merchant/finance.dart) |

## Natívna implementácia schváleného toku

Webový návrh trvá približne 7,8 s vrátane prestávok na prezretie jednotlivých scén. V produkcii treba choreografiu naviazať na skutočné stavy a kratšie prechody; hotová odpoveď nemá čakať na prehratie celej prezentácie.

| Udalosť | Pohyb | Cieľový čas pohybu | Podmienka výsledku |
|---|---|---|---|
| Stlačenie Zaplatiť | Stlačenie tlačidla, zdvih karty, rozloženie vrstiev. | 120–450 ms | Platný checkout; opakované odoslanie je blokované. |
| Otvorenie spracovania | Jedno 3D preklopenie a nábeh orbitov. | 600–900 ms | Operácia sa skutočne začala. |
| Čakajúca odpoveď | Pokojný orbit hlavného predmetu a čitateľný stav. | Podľa operácie | Zatiaľ nie je potvrdený výsledok. |
| Úspech | Dokončenie otočenia, pečiatka/check, krátke častice. | 600–900 ms | Demo rezervácia je uložená a `reserved`; pri reálnej platbe potvrdený výsledok príslušnej služby. |
| Prechod do objednávok | Spoločná karta sa presunie na miesto v zozname. | 450–650 ms | Objednávka je dostupná podľa stabilného ID. |
| Zlyhanie alebo zrušenie | Vrstvy sa vrátia ku košíku alebo k existujúcej rezervácii; chyba je čitateľná. | 250–400 ms | Zachovať rozpracované dáta, správny stav a možnosť opakovania. |

Vo Flutteri nadviazať na `AppMotion`, `AppPressScale`, `AppPageRoute` a existujúce haptiky. Sekvenciu riadiť jedným `AnimationController` a intervalmi; perspektívu, rotáciu a presun riešiť pomocou `Transform`/`Matrix4`. Fotografie medzi trasami môžu používať `Hero` so stabilným tagom. Samostatný overlay patrí letu do košíka, kde už existuje konkrétny cieľ. GSAP je súčasť webového návrhu.

Zdieľateľné stavebné bloky pre implementáciu:

- **Otáčaná karta:** predná/zadná strana, správne vykreslenie pri prekročení 90°, stabilný tieň a nulová zmena rozloženia okolia.
- **Pripravená sekvencia platby:** zdvih, vrstvy, preklopenie, čakanie, výsledok; samostatná logika obchodných stavov.
- **Presun spoločného predmetu:** stabilná identita, skutočný počiatočný a cieľový obdĺžnik, bezpečné ukončenie po navigácii.
- **Potvrdenie výsledku:** pečiatka/check s voliteľnými časticami; spustenie len raz pre konkrétnu dokončenú udalosť.
- **Zmena čísla a pozície karty:** smerová zmena ceny/počtu a preskupenie riadkov so stabilnými kľúčmi.

## Spoločné pravidlá

- Malé stlačenie 120–180 ms, zmena hodnoty 180–260 ms, prechod obsahu 250–400 ms. Výrazné jednorazové scény majú zvyčajne 600–1 100 ms na jeden motív.
- Haptika patrí akcii a potvrdenému výsledku. Zlúčiť súbežné požiadavky; scroll, písanie a neaktívne prvky zachovajú pokojný režim.
- Pri nastavení obmedzeného pohybu použiť priamu zmenu alebo krátke prelínanie. Zachovať všetky akcie, stavy, kód a informáciu o úspechu/chybe.
- Pri finančných, skladových a bezpečnostných úkonoch výsledný stav vychádza z uložených dát. Spracovanie, odoslanie a dokončenie majú rozdielny význam.
- Animácia zachová dotykovú plochu, sémantiku, poradie fokusu, rozpracované formuláre a polohu zoznamu. Podpore a obsluhe umožní pokračovať bez zbytočného čakania.
- Opakovaná návšteva alebo bežný rebuild neprehráva oslavu znovu. Animácie mimo viditeľnej sekcie sú zastavené a controllery/overlaye sa uvoľnia po odchode.
- Najviac jeden dominantný motív v danej chvíli; sprievodné častice a vrstvy sú dekoratívne a ignorujú dotyky aj čítačku obrazovky.

## Poradie realizácie a overenie

1. Preniesť platobnú kartu, vrstvy, rotácie a potvrdenie do existujúceho demo toku; zachovať čakanie, chybu, opakovanie, existujúcu objednávku a obnovu dát.
2. Nadviazať na kartu v objednávkach a rozvinutie kódu. Pridať potvrdenie vyzdvihnutia vrátane objednávok s viacerými položkami.
3. Rozšíriť let do košíka a meniace sa čísla. Prepojiť obchod, produkt a galériu spoločným predmetom.
4. Dokončiť mikrointerakcie navigácie, filtrov, mapy a obľúbených. Potom členstvo, kredit a onboarding.
5. Predajca: publikovanie ponuky a presun zásielky. Následne pokojné zmeny riadkov vo formulároch, podpore a administrácii.

Pri každom balíku overiť svetlý/tmavý vzhľad, veľký text, úzky displej, obmedzený pohyb, čítačku obrazovky, rýchle opakované tapy a odchod počas operácie. Pri nákupnom toku tiež pomalú/chybnú odpoveď, návrat aplikácie z pozadia, opakovanie bez duplikácie objednávky a obnovenie uloženého stavu. Výkon posúdiť v profilovacom režime na fyzickom iOS aj Android zariadení; pohyb má zachovať plynulý scroll a okamžitú odozvu na ďalšiu povolenú akciu.

## Rozsah inventúry

Zmapované verejné obrazovky: `HomeScreen`, `FavoritesScreen`, `CatalogScreen`, `StorefrontScreen`, `OfferDetailScreen`, `CartScreen`, `CheckoutScreen`, `DemoPaymentScreen`, `InvoiceScreen`, `OrdersScreen`, `OrderDetailScreen`, `OnboardingScreen`, `LocationScreen`, `ProfileScreen`, `AuthScreen`, `ClubScreen`, `WalletScreen`, `SettingsScreen`, `PrivacyScreen`, `HelpScreen`, `AccountSecurityScreen`, `AccountActionScreen`, `DemoMailScreen`, `LegalScreen`, `LegalAdminScreen`, `BillingScreen`, `SupportActivityScreen`, `SupportScreen`, `TicketScreen`, `MerchantPortalScreen`, `WarehouseScreen`, `WarehouseDetailScreen`, `MerchantMediaScreen`, `MerchantTeamScreen`, `MerchantInviteScreen`, `MerchantFinanceScreen`, `PlatformAdminScreen`, `PlatformReadinessScreen`.

Zahrnuté doplnkové plochy: `FiltersSheet`, `CouponSheet`, `RatingsSheet`, `ReviewsSheet`, `RefundSheet`, `PhotoGallery`, `ReviewPhoto`, `SupportPhotoView`, `MerchantEditor`, `MerchantChoicePage`, výber demo identity, jazykový panel, právny súhlas a potvrdenia akcií. Spoločné `PrimaryButton`, `RoundButton`, `SettingsRow`, `QuantityControl`, `SheetHeading`, `SectionHeading`, `EmptyState`, fotografie, stavové štítky a navigácia umožňujú šíriť malé animácie jednotne naprieč aplikáciou.
