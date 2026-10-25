# Motion návrhy

## Platba → objednávky

Schválený vizuálny smer z 25. 10. 2026: spoločná karta balíčka sa zdvihne z košíka, rozloží na vrstvy, preklopí do platobnej karty, prejde cez rotujúce orbity a po potvrdení dosadne do objednávok. Nasleduje otvorenie kódu vyzdvihnutia.

- [Prehrateľná ukážka](payment-motion.html) je samostatný HTML súbor. Otvor ho v prehliadači a stlač **Prehrať motion návrh**. Po dokončení možno otvoriť kód a prehrávať znovu.
- [Editovateľný zdroj](payment-motion.source.html) je fragment pre náhľad v konverzácii. Obsahuje rovnakú choreografiu.
- [Mapa celej aplikácie](../MAPA_POHYBU.md) rozlišuje existujúci stav, návrhy a poradie implementácie vo Flutteri.

Ukážka simuluje priebeh platby a lokálny stav prezentácie. Nevytvára objednávky v aplikácii a nevolá platobné služby. Natívny tok `DemoPaymentScreen` má vlastné ukladanie objednávky; schválenú 3D choreografiu doň treba preniesť podľa mapy.

Zdroj obsahuje fotografiu a GSAP 3.15.0 vrátane pôvodnej licenčnej hlavičky. Samostatný export pridáva prezentačný obal, ikony a štýly; tieto prostriedky môžu vyžadovať pripojenie. Aplikačná ukážka nepoužíva `fetch`, XHR ani WebSocket. Uloženie stavu náhľadu je voliteľné a jeho chyba neblokuje prehrávanie.

Overené: prvé aj opakované prehrávanie, prechod na kód a späť, obnovenie uloženého stavu, šírka 320 px, režim obmedzeného pohybu a konzola bez chýb. Tieto kontroly sa týkajú návrhu v prehliadači.
