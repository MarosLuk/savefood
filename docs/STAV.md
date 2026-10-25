# Save Food · stav implementácie · 25. 10. 2026

Rozšírená je zákaznícka aplikácia, portál predajcu aj samostatná administrácia. Analýzu každého dopĺňaného bodu, konkrétny kód a hranice overenia obsahuje [DOKONCENIE.md](DOKONCENIE.md).

Názov **Save Food**, identifikátor **com.dakoty.savefood** (iOS aj Android), Apple Team **QQ3UCX8XGK** potvrdený pre Dakoty Studio. Pripravená registrácia/prihlásenie cez Apple a Google pomocou Firebase, skutočný projekt a súbory ešte používateľ dodá: [FIREBASE.md](FIREBASE.md).

Potvrdené: Hetzner, dočasne HTTPS na verejnej IP bez domény; doklady za potraviny vystavuje predajňa (`merchantSeller`). ERP/POS ani účtovníctvo zatiaľ nie sú vybrané. Pripravená konfigurácia a postup: [HETZNER.md](HETZNER.md). IP a prístup na server ešte neboli poskytnuté; nasadenie nie je vykonané.

| Oblasť | Implementované | Zostáva pre ostrú prevádzku |
|---|---|---|
| Katalóg a nákup | Ponuky, fotografie, filtre, mapa, obľúbené, košík, objednávky, výdaj, kredit, kupóny a Klub | Reálne údaje partnerov a verejný server |
| Účty | Obnova/zmena hesla, overenie/zmena e-mailu, revokácia relácií, export a odstránenie/anonymizácia s kontrolou záväzkov | Aktivácia a doručovací test e-mailu |
| Fotografie | Knižnica predajcu, nahrávanie/fotoaparát, sanitizácia a vlastníctvo; súkromné podporné a recenzné koncepty | Fotoaparát a oprávnenia overiť na fyzických zariadeniach |
| Veľké sklady | Stránkovanie, indexované vyhľadávanie, receptúry, FEFO, kvalita, termíny, inventúry, presuny a pôvod šarže | Postupy partnerov a meranie na zvolenom hostingu |
| Pobočky a tím | Rozsah prístupov, roly, pozvánky a bezpečné odovzdanie vlastníctva | Prideliť reálnych pracovníkov |
| Vážený tovar | Presné kg/l v celočíselných g/ml vo všetkých skladových tokoch | Mapovanie jednotiek konkrétneho ERP |
| ERP/POS | Synchronizácia verzií, trvalý feed, potvrdenia, echo ochrana a spustiteľný HTTP konektor | Výber produktu, prístup, mapovanie a akceptácia partnera |
| Recenzie | Štyri dimenzie, celkové hodnotenie, fotografie, overený výdaj, histogram, úpravy a moderácia | Pilotné používanie |
| Administrácia | Admin/moderator/auditor, účty, firmy/pobočky, obsah, operátori, audit, podmienky, doklady a prevádzkové kontroly | Overený produkčný správca |
| Refundácie | Jednotlivé kusy, presné sumy, podiel nevydaných zásob, čiastočné reverzie a obnova po výpadku | Živé záverečné Stripe overenie |
| Doklady | Nemenné údaje, číslovanie, súkromné PDF, opravné doklady, archivácia, JSON a účtovný feed | Identita, predávajúci, sadzby a schválené pravidlá vrátane platieb vopred |
| Podpora | Tikety, pravidlová triáž/odpovede, fotografie, interné poznámky, audit, upozornenia a refundácie | Operátori a živé doručovanie |
| E-mail/OAuth/FCM | Adaptéry, fronty, bezpečné relácie a klientské toky | Účty/poverenia a skutočné doručovacie testy |
| Podmienky a súkromie | Koncepty, nemenné verzie, evidencia súhlasu a čistenie podľa nastavených lehôt | Schválené texty a údaje prevádzkovateľa |
| Prevádzka | Funkčný Docker, health/readiness, metriky, HTTPS/Compose šablóna, online záloha a samostatná obnova | Nasadenie na Hetzner/IP, neskôr doména, offsite záloha a produkčný akceptačný test |
| Dizajn a demo | Modrý light/dark/system, mobil/web, fiktívne účty, zásoby, fotografie a doklady | Spätná väzba z pilotnej prevádzky |
| Distribúcia | Tri webové buildy, Android debug APK, iOS simulátorová zostava a release CI konfigurácia | Produkčné podpisy, obchody, certifikáty a fyzické zariadenia |
| VISA/Apple Pay/Google Pay | Stripe implementácie; explicitne vypnutý produkčný režim bez sandboxových transakcií | Aktivácia až v závere podľa zadania |

Posledná úplná kontrola: analyzer bez nálezov; 288 testov v štandardnej sade (doména 30, API 171, HTTP klient 3, perzistencia 3, Flutter 81). Dva voliteľné obrazové exporty zostávajú mimo bežnej sady; ich predchádzajúce overenie je v historickom zázname. Navyše prešiel explicitný záťažový test a test online zálohy/obnovy.

Záťažový test s 5 000 SKU: 100 lokálnych požiadaviek, súbežnosť 20, približne 0,9 s celkovo a p95 približne 204 ms. Nejde o produkčný internetový benchmark ani všeobecnú garanciu výkonu.

Tvrdenie „všetko je 100 % aktívne v ostrej prevádzke“ by nebolo pravdivé. Nevybrané služby, podpisy a schválené právne/účtovné údaje nemožno nahradiť fiktívnym nastavením. Ich aktivácia a záverečné platby zostávajú konkrétnymi externými krokmi.
