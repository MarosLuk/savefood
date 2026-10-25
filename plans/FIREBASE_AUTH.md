# Firebase Apple a Google

Zadanie: registrácia aj prihlásenie cez Apple a Google, Firebase projekt a jeho konfiguračné súbory dodá používateľ neskôr. Hosting aplikácie zostáva Hetzner. Zachovať existujúce e-mailové účty, objednávky a oprávnenia.

Zvolený postup: Flutter Firebase Auth, natívny google_sign_in pre Google a Firebase Apple provider; na webe Firebase popup. Spoločná inicializácia Firebase s existujúcim FCM. Dart API overí RS256 podpis, projekt/issuer/audience/čas a aktuálny stav Firebase účtu cez accounts:lookup, potom vydá bežnú odvolateľnú reláciu aplikácie. Firebase ID token sa neukladá. Identita je viazaná na projekt a UID; účty s rovnakým e-mailom sa automaticky nespájajú. Nový účet vyžaduje aktuálny súhlas. Chybný projekt, iný provider, zrušený token a deaktivovaný účet nesmú vytvoriť reláciu.

Alternatíva priameho OAuth je už implementovaná, ale nový požadovaný projekt bude používať Firebase. Presun všetkých dát do Firestore by zbytočne menil skladové transakcie a nie je súčasťou zadania. Rozhodujúce overenie: podpísané JWT a simulované oficiálne HTTP odpovede v testoch; naživo až po dodaní skutočného projektu.

- [x] Serverová konfigurácia, overenie JWT a stavu účtu, registrácia/prihlásenie a testy.
- [x] Flutter poskytovatelia, zrušenie/chyby, súhlas, odhlásenie a jednotná inicializácia.
- [x] Návod pre projekt, iOS/Android/web, konfiguračné vzory a zostavenia.
- [ ] Aktivácia a reálne prihlasovacie testy po dodaní projektu a Apple nastavení.
