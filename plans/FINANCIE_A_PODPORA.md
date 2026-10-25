# Financie a zákaznícka podpora

Cieľ: doplniť výplaty predajcom, účtovné podklady a podporu s konverzáciami, automatickým triedením a napojením na objednávky; zachovať sklad, platby, demo a svetlý/tmavý Flutter dizajn.

Známe: viac predajcov v jednej objednávke, platformová Stripe platba, kredit a kupóny, výdaj po riadkoch. Neznáme: ERP/účtovný systém, obchodná provízia a účty poskytovateľov (otázky odoslané používateľovi). Predvolená provízia zostáva 0 %, žiadne skutočné výplaty sa pri implementácii nevykonajú.

Možnosti: (A) samostatné platby predajcom by rozbili spoločný košík; (B) oddelené Stripe charges/transfers umožnia vyúčtovanie po výdaji a viac príjemcov; (C) minimálne CSV bez prevodov nevyrieši požadované výplaty. Vybrané B, s trvalým stavovým automatom a opakovateľnými Stripe požiadavkami. Použiť Accounts v2 recipient + Stripe-hosted onboarding; rovnaký model simuluje lokálny sandbox. Skutočný bankový payout nasleduje podľa nastavenia pripojeného účtu, UI nebude zamieňať transfer na Stripe účet s pripísaním na banku.

Najrizikovejšie: centové rozdelenie zliav/kreditu, obnova po výpadku po Stripe transfere a refundácia po výplate. Najprv čistý výpočet a testy invariantov, potom perzistentná koordinácia. Kredit môže vyžadovať financovanie zostatkom platformy; nesmie sa pripísať ako ďalšia kartová platba. Finančné doklady nesmú predstierať fiškálny doklad alebo automaticky určenú DPH.

- [x] Rozdelenie súm na riadky bez straty centov, nemenný snapshot a záznamy vyúčtovania.
- [x] Connect onboarding, overenie spôsobilosti, transfer po výdaji, obnova/idempotencia, provízia a rozpis.
- [x] Účtovné podklady a export s identifikátormi, stavmi a oddeleným kreditom/platbou; API pre vlastné účtovníctvo.
- [x] Tikety s históriou, správami, automatickými odpoveďami/triážou, prioritou, operátorom a oprávneniami.
- [x] Reklamácie a refundácie po položkách, koordinácia so skladom, kreditom a prevodmi.
- [x] Flutter financie a podpora pre zákazníka/predajcu/operátora; svetlá/tmavá a mobil/web.
- [x] Bohaté demo, testy, zostavenia, vizuálne overenie a aktualizovaná dokumentácia.

Testy: zaokrúhľovanie/alokácia na centy; izolácia predajcov a zákazníkov; nepovolené výplaty a refundácie; opakované požiadavky a návrat po chybe poskytovateľa; limity refundácií a správ; nezverejnenie súkromných údajov; responzívne widgety a reálny HTTP tok.

Overené 25. 10. 2026: 180 testov (30 doména, 81 API, 3 HTTP klient, 3 úložisko, 63 Flutter), analyzer bez nálezov. Reálne webové demo: vytvorenie tiketu, automatická odpoveď, prevzatie operátorom, interná poznámka skrytá zákazníkovi, verejná odpoveď a sandbox refundácia 6,94 €. Regresný test opravuje vynechanie posledného dňa exportu pri prechode na zimný čas. Finančný worker strieda neúspešné úlohy, aby neblokovali neskoršie prevody. Oba weby, Android debug a iOS pre konkrétny simulátor zostavené. Aktivácia živých poskytovateľov a konkrétny ERP zostávajú závislé od účtov a voľby prevádzkovateľa.
