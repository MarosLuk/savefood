# Dokončenie prevádzkových tokov

Používateľ 25. 10. 2026 uprednostnil plnú implementáciu prevádzky; živé platby sa zapoja na konci.

Cieľ: inventúry a fyzické presuny medzi pobočkami, fotografické reklamácie, úplná história podpory, triedenie/priradenie a neprečítané udalosti s pripravenou push integráciou. Zachovať rezervácie, FEFO, oprávnenia a obe témy na webe aj mobile.

Známe: jeden SQLite proces, synchrónne transakcie, roly firma/vlastník/vedúci/pracovník, spoločné produkty, zásoby po šaržiach, existujúci FCM adaptér. Chýbajú účty poskytovateľov a konkrétny ERP; žiadne živé platby ani externé správy sa pri implementácii nevykonajú.

Možnosti skladových presunov: priamy presun by predstieral prijatie v cieli; zvolený trvalý stav koncept → na ceste → prijaté, prípadne potvrdený fyzický návrat. Odoslanie odpočíta iba voľné kusy; príjem zachová pôvodný termín a vyžaduje kontrolu kvality. Inventúra používa snapshot verzií, uložené počty a atómové schválenie vedúcim; zmenené šarže treba prepočítať. Najprv test invariantov rezervácií a zachovania množstva, potom UI.

Prílohy: súkromné JPEG/PNG nahratie s limitom, serverové overenie rozmerov a prekodovanie bez metadát, SQLite blob. Žiadne verejné URL; oprávnenie sa kontroluje aj pri každom načítaní fotografie. Interná poznámka skryje aj jej fotografie. Odpovede vytvárajú trvalé udalosti; čítanie potvrdzuje iba skutočne načítanú časť konverzácie. Push nesmie prezradiť text ani fotografiu reklamácie na zamknutej obrazovke.

- [x] Skladové schémy, inventúry, presuny a testy transakčných invariantov.
- [x] Webové/mobilné obrazovky inventúr a presunov s rolami a auditom.
- [x] Súkromné fotografické prílohy a úplné stránkovanie histórie.
- [x] Vyhľadávanie, priorita, priradenie a audit podpory.
- [x] Trvalé upozornenia, neprečítané počty, označenie prečítania a FCM fronta.
- [x] Naplnené demo, testy, zostavenia, snímky a aktuálne návody.

Preverenie: rezervácie sa nedajú presunúť ani odrátať inventúrou; výdaj počas počítania zneplatní snapshot; opakovanie príjmu/odoslania nezmení stav dvakrát; cudzia firma a rola nemôžu schváliť operáciu; príloha cudzieho tiketu a interná fotografia sa zákazníkovi nevydajú; nové udalosti sa neoznačia čítaním starého snapshotu; push z odhlásenej relácie sa neodošle.

Výsledky kontrol a obmedzenia: [overenie prevádzkových tokov](../docs/OVERENIE_PREVADZKY.md).
