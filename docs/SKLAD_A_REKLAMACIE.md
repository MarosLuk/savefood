# Inventúry, presuny a fotografické reklamácie

Prevádzkové funkcie pre predajcov aj zákazníkov. Zdieľajú účet, sklad a server s mobilnou aplikáciou a samostatným predajcovským webom. Používateľ 25. 10. 2026 určil, že ostré platby sa zapoja na záver; toto rozšírenie sa sústreďuje na prevádzku.

## Inventúra

**Predajca → Sklad → Inventúry a presuny → Nová inventúra.** Pri založení sa uloží zoznam šarží, fyzické množstvá a verzie. Pracovník zadá skutočné počty a uloží ich; uloženie počtov ešte nemení sklad. Rozdiely naraz schváli vlastník alebo manažér. Pri väčšej inventúre možno postupne ukladať dávky do 200 zmenených šarží.

Schválenie je jedna SQLite transakcia. Ak počas počítania pribudla šarža, prebehol výdaj, príjem alebo iná zmena verzie, schválenie sa odmietne. **Obnoviť zmenené šarže** aktualizuje predlohu; zmenené riadky treba znovu spočítať, nezmenené uložené počty sa zachovajú. Neuložené miestne úpravy rozhranie pred obnovou oznámi. Množstvo sa nedá znížiť pod aktuálne rezervácie. Ak zásoba chýba aj pre už rezervované objednávky, najprv treba vyriešiť tieto objednávky.

Schválenú inventúru nemožno zaúčtovať druhýkrát. Nová oprava ide cez ďalšiu inventúru alebo zdôvodnený skladový pohyb. Rozpracovanú inventúru môže vedúci zrušiť. Pre jednu pobočku môže byť otvorená jedna inventúra. Každý krok má aktéra, čas a audit.

## Presuny medzi pobočkami

Pobočky musia patriť tej istej firme a používať spoločný produkt. Vytvorenie konceptu nemení zásoby. **Potvrdiť odoslanie** odpočíta zo zdroja iba voľné, skontrolované kusy pred termínom a zaeviduje ich ako **Na ceste**. Ochrana rezervácií sa kontroluje znovu až pri odoslaní.

V cieli sa zásoby objavia po **Potvrdiť fyzický príjem**. Vznikne dohľadateľná samostatná šarža s pôvodným termínom a označením dátumu. Bežný príjem zostáva na kontrolu kvality; manažér môže výslovne potvrdiť jej vykonanie. Systém nedovolí predĺžiť dátum ani sprístupniť zadržanú alebo exspirovanú šaržu tým, že sa presunie do inej pobočky.

Vyradenie pôvodnej šarže sa prenesie aj na jej už prijaté potomky. Karanténa sa rovnako prenesie na nadväzujúce predajné zásoby. Opätovná kontrola pôvodnej šarže automaticky neschváli zásoby v inej pobočke. Rezervácie nad nespôsobilou šaržou zostanú evidované a existujúca automatická kontrola ich zaradí podpore; nový predaj a výdaj ich neobídu.

Koncept možno zrušiť. Tovar na ceste musí byť prijatý alebo musí obsluha potvrdiť jeho **fyzický návrat**. Návrat vytvorí v zdroji osobitnú šaržu na kontrolu, aby sa nezmiešal s pôvodnými zásobami a nezmenil kvalitu už rezervovaných kusov. Vyradený tovar zostane vyradený. Opakovanie požiadavky s rovnakým kľúčom neodpočíta ani neprijme tovar druhýkrát. Staršie presuny a inventúry možno načítať po stránkach aj nad 100 záznamov.

## Reklamácia s fotografiami

Zákazník vytvorí požiadavku z profilu alebo objednávky. V konverzácii použije **Priložiť fotografie**, v iOS/Androide aj **Odfotiť**. K správe možno priložiť najviac tri fotografie; možno poslať aj samotnú fotografiu bez textu. Rozpracované nahraté fotografie sa uchovajú pri tikete, dajú sa odstrániť alebo odoslať neskôr. Android obnovuje výsledok výberu aj po ukončení aktivity systémom.

Server prijíma statické JPEG/PNG do 5 MB a 20 megapixelov, overí skutočný obsah a vytvorí JPEG najviac 2048 px bez EXIF a pôvodných metadát. Súčasne spracúva najviac dve fotografie. Jeden tiket má limit 50 fotografií a 25 MB. Neodoslané prílohy sa po 24 hodinách vyčistia.

Fotografie nie sú verejné súbory. Pri každom načítaní sa vyžaduje prihlásenie a oprávnenie k tiketu. Rozpracovaný obrázok vidí iba odosielateľ. Operátor môže pripojiť fotografiu k internej poznámke; zákazník nedostane ani jej obsah, ani prílohu. Prílohy sú v SQLite databáze a patria do jej zálohy. Zobrazenie v aplikácii používa autentifikované načítanie do pamäte.

