# Financie a zákaznícka podpora

Implementované vo Flutter zákazníckej aplikácii aj v samostatnom predajcovskom webe. Rozhranie používa spoločné modré témy, svetlý/tmavý/systémový vzhľad a serverové oprávnenia. Lokálny režim bez API nemá serverovú podporu ani finančný portál.

## Vyúčtovanie predajcu

**Predajca → Prehľad → Financie** alebo karta financií v nastaveniach. Prístup má vlastník firmy; pracovník skladu ani cudzí predajca tieto údaje nevidia.

Prehľad obsahuje predaj po zľavách, refundácie, províziu, čistú sumu predajcu, uskutočnené prevody, stav pripojeného Stripe účtu a jednotlivé objednávky s fotografiou. Posledných 500 riadkov je v rozhraní, súhrny zahŕňajú celú históriu. Účtovný export môže pokryť zvolené obdobie do 366 dní.

Pri rezervácii vzniká nemenné rozdelenie ceny každého riadka v centoch. Kupón, servisný poplatok a kredit sa rozdelia metódou najväčších zvyškov; súčty presne sedia s objednávkou. Provízia sa uloží s objednávkou. Starším objednávkam migrácia nepridáva spätne novú províziu. Servisný poplatok zákazníka 2 % je oddelený od provízie predajcu.

Prevod sa vytvára až za vydaný riadok po uplynutí ochranného času. Spoločný košík môže obsahovať viac predajcov; výdaj jedného neuvoľní peniaze za ostatných. Kreditom krytú časť financuje disponibilný zostatok platformy. Stripe poplatky nie sú automaticky účtované ako provízia predajcu. Neoverený účet, finančné pozastavenie alebo rozpracovaná refundácia prevod blokujú.

**Prevedené predajcovi znamená prevod na jeho Stripe účet.** Následná výplata na banku podlieha nastaveniu a overeniu účtu u Stripe; aplikácia ju neoznačuje za pripísanú bankovú výplatu.

## Aktivácia Stripe Connect

Na serveri nastav:

```dotenv
PAYMENT_MODE=stripe
STRIPE_CONNECT_ENABLED=true
PLATFORM_COMMISSION_BPS=0
SETTLEMENT_DELAY_HOURS=24
AUTOMATIC_SETTLEMENTS=false
MERCHANT_APP_URL=https://predajca.example.sk
```

K tomu patria existujúce Stripe secret, publishable a webhook kľúče podľa [návodu na platby](PLATBY.md). `100` bázických bodov je 1 %. Povolená provízia je 0–50 %, ochranný čas 0–720 hodín. Predvolená provízia zostáva **0 %**, kým prevádzkovateľ neurčí dohodnutú sadzbu. `AUTOMATIC_SETTLEMENTS` je počiatočná voľba pre novo pripojených predajcov; vlastník ju potom mení prepínačom vo financiách. Vypnutie automatického vytvárania neodvolá už zaradené prevody.

Adaptér používa Stripe Accounts v2 `recipient`, Express hosted onboarding a capability `stripe_balance.stripe_transfers`; API verzia je pripnutá na `2026-09-30.endive`. Vlastník otvorí **Pripojiť Stripe**, doplní overenie a po návrate obnoví stav. Expirovaný odkaz vytvorí znovu cez prihlásený portál. Server pred prevodom znovu preverí schopnosť účtu prijímať prevody a pôvodnú platbu (menu, sumu, metadata, úspech a spor).

Používa sa model separate charges and transfers. Na platforme treba aktivovať Connect, zodpovedajúce oprávnenia a podporovaný cezhraničný/domáci tok. Overiť treba konkrétnu konfiguráciu platformy a príjemcov v Stripe testovacom režime. Živé účty, bankové výplaty a reálne VISA/Apple Pay/Google Pay transakcie bez poverení prevádzkovateľa neboli vykonané.

Webhook pridaj aj pre `charge.refunded` a `charge.dispute.created`. Neznáma externá refundácia pozastaví ďalšie vyúčtovanie. Spor vyvolá pozastavenie a pokus o reverziu známych prevodov. Vyriešenie sporu a prípadné opätovné odoslanie už reverzovaného prevodu vyžaduje prevádzkovú kontrolu v Stripe; nevytvára sa automaticky ďalšia výplata.

## Účtovné podklady

Každý zaplatený riadok vytvorí vyrovnaný prevádzkový denník: externá úhrada, zákaznícky kredit, záväzok voči predajcovi a príjem platformy. Refundácia, prevod a reverzia majú vlastné vyrovnané záznamy. Nezaplatené zrušené rezervácie sa nevykazujú ako prijaté tržby.

