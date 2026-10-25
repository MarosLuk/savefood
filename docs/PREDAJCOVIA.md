# Portál predajcu: web aj mobil

Portál je súčasťou spoločného Flutter jadra. Malá reštaurácia sa k nemu dostane v aplikácii cez **Profil → Moja prevádzka**. Samostatný webový vstup je `lib/main_merchant.dart`; počítač používa bočné menu a mobil spodnú navigáciu. Obe verzie používajú rovnaké účty, databázu a serverové pravidlá. Svetlý, tmavý aj systémový vzhľad sa prepínajú v menu **Vzhľad a účet**.

## Prvé nastavenie

1. Prihlás sa alebo vytvor bežný účet. Vyber **Založiť účet prevádzky**, vyplň firmu, IČO a prvú prevádzku vrátane adresy a polohy. Tento účet je vlastníkom firmy.
2. V **Sklad → Nová položka** vytvor SKU/EAN, názov, kategóriu, jednotku (kus, balenie, porcia, kilogram alebo liter), bežnú hodnotu jednotky, alergény, skladovaciu zónu a vlastnú fotografiu z knižnice, fotoaparátu alebo HTTPS adresy. SKU je text a zachová úvodné nuly. Kus/porcia/balenie vyžadujú celé množstvo; kg a l podporujú najviac tri desatinné miesta a ukladajú sa presne ako g/ml.
3. Prijmi konkrétnu šaržu: množstvo, označenie dátumu a najneskorší bezpečný výdaj. Pri hotovom jedle zadáva bezpečný čas prevádzkovateľ; aplikácia ho nevymýšľa. Nové importované šarže čakajú na kontrolu. Vlastník/manažér môže potvrdiť kvalitu; personál príjem iba pripraví.
4. V **Ponuky → Vytvoriť balíček** vyber receptúru jedného balíčka, počet, cenu po zľave a výdajové okno. Hodnotu obsahu a alergény spočíta server. Návrh možno schváliť, ponuku pozastaviť a upraviť cenu pre budúce objednávky. Pôvodné objednávky zachovajú svoju cenu a obsah.
5. Pri výdaji zadaj kód od zákazníka. Vydajú sa iba položky aktívnej prevádzky. Predajca nevidí fakturačné údaje, e-mail zákazníka ani uložený výdajový kód.

Vlastník pridáva ďalšie prevádzky a prístupy existujúcim účtom. Manažér spravuje sklad, kvalitu, ponuky a pravidlá. Personál prijíma zásoby, robí skladové pohyby a vydáva balíčky. Roly platia pre všetky prevádzky príslušnej firmy. Vytváranie a odvolanie integračných tokenov a zmeny členov tímu sú vyhradené vlastníkovi.

## Ako sa počíta sklad

- **Fyzicky**: počet skutočných jednotiek v šarži.
- **Rezervované**: jednotky zablokované čakajúcimi alebo zaplatenými objednávkami.
- **Voľné**: fyzicky mínus rezervované; nevyhovujúca alebo expirovaná šarža sa neponúka.

Pri objednávke server v jednej SQLite transakcii pridelí konkrétne šarže podľa FEFO: najbližší termín má prednosť. Dostupnosť sa zdieľa medzi ponukami, ktoré používajú rovnaké položky. Viac ponúk môže odkazovať na rovnaké SKU; ich uvedený počet sa dynamicky prepočítava a každá objednávka opäť overí celý košík. Návrhy neblokujú zásoby.

Pri prevzatí sa zníži fyzický aj rezervovaný stav. Storno uvoľní rezerváciu po úspešnom zrušení/refundácii platby. Po kontrole expirovanej nezaplatenej objednávky sa uvoľní aj jej sklad. Záporný pohyb ani externá inventúra nesmú znížiť fyzický stav pod rezervované množstvo. Skladové opravy majú verziu, dôvod a audit. Chyba jednej položky v košíku alebo importe vráti celú transakciu.

Zablokovanie kvality okamžite vyradí šaržu z nových ponúk a zablokuje výdaj existujúcich rezervácií. Tieto objednávky sa označia na riešenie. Manažér môže stornovať celú nevyzdvihnutú objednávku jednej prevádzky a odoslať refundáciu. Objednávky viacerých prevádzok rieši správca platformy alebo podpora. Operátor môže refundovať jednotlivé kusy aj z čiastočne vydanej objednávky; presne sa uvoľní iba nevydaný podiel zásob a vyrovná príslušná časť prevodu. Implementácia Stripe Connect a refundácií je pripravená, jej živá aktivácia zostáva na záver podľa zadania.

