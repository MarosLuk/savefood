# Dokončenie funkčných oblastí · 25. 10. 2026

Každý bod pôvodného zoznamu má implementáciu alebo konkrétnu hranicu vyžadujúcu externé údaje. Produkčné platby zostávajú na záver podľa zadania. Lokálne demo používa fiktívne údaje a nemôže byť spustené s produkčným režimom ani s kľúčmi Stripe, Firebase alebo e-mailovej služby.

Následne potvrdené: Hetzner, dočasne HTTPS na IP bez domény, predajňa ako vystavovateľ dokladov za potraviny. Príprava: [HETZNER.md](HETZNER.md), `compose.hetzner.yaml` a `infra/Caddyfile.ip`; model je pripnutý cez `BILLING_SELLER_MODEL=merchantSeller`. ERP/POS a účtovníctvo zostávajú neurčené. Skutočná identita platformy a predajní ešte nebola dodaná.

Doplnené je Firebase Apple/Google prihlásenie a registrácia, nový názov Save Food a com.dakoty.savefood pre iOS/Android. Konfigurácia a hranice živého overenia: [FIREBASE.md](FIREBASE.md).

## 1. Účty a bezpečnosť

- Jednorazové overenie e-mailu a obnova hesla: 8-miestny kód, platnosť 15 minút a najviac päť pokusov. Server ukladá hash; odpoveď obnovy neprezradí existenciu účtu.
- Zmena hesla alebo e-mailu a vymazanie vyžadujú aktuálne heslo alebo krátkodobé overenie cez pôvodný e-mail. Nová adresa sa potvrdzuje samostatne. Bezpečnostná zmena odvolá relácie a zariadenia.
- Export profilu, objednávok, kreditu, recenzií, členstiev, dokladov a zákazníckej komunikácie. Heslá, prihlasovacie tokeny, interné poznámky podpory ani cudzie súkromné koncepty neobsahuje.
- Odstránenie/anonymizácia účtu s kontrolou aktívnych objednávok, členstva a vlastníctva firmy. Posledného správcu nemožno odstrániť bez náhrady. Finančné záznamy sa uchovávajú podľa nastavenej politiky.
- Apple a Google OAuth identity s overeným e-mailom sa označia ako overené. Heslá sa neobchádzajú prihlasovaním do účtu s rovnakou adresou od iného poskytovateľa.

Kód: [accounts.dart](../apps/api/lib/src/accounts.dart), [account_security.dart](../apps/mobile/lib/features/account_security.dart). Overenie: account_lifecycle_test.dart, media_access_test.dart, platform_test.dart.

## 2. E-mail

Trvalá fronta má deduplikáciu, poskytovateľský idempotentný kľúč, opakovanie s odstupom a vypršanie. Po doručení alebo vypršaní sa citlivé telo vyčistí. Adaptér Resend je implementovaný; bez poverení sa skutočné správy neodosielajú. E-maily o objednávkach a podpore možno vypnúť, bezpečnostné správy ostávajú samostatné. Pozvánky majú overenie cieľovej adresy.

Demo schránka existuje iba v režime DEMO_SHOWCASE. Simuluje doručenie pre testovacie identity; nie je to produkčný prístup k e-mailovým schránkam.

Kód: [mail.dart](../apps/api/lib/src/mail.dart), [account_routes.dart](../apps/api/lib/src/account_routes.dart), support_activity.dart. Overenie: account_lifecycle_test.dart a legal_test.dart. Aktivácia potrebuje MAIL_FROM, RESEND_API_KEY, overenú odosielaciu doménu a doručovací test.

## 3. Fotografie predajcu a zákazníka

- Knižnica predajcu, galéria, fotoaparát, náhľad a výber pri tvorbe produktu alebo balíčka.
- Vlastníctvo a roly kontroluje server aj po asynchrónnom spracovaní. Používanú produktovú fotografiu nemožno odstrániť z produktu, ponuky ani histórie objednávok.
- JPEG/PNG do 5 MB a 20 megapixelov, orientácia, zmenšenie do 2048 px, nový JPEG bez pôvodných metadát. Limity knižnice a súbežného spracovania chránia server.
- Koncept zákazníckej fotografie je súkromný. Verejná je až ako príloha povolenej recenzie. Podporné fotografie ostávajú súkromné.
- Obnova rozpracovaného výberu po ukončení Android aktivity zachováva príslušný účet a cieľ.