Tlačidlo **Exportovať účtovný CSV** na webe priamo stiahne súbor; mobil otvorí systémové uloženie/zdieľanie. Ide o UTF-8 CSV s BOM a oddeľovačom `;`. Identifikátory objednávky, položky, firmy a pobočky dopĺňajú druh operácie, účet, `debit_cents`, `credit_cents`, EUR a čas UTC. Obdobie je `[from, to)` v UTC; koncový dátum sa nezahŕňa. API navyše vráti identifikátory a stavy Stripe prevodov.

Tento CSV export je **prevádzkový podklad pre účtovníctvo**. Súkromné PDF faktúry a opravné doklady sú samostatný modul opísaný nižšie. Sadzba DPH sa neodhaduje (`vat_status=not_determined`), chýbajúcu daňovú identitu aplikácia nevymýšľa. Mapovanie účtov, schválenie daňového modelu, uzávierka a konkrétny adaptér POHODA/OMEGA/iného systému vyžadujú určenie systému a pravidiel prevádzkovateľa. Existujúce skladové API a CSV ostávajú podľa [návodu pre predajcov](PREDAJCOVIA.md). Pri migrácii sa staršie objednávky zaevidujú v prevádzkovom denníku v čase migrácie; pôvodný čas objednávky zostáva zachovaný samostatne.

## Požiadavky a operátor

Zákazník otvorí **Profil → Požiadavky a zákaznícka podpora** alebo podporu z konkrétnej objednávky. Zadá predmet, kategóriu a správu, môže pripojiť svoju objednávku. Dostane jasne označenú odpoveď **Automatický asistent** podľa kategórie. Ide o pravidlá a automatické triedenie, nie o LLM chat. Vlastnú požiadavku vie doplniť a uzavrieť; nová správa opätovne otvorí vyriešenú požiadavku.

Operátor má spoločnú frontu, filtre stavov, preberanie prípadu, verzie proti súbežnému prepísaniu, priority, verejné odpovede a súkromné interné poznámky. Potravinová kvalita sa označuje ako naliehavá. Technický problém platby alebo nespôsobilá rezervovaná šarža môže vytvoriť tiket automaticky. Zákazník nikdy nedostane interné poznámky, audit ani konverzáciu cudzieho účtu. Fronta aj história správ sa stránkujú po 50; staršie správy a audit sa načítajú ďalšími stránkami. Rozhranie priebežne obnovuje stav, keď je otvorené. Súkromné fotografické prílohy, centrum udalostí a FCM frontu podpory opisuje [rozšírený návod](SKLAD_A_REKLAMACIE.md). Prevádzkové e-maily sa odosielajú po konfigurácii mailovej služby; zákazník ich môže vypnúť v nastaveniach. SMS sa neodosielajú.

Operátora pridelí správca v samostatnej administrácii. Pôvodný servisný endpoint `POST /v1/admin/support/agents` zostáva dostupný s Bearer `ADMIN_TOKEN` (aspoň 32 znakov) a JSON `{ "email": "existujuci@ucet.sk", "enabled": true }`. Vypnutie používa `false`. Tajný administrátorský token sa nikdy nevkladá do Flutter aplikácie. V showcase je pripravená **Nina · zákaznícka podpora**; tento účet existuje iba v oddelenom lokálnom deme.

## Reklamácie a refundácie

Z tiketu s objednávkou operátor otvorí **Reklamácia a refundácia**, zvolí objednávkové riadky, počet kusov a dôvod. Možno refundovať aj jeden kus z viac-kusového riadka; suma a zľavy sa rozdelia presne na jednotky. Možno vrátiť jeden riadok zo zmiešaného košíka aj po výdaji iných položiek.

Server najprv obnoví prípadný nepotvrdený prevod a reverzuje už odoslanú sumu predajcu. Až potom vráti prislúchajúcu externú úhradu a kredit. Pri chybe poskytovateľa zostáva trvalá rozpracovaná operácia; **Obnoviť existujúcu refundáciu** opakuje tú istú požiadavku. Kredit sa nepripíše, kým externá refundácia nie je úspešne potvrdená. Vrátenie na kartu následne závisí od banky.

Nevydané rezervované kusy sa uvoľnia. Vydané potraviny sa refundáciou nevracajú do predajného skladu. Cashback, ktorý ešte nevznikol, sa prepočíta zo zvyšných potravín; už pripísaný cashback sa ponechá ako marketingový náklad platformy. Bežné celkové storno po čiastočnej refundácii je blokované; zostávajúce riadky rieši podpora.

## Obnova po výpadku

Prevody a refundácie majú trvalé identifikátory a idempotency key, používané opäť po výpadku odpovede. Objednávku zamyká spoločný procesný zámok voči výdaju, stornu a refundácii. Finančný worker po spustení prevádzky beží v minútovom cykle; v cykle spracúva najviac 20 prevodov. Nepotvrdené úlohy sa striedajú podľa posledného pokusu, aby neblokovali novšie prevody.