## Automatické balíčky

Pravidlo určuje kategóriu, skladovaciu zónu, počet dní pred termínom, minimálnu hodnotu obsahu, zľavu, denný limit, čas výdaja a režim zverejnenia. Predvolený režim je **najprv schváliť návrh**. Priame zverejnenie je výslovná voľba pri pravidle.

Server pravidlá kontroluje každú minútu a na požiadanie. Každé pravidlo vytvorí najviac jednu ponuku na kalendárny deň v pásme Europe/Bratislava; reštart a opakované spustenie nevytvoria duplikát. Pri nedostatku vhodných zásob sa pravidlo preskočí a môže uspieť pri ďalšej kontrole. Zmena pravidla už vytvorenú dnešnú ponuku neprepíše.

Obsah vyberá deterministicky podľa najbližšieho termínu, do dosiahnutia minimálnej hodnoty. Používa iba skontrolované šarže, rovnakú kategóriu a skladovaciu zónu. Musia byť vhodné počas celého výdajového okna aj v časovom horizonte pravidla. Alergény sú zjednotením položiek; automatické diétne tvrdenia sa nepridávajú. Cena sa odvodí od skutočnej hodnoty receptúry a zľavy, najmenej 0,50 €.

Dátum spotreby súvisí s bezpečnosťou, minimálna trvanlivosť s kvalitou. Aplikácia má pre automatizáciu konzervatívne pravidlo neprekročiť zadaný termín pri oboch označeniach. [Vysvetlenie EFSA](https://www.efsa.europa.eu/enIE/safe2eat/food-date-labelling). Pri hotových jedlách a skladovaní sa vychádza z overených postupov prevádzky.

## CSV a skladové prepojenie

CSV import prijíma existujúce SKU, najviac 200 riadkov na dávku, čiarku alebo bodkočiarku, UTF-8 a citované polia. Všetky nové položky idú na kontrolu. Príklad:

```csv
sku,lotCode,quantity,deadline,dateType
000123,PEK-2410-A,12,2026-12-01T22:59:00Z,bestBefore
MENU-01,KUCHYNA-A,8,2026-12-01T14:00:00Z,useBy
```

V **Nastavenia → Pokladňa a externý sklad** vytvor pripojenie. Token sa zobrazí raz, patrí iba jednej prevádzke a dá sa odvolať. V databáze sa ukladá jeho hash; opakované načítanie odpovede cez idempotency key token znova nevráti. Token neposkytuje prístup k zákazníckym účtom ani ostatným prevádzkam.

`GET /v1/integrations/stock` s `Authorization: Bearer <skladový-token>` vráti vlastné šarže, SKU, fyzický a rezervovaný stav a verziu. `POST` na rovnakú cestu prijme napríklad:

```json
{
  "eventId": "pos-receipt-20261201-000001",
  "operation": "receive",
  "sku": "000123",
  "lotCode": "PEK-2410-A",
  "quantity": 12,
  "deadline": "2026-12-01T22:59:00Z",
  "dateType": "bestBefore"
}
```

Operácia `adjust` používa rovnaké SKU/šaržu, `delta` (napr. -2) a `reason`. Operácia `set` používa `onHand`, `reason`, `expectedVersion` z posledného načítania a rastúce `sequence` pre pripojenie a šaržu. Staršia verzia alebo poradie skončia 409 a vyžadujú zosúladenie. Každá udalosť má trvalé `eventId`; identické opakovanie vráti pôvodný výsledok, iný obsah s tým istým ID skončí 409. Príjem z ERP nemôže sám schváliť kvalitu.

Adaptér musí do externého skladu preniesť aj výdaje aplikácie alebo ich zohľadniť pri inventúrnom zosúladení, aby sa už odovzdané jednotky nevracali späť. Načítaním verzie sa nenahrádza vecné zosúladenie dvoch systémov. Konkrétny ERP/POS adaptér sa dokončí podľa API a prístupov daného systému; žiadny živý sklad zatiaľ nebol pripojený.

Každá mutácia `/v1/merchant/*` používa `idempotencyKey` (16 až 100 znakov); formulár ho zachová pri opakovaní po výpadku. Zmena obsahu s už použitým kľúčom skončí 409. Skladové integračné udalosti používajú vlastné `eventId`. Storno je idempotentné podľa objednávky a poskytovateľskej refundácie.

## Spustenie webu

```sh
PATH=/Users/maroslukac/Desktop/flutter/bin:$PATH bash tool/build_merchant_web.sh \
  --dart-define=API_BASE_URL=http://127.0.0.1:8080
python3 -m http.server 7358 --bind 127.0.0.1 --directory apps/mobile/build/merchant-web
```

V bežnej webovej aplikácii otvorí portál aj `/?portal=merchant`. Webový build a mobilný klient musia používať ten istý `API_BASE_URL`. Pri samostatnej verejnej doméne portálu doplň jej HTTPS origin do `ALLOWED_ORIGINS`. Portál pracuje v sandboxe aj Stripe režime API; nové účty a sklad sa ukladajú na server.

Schéma sa doplní pri otvorení existujúcej databázy. Pred aktualizáciou produkčnej databázy vytvor zálohu. Skladové objednávkové riadky majú indexy a dopĺňajú sa aj z existujúcich rezervácií. Aktuálny backend je jeden aktívny Shelf/SQLite proces. Lokálny záťažový test s 5 000 SKU prešiel; pred rozsahom celej obchodnej siete treba merať zvolený hosting a pri horizontálnom škálovaní pripraviť serverovú databázu a distribuované zámky. Prevádzkové rozhranie používa serverové stránky po 50 riadkoch a indexované vyhľadávanie; výbery receptúr, príjmov a presunov prehľadávajú aj ďalšie stránky. Inventúrne riadky majú samostatné stránky po 100 a skladový integračný snapshot po 200.

Predajcovský portál obsahuje aj financie vlastníka a vstup do zákazníckej podpory. Tikety, operátorské reklamácie, refundácie, Connect a účtovné podklady opisuje [samostatný návod](FINANCIE_A_PODPORA.md). Refundácia vydaného jedla ho nevracia do skladu.

## Overenie implementácie

Aktuálne prešlo 288 testov v štandardnej sade; analyzer je bez nálezov. Navyše prešiel explicitný skladový záťažový test a test online zálohy/obnovy. Pokryté sú FEFO, rollback, kvalita, inventúry, presuny, presné kg/l, roly pobočiek, prepínanie účtov, importy, poradie ERP udalostí, refundácie aj ochrana fotografií a dokladov. Všetky tri weby, dva Android debug APK a iOS simulátorová zostava boli znovu zostavené 25. 10. 2026. Podrobný rozsah a zostávajúce externé kroky sú v [DOKONCENIE.md](DOKONCENIE.md).

Obrazovky v `docs/screenshots/merchant-*` sú skutočný Flutter render s ukážkovými údajmi z testov. Export: `flutter test test/merchant_preview_test.dart --dart-define=CAPTURE_PREVIEWS=true` z `apps/mobile`. Kontrolované šírky 375, 768 a 1440 px; manuálna vizuálna kontrola svetlej aj tmavej témy. Pri väčších prevádzkach je stále potrebné overiť záťaž a konkrétny skladový adaptér.

Pripravené predajcovské účty už nie sú iba súčasťou vizuálnych testov: `bash tool/demo.sh` naplní samostatnú databázu pre skutočný web aj mobil. Návod a scenáre sú v [DEMO.md](DEMO.md).

Inventúry, presuny zásob medzi pobočkami vrátane príjmu a karantény, fotografické reklamácie a upozornenia: [podrobný postup](SKLAD_A_REKLAMACIE.md).

## Tímy, integrácie a nové doklady

Vlastník vie pozvať kolegu e-mailom, obmedziť jeho prístup na pobočky a po opätovnom overení odovzdať vlastníctvo overenému členovi. Pravidlá platia na serveri.

GET /v1/integrations/changes vracia trvalé skladové udalosti po 200; POST /v1/integrations/changes/ack potvrdzuje doručenú sekvenciu. Samostatný konektor spracuje výdaje, rezervácie, presuny a opravy bez spätnej echo slučky. Konkrétne mapovanie ERP/POS ostáva závislé od vybraného partnera.

Faktúry a fakturačný profil obsahujú PDF/JSON doklady a vytvorenie oddeleného účtovného tokenu. Kompletný rozsah, overenie a hranice nasadenia: [DOKONCENIE.md](DOKONCENIE.md).