Kód: [media.dart](../apps/api/lib/src/media.dart), [image_codec.dart](../apps/api/lib/src/image_codec.dart), [media_library.dart](../apps/mobile/lib/features/merchant/media_library.dart). Overenie: media_access_test.dart, detailed_reviews_test.dart a Flutter testy.

## 4. Veľké sklady, pobočky a tímy

Pracovné prehľady načítavajú 50 riadkov a referencie potrebné na ich zobrazenie. Vyhľadávanie produktov a šarží používa udržiavaný normalizovaný index. Výber receptúry, príjmu a presunu dokáže vyhľadať položku mimo prvej stránky. Inventúra má 100 riadkov na stránku, globálny stav dokončenia, serverové vyhľadávanie a transakčné schválenie.

Roly vlastník/manažér/personál možno obmedziť na pridelené pobočky. Cieľová pobočka vie prevziať zásielku bez správy zdroja a bez zobrazenia jeho rezervácií. Pozvánky sú jednorazové, viazané na overený e-mail a platia sedem dní. Vlastníctvo možno odovzdať existujúcemu overenému kolegovi po opätovnom overení oprávnenia.

Kilogramy a litre sa ukladajú ako celočíselné gramy a mililitre, s presnosťou na tri desatinné miesta. Rovnaké jednotky používajú príjmy, úpravy, receptúry, presuny, inventúry, CSV a integračné udalosti. Kusové jednotky zostávajú celé. Hodnota receptúry sa zaokrúhľuje až po spočítaní.

Existujúce FEFO rezervácie, kvalita, termíny, bezpečný výdaj, inventúrne konflikty a pôvod presunutých zásob zostávajú serverové invarianty.

Kód: merchant_access.dart, merchant_paging.dart, warehouse.dart, partial_stock.dart a Flutter merchant/choices.dart. Overenie: merchant_paging_test.dart, weighted_stock_test.dart, warehouse_test.dart, media_access_test.dart.

## 5. ERP/POS a účtovný konektor

Príchod z externého skladu používa oddelený token pobočky, SKU, stabilné eventId, kontrolu jednotky a verzie. Externý príjem vždy čaká na kontrolu kvality. Absolútna synchronizácia neprepíše novšiu sekvenciu ani nespotrebuje rezervované zásoby.

Odchádzajúci trvalý feed zahŕňa príjmy, rezervácie, uvoľnenie, výdaj, úpravy, kvalitu a presuny. Každá udalosť obsahuje absolútny stav aj delty a jednotku. Prijímateľ potvrdzuje až doručenú sekvenciu. Označenie echo zabraňuje spätnej slučke vlastných udalostí.

Samostatný HTTP konektor je spustiteľný:

~~~sh
dart run apps/api/bin/erp_connector.dart --once
dart run apps/api/bin/erp_connector.dart --accounting --once
~~~

Konfigurácia je výhradne v prostredí: MARKETPLACE_URL, STOCK_TOKEN alebo ACCOUNTING_TOKEN, ERP_URL, ERP_TOKEN, CONNECTOR_STATE_PATH. ERP_PULL_INCOMING zapne príjem. Nešifrovaný HTTP je povolený iba explicitne pre lokálny loopback test cez ERP_ALLOW_LOOPBACK.

Zmluva prijímateľa:

| Endpoint partnera | Požiadavka | Potvrdenie |
|---|---|---|
| POST /stock/events | nevyhadzuj.stock.v1 + idempotency-key | presné eventId a acceptedSequence |
| GET /stock/inbound?after=… | najviac 200 stabilných udalostí erp-* | events, nextCursor, hasMore |
| POST /accounting/documents | nevyhadzuj.billing.v1 + idempotency-key | presné documentId a hash |

