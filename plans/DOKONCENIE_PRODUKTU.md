# Dokončenie produktu

Zadanie 25. 10. 2026: dôkladne analyzovať a implementovať každý bod posledného zoznamu. Platobné zapojenie ostáva na záver. Žiadne fiktívne údaje prevádzkovateľa ani tvrdenia o aktívnej externej službe.

## Prístup

Zachovať Flutter monorepo, API a modrý svetlý/tmavý dizajn. Rozširovať samostatnými serverovými modulmi a klientskymi obrazovkami; najprv invarianty a oprávnenia, potom UI. Alternatíva kompletného prepisu backendu by ohrozila už otestované rezervácie a financie; minimálne formulárové doplnenia by nepokryli bezpečné účty ani veľké sklady. Zvolená priebežná migrácia s kompatibilnými schémami, transakciami a testami. Záťažové výsledky rozhodnú o potrebe PostgreSQL, nie predpoklad.

Najväčšie riziká: tokeny obnovy účtu a odvolanie relácií, presné rozdelenie sumy čiastočných refundácií, izolácia údajov pobočiek, zápis vážených zásob bez desatinných chýb, cudzie obrázky a osobné údaje, nemenné vystavené doklady. Externé systémy a daňový režim nie sú určené; otázky sú položené, nezávislé práce pokračujú.

## Matica dokončenia

- [x] Účty: jednorazová obnova hesla, zmena hesla/e-mailu, overenie e-mailu, revokácia relácií, export a vymazanie/anonymizácia účtu, UI a bezpečnostné testy.
- [x] E-mail: trvalá fronta, poskytovateľský adaptér, bezpečné testovacie doručenie, opakovanie, šablóny a nastavenia.
- [x] Médiá predajcov: priamy výber/fotoaparát, sanitizácia, vlastníctvo a správa fotografií, bezpečné verejné varianty ponúk a testy.
- [x] Veľké sklady: serverové stránkovanie a vyhľadávanie, klientské priebežné načítanie, práva pobočiek, pozvánky, presné vážené jednotky, integračný konektor so spätným výdajom a zosúladením.
- [x] Recenzie: štyri dimenzie, vlastné fotografie po overenom výdaji, verejné zobrazenie a moderácia.
- [x] Administrácia: samostatný webový vstup, roly správcu, používatelia, firmy, prevádzky, podpora, ponuky/recenzie a audit; žiadny admin secret v klientovi.
- [x] Účtovníctvo: nemenné doklady/číslovanie, konfigurovaná identita a daňový režim, export/adaptér, refundácie jednotlivých kusov a rozdelenie súm bez zaokrúhľovacích strát.
- [ ] Prevádzka: konfigurované OAuth/FCM/e-maily, HTTPS/domain infra šablóny, zálohy/obnova, monitoring, zdravotné kontroly, kontrola produkčnej konfigurácie.
- [ ] Distribúcia: release konfigurácie a CI, Android/iOS podpisové postupy, testy fyzických zariadení a obchodové podklady podľa dostupných účtov.
- [ ] Podmienky/súkromie: konfigurovaná identita, spracovatelia, uchovávanie, verzované súhlasy, bez vymyslených prevádzkových údajov.
- [x] Záťažové, bezpečnostné a UI testy, nové demo, screenshoty, zostavenia a aktualizovaný stav.

## Hranice externých krokov

Upresnenie používateľa: hosting Hetzner, dočasne HTTPS na verejnej IP bez domény; doklady za potraviny vystavuje predajňa. ERP/POS ani účtovníctvo zatiaľ nie sú vybrané. Zvolená príprava používa samostatné HTTPS porty pre tri existujúce weby a API, aby nebolo potrebné meniť základné cesty Flutter assetov. Caddy 2.11.7 bude pre IP explicitne používať verejné ACME s profilom shortlived a default_sni pre kontajnerový NAT. Konfigurácia sa overí bez žiadosti o certifikát; verejné vydanie a obnova sa overia až s pridelenou IP a serverom. Fakturačný model merchantSeller sa pripne konfiguráciou a nesmie potichu prepnúť existujúcu databázu na iného predávajúceho.

Výber ERP/POS, účtovníctva, hostingu, domény, e-mailového poskytovateľa a údaje prevádzkovateľa boli vyžiadané. Bez nich sa pripravuje konkrétne testovateľné rozhranie a lokálne integračné prostredie; živá integrácia sa nebude označovať za hotovú. Reálne finančné transakcie a prijatie záväzných podmienok za používateľa sa nevykonajú. Aktivácia platieb sa vykoná až v záverečnej etape.

## Výsledok tejto etapy

Funkčný kód, testy a lokálne zostavenia sú dokončené v rozsahu uvedenom v [docs/DOKONCENIE.md](../docs/DOKONCENIE.md). Externé aktivácie ostávajú otvorené: konkrétny ERP/POS a účtovníctvo, nasadenie na potvrdený Hetzner/IP a neskôr doména, mail/OAuth/FCM, právne a účtovné údaje, distribučné podpisy a fyzické zariadenia. Generický konektor je otestovaný; partnerov neurčený systém sa nepovažuje za pripojený. Platby ostávajú na koniec.