## Operátorská fronta a úplná história

Fronta podporuje vyhľadávanie predmetu, čísla tiketu a objednávky bez diakritiky, stavy, priority, moje/nepriradené prípady a iba neprečítané. Operátor môže prevziať požiadavku, zmeniť stav, prioritu a priradenie inému aktívnemu operátorovi. Konflikt verzie vyžaduje obnovenie údajov, takže kolega neprepíše cudziu novšiu zmenu.

Konverzácia načíta posledných 50 správ; **Načítať staršie správy** sprístupní celú uloženú históriu. Otvorená konverzácia získava novšie správy postupne podľa kurzora, takže nevynechá medzeru pri väčšom počte odpovedí. Audit sa tiež stránkuje a vidí ho iba operátor. Automatický asistent zostáva jasne označený a odpovedá podľa pravidiel, nepoužíva LLM.

## Upozornenia

Zvonček **Podpora a upozornenia** je v zákazníckej aplikácii aj predajcovskom webe. Nové odpovede vytvoria trvalé udalosti a počet neprečítaných požiadaviek. Označenie ako prečítané potvrdí len načítaný kurzor; odpoveď, ktorá prišla neskôr, sa nestratí. Interné udalosti zostávajú operátorom. Z centra sa otvorí konkrétna konverzácia alebo celá fronta.

Push pre podporu má samostatnú voľbu **Správy zákazníckej podpory** v nastaveniach. Používa existujúcu konfiguráciu Firebase/APNs; in-app centrum funguje aj bez nej. Fronta doručenia má pokusy a oneskorenia, pred odoslaním preverí reláciu, oprávnenie, používateľovu voľbu aj stav prečítania. Text push je všeobecný, neobsahuje text reklamácie ani fotografiu. Kliknutie otvorí príslušný tiket. Bez poverení poskytovateľa nebolo overené živé doručenie. E-mail a SMS sa v tejto verzii neposielajú.

## API

Operácie používajú Bearer používateľský token; zmeny JSON aj `idempotencyKey`. Koncepty, príjem a schválenie majú navyše očakávanú `version`.

| Funkcia | Endpoint |
|---|---|
| Prehľad operácií a ďalšie stránky | `GET /v1/merchant/stock/operations?storeId=…&beforeCounts=…&beforeTransfers=…` |
| Založenie inventúry | `POST /v1/merchant/stock/counts` |
| Detail / zmena inventúry | `GET /v1/merchant/stock/counts/<id>`, `POST …/<id>` |
| Akcie inventúry | `save` + `lines`, `rebase`, `post`, `cancel` |
| Založenie presunu | `POST /v1/merchant/stock/transfers` |
| Detail / zmena presunu | `GET /v1/merchant/stock/transfers/<id>`, `POST …/<id>` |
| Akcie presunu | `dispatch` + `lotVersion`, `receive` + `checked`, `return` + `physicallyReturned`, `cancel` |
| Fotografia do tiketu | `POST /v1/support/tickets/<id>/photos`, surové binárne telo |
| Autorizované zobrazenie | `GET /v1/support/photos/<id>` |
| Odstránenie rozpracovanej fotografie | `POST /v1/support/photos/<id>/discard` |
| Správa s prílohami | `POST /v1/support/tickets/<id>/messages` + `attachments: [id]` |
| Staršie / novšie správy | `GET /v1/support/tickets/<id>?before=…` alebo `?after=…` |
| Audit a operátori | `GET /v1/support/tickets/<id>/audit?before=…`, `GET /v1/support/agents` |
| Udalosti / prečítanie | `GET /v1/support/notifications?before=…`, `POST …/notifications/read` + `through` |
| Prečítanie konverzácie | `POST /v1/support/tickets/<id>/read` + `through` |

Sklad naďalej používa celé jednotky kus/balenie/porcia. Konkrétny ERP/POS adaptér potrebuje určenie systému a jeho API; nové operácie sú pripravené cez spoločné autorizované API. SQLite prevádzka predpokladá jeden aplikačný proces. Pred veľkou produkčnou sieťou ostávajú záťažové testy a infraštruktúrne rozhodnutia.

## Závislosti

`image_picker` je pripnutý na 1.2.3 kompatibilný s Flutter 3.38/Dart 3.10; 1.2.4 vyžaduje novšie SDK. Spracovanie obrázkov používa `image` 4.10.1. Overené podľa [oficiálneho changelogu Flutter pluginu](https://pub.dev/packages/image_picker/changelog) a [dokumentácie dekodéra](https://pub.dev/documentation/image/4.10.1/image/Decoder-class.html). App iOS má popisy účelu fotoaparátu a výberu fotografií.