Pri výpadku sa nepotvrdí ďalší kurzor. Opakovanie používa rovnakú identitu udalosti alebo dokladu. Účtovný token má oddelený rozsah vystavovateľa a možno ho odvolať z portálu. Prenášaný účtovný JSON je verzované rozhranie, nie univerzálny importný formát konkrétneho účtovného programu.

Kód: stock_connector.dart, erp_bridge.dart, accounting_connector.dart. Overenie: stock_connector_test.dart a billing_test.dart vrátane stratenej odpovede a oddelenia vystavovateľov.

**Chýba externé rozhodnutie:** konkrétny ERP/POS/účtovný program, jeho prístup, mapovanie katalógu a partnerov a akceptačný test na jeho strane. Konektor sa neoznačuje ako živé napojenie POHODA, OMEGA alebo iného neurčeného produktu.

## 6. Hodnotenia

Celkové hodnotenie, kvalita, hodnota, množstvo a vyzdvihnutie; histogram a priemery za všetky zverejnené hodnotenia; stránkovanie; najviac tri vlastné fotografie. Hodnotiť môže zákazník s vydaným balíčkom. Vlastnú recenziu upraví alebo odstráni. Moderáciu nemožno obísť úpravou skrytej recenzie.

Kód: reviews.dart na serveri aj vo Flutter klientovi. Overenie: detailed_reviews_test.dart, platform_test.dart a completion_features_test.dart.

## 7. Administrácia

Samostatný vstup main_admin.dart a web na porte 7359. Roly admin, moderator a auditor má server; v klientovi nie je administrátorský secret. Obsahuje účty, firmy, pobočky, ponuky, recenzie, operátorov podpory, doručovanie, audit, fakturačné nastavenia, podmienky a prevádzkové kontroly.

Správca pozastaví účet, firmu alebo predaj v jednej pobočke; zmenu odôvodní. Moderátor má len obsahové oprávnenia, auditor iba čítanie. Pozastavenie skrýva príslušné ponuky a zastavuje príslušné vyúčtovanie; aktívne objednávky sa odovzdajú podpore na preverenie. Posledného správcu nemožno odobrať.

Kód: platform.dart, platform_routes.dart, runtime_status.dart, Flutter features/platform/. Overenie: platform_test.dart, runtime_test.dart a responzívne Flutter testy.

## 8. Refundácie a doklady

Operátor vyberá počet kusov, aj jeden kus z viac-kusového riadka. Rozdelenie zľavy, poplatku, kreditu, provízie a platby zachová každý cent. Nevydané množstvo uvoľní iba príslušný podiel zásob. Vydané potraviny sa nevracajú do predajného skladu. Príslušná časť prevodu sa vyrovná samostatne.

Pri stratenej odpovedi sa opakuje tá istá operácia. Po uplynutí bezpečného okna sa vyžaduje spárovanie už existujúcej Stripe operácie podľa sumy, meny, prevodu a pôvodnej refundácie. Podpora má príslušné ovládanie; nevytvára sa naslepo ďalšia reverzia.

Doklady majú transakčný číselný rad, nemenný obsah a údaje vystavovateľa/odberateľa, hash a súkromné PDF. Opravný doklad používa pôvodné údaje a presné pôvodné jednotkové podiely DPH. Refundácia pred vystavením zníži fakturované množstvo. K dispozícii sú súkromné PDF, JSON export a účtovný feed. Bežný prevádzkový CSV denník ostáva samostatný.

**Pred použitím v produkcii treba rozhodnúť a schváliť:** fakturačnú identitu potvrdenej predajne a platformy, sadzby, retenčné lehoty a účtovné/daňové pravidlá vrátane platieb vopred. Implementovaný model vystavuje predajný doklad po prevzatí; bez schválenia tohto modelu účtovníkom sa nemá vyhlasovať za univerzálne daňové riešenie.

Kód: partial_refunds.dart, partial_stock.dart, billing.dart a Flutter billing.dart. Overenie: partial_refunds_test.dart, billing_test.dart a operations_test.dart. PDF ukážka: artifacts/demo-faktura.pdf, výslovne fiktívna.

## 9. Prevádzka a údaje