Nepotvrdená operácia po 23 hodinách sa automaticky neposiela znovu, aby neprekročila bezpečnú dobu opakovania poskytovateľa. Operátor pri prevode zadá existujúci `tr_…` cez **Spárovať existujúci Stripe prevod**; server overí sumu, menu, príjemcu aj settlement metadata. Nemožno iba ručne označiť ľubovoľný prevod za zaplatený. Podpora môže **Overiť a uvoľniť vyúčtovanie**, ale len po kontrole pôvodnej platby, refundácií, rezervovaných šarží a nepotvrdených prevodov. Tieto úkony majú audit.

Nejasné vytvorenie pripojeného účtu alebo externá refundácia mimo aplikácie vyžadujú prevádzkovú rekonciliáciu v Stripe a databáze; aplikácia nevymyslí náhradný účet ani druhú úhradu. SQLite verzia je určená pre jeden aktívny aplikačný proces; pred horizontálnym škálovaním treba databázové zámky a worker frontu.

## API

Všetky merchant/support endpointy používajú bežný Bearer používateľský token; výnimkou je administrátorské pridelenie operátora. Meniteľné požiadavky posielajú `idempotencyKey`. Klient je v `packages/marketplace_api/lib/src/operations_client.dart`.

| Operácia | Endpoint |
|---|---|
| Financie vlastníka | `GET /v1/merchant/finance/<org>` |
| Pripojenie / obnovenie účtu | `POST …/<org>/connect`, `POST …/<org>/refresh` |
| Automatické / ručné zaradenie | `POST …/<org>/automatic`, `POST …/<org>/settle` |
| Účtovný export | `GET …/<org>/export?from=YYYY-MM-DD&to=YYYY-MM-DD` |
| Moje požiadavky / fronta | `GET /v1/support/tickets?inbox=true&status=open&before=<cursor>` |
| Vytvorenie / detail | `POST /v1/support/tickets`, `GET …/<id>` |
| Správa / stav / uzavretie | `POST …/<id>/messages`, `POST …/<id>/status`, `POST …/<id>/close` |
| Objednávka pre operátora | `GET …/<id>/order` |
| Refundácia / obnovenie | `POST …/<id>/refund`, `POST …/<id>/refunds/<refund>/retry` |
| Rekonciliácia prevodu | `POST …/<id>/transfers/<job>/reconcile` |
| Kontrola pozastavenia | `POST …/<id>/release-finance` |

V `GET tickets` je `inbox=true` určené iba operátorovi; zákazník parameter vynechá. Pri zmene stavu sa posiela `expectedVersion`.

## Zdroje návrhu integrácie

Oficiálna dokumentácia overená 25. 10. 2026: [Accounts v2](https://docs.stripe.com/api/v2/core/accounts/create), [recipient konfigurácia](https://docs.stripe.com/connect/accounts-v2/connected-account-configuration), [Account Links v2](https://docs.stripe.com/api/v2/core/account-links/create), [oddelené charges a transfers](https://docs.stripe.com/connect/separate-charges-and-transfers), [Transfers API](https://docs.stripe.com/api/transfers/create), [reverzia prevodu](https://docs.stripe.com/api/transfer_reversals/create). Kód nespolieha na údaje od klienta ako potvrdenie platby alebo výplaty.

## Overenie tejto implementácie

Aktuálne 288 testov v štandardnej sade; analyzer bez nálezov. Finančné scenáre overujú centové súčty, izoláciu vlastníkov, súkromie poznámok, verzie tiketu, refundáciu pred a po výdaji, reverziu, stratenú odpoveď poskytovateľa, 23-hodinové pozastavenie, zmiešaný košík s kupónom a kreditom, históriu nad 500 riadkov a priechodnosť dlhšej fronty. Export používa kalendárne dátumy aj pri zmene letného/zimného času v Bratislave. Rozloženia prešli pri 375 a 1440 px v oboch témach a pri väčšom texte. Reálny HTTP tok bol manuálne overený cez webové demo; živý Stripe ani konkrétny ERP toto overenie nenahrádza.

## Doklady a dokončenie

Súkromné PDF faktúry, opravné doklady po jednotlivých kusoch, nemenné daňové podiely, číslovanie, archivácia a účtovný HTTP feed opisuje [DOKONCENIE.md](DOKONCENIE.md). Po strate odpovede za hranicou bezpečného idempotentného okna podpora spáruje presnú existujúcu Stripe refundáciu/reverziu. Opakovaný postup nemení pôvodnú požiadavku. Aktivácia ostrých platieb a schválenie daňového modelu ostávajú externými krokmi.