- Explicitný PAYMENT_MODE=disabled dovolí pripraviť produkčný systém s vypnutými platbami. Nepoužije sandboxovú platobnú ani vyúčtovaciu bránu.
- Zdravotná kontrola /health/ready a autorizovaná /v1/platform/readiness. Kontroly konfigurácie, fronty a agregované časy požiadaviek; v metrikách nie sú zákaznícke identifikátory ani vyhľadávací text.
- Online SQLite záloha, kontrolný súčet, kontrola integrity a obnova do nového súboru bez prepísania existujúcej databázy: [tool/backup.py](../tool/backup.py). Overená aj záloha bežiaceho dema a jej samostatná obnova.
- Docker obraz so správnym Linux SQLite runtime, písmom pre PDF, neprivilegovaným používateľom a zdravotnou kontrolou. Kontajner sa reálne spustil; samotná úspešná kompilácia sa nepovažuje za prevádzkový test.
- Produkčná Compose šablóna, HTTPS proxy Caddy, tri webové vstupy, trvalý disk a lokálny zálohovací proces. Caddy konfigurácia prešla validáciou.
- Verzované publikované podmienky, koncepty, identita prevádzkovateľa, súhlasy s konkrétnou verziou a elektronickými dokladmi. Nastavené lehoty riadia čistenie osobných údajov starých objednávok, uzavretej podpory, auditu účtu, mailov a konceptov fotografií.

**Nie je vykonané:** verejné nasadenie, DNS/TLS na vlastnej doméne, vzdialená/offsite záloha, produkčné doručovanie e-mailov, OAuth a FCM/APNs. Hetzner už je vybraný; chýba pridelená IP/prístup na server, neskôr doména, aktivácia poskytovateľov a reálne poverenia. Produkčné právne texty a účtovné identity sa nevymýšľajú.

## 10. Zostavenia, distribúcia a overenie

Zostavené sú zákaznícky web, portál predajcu, administrácia, Android debug APK a iOS simulátorová aplikácia. Nové obrazovky sa testujú pri šírke 375 a 1440 bodov v light/dark režime. Screenshoty sú v docs/screenshots/completion-*; živé demo bolo kontrolované aj v prehliadači. PDF sa skutočne vyrenderovalo a vizuálne skontrolovalo.

Release workflow pripravuje podpísaný Android App Bundle po dodaní štyroch CI signing secrets a webové artefakty. CI súbory sú pripravené, neboli spustené na vzdialenom GitHub účte. iOS produkčný archív a publikovanie vyžadujú Apple tím, certifikáty/profil a schválené obchodové údaje. Zostava pre simulátor nepreukazuje test na fyzickom zariadení.

Záťažový test: 5 000 SKU, 100 požiadaviek v skupinách po 20; približne 0,9 s celkovo, p95 približne 204 ms. ERP feed prešiel 5 006 udalosťami v 26 stránkach. Ide o lokálny in-process benchmark so syntetickými dátami, nie meranie internetovej produkcie. Výsledok je v artifacts/warehouse-load.json.

## Čo potrebuje prevádzkovateľ doplniť

1. ERP/POS a účtovný systém s mapovaním a testovacím prístupom.
2. Pridelenú IP a prístup na Hetzner, neskôr doménu; mailový účet/doménu, OAuth a Firebase/APNs.
3. Reálnu identitu platformy a predajní, schválené podmienky, retenčné a účtovné pravidlá. Vystavovateľ za potraviny už je určený: predajňa.
4. Android/iOS signing a distribučné účty, fyzické zariadenia a predprodukčný akceptačný test.
5. Až potom záverečnú aktiváciu a živé overenie platieb VISA, Apple Pay, Google Pay a Stripe Connect.

Technické podklady: [finančná správa – faktúry](https://www.financnasprava.sk/sk/podnikatelia/dane/dan-z-pridanej-hodnoty/vyhotovovanie-faktur), [Stripe – overenie reverzie](https://docs.stripe.com/api/transfer_reversals/retrieve), [Resend – idempotencia](https://resend.com/docs/dashboard/emails/idempotency-keys), [Caddy – reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy).
