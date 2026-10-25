# Overenie nasadenia · 25. 10. 2026

Vydanie `20261025-https` je na `/home/marosko/save-food/releases/20261025-https`.
Používa API obraz `nevyhadzuj-api:hetzner-20261025` pre linux/amd64,
zostavený lokálne z aktuálneho projektu.

| Kontrola | Výsledok |
|---|---|
| Zákaznícky web `https://46.62.223.67:8452` | HTTP 200, Flutter onboarding a domov overené v prehliadači |
| API `https://46.62.223.67:8453/health/ready` | HTTP 200, `ready: true` |
| Predajca `https://46.62.223.67:8454` | HTTP 200, vlastný názov, manifest a zostavený klient |
| Administrácia `https://46.62.223.67:8455` | HTTP 200, vlastný názov, manifest a zostavený klient |
| TLS | Všetky porty prešli cez systémovú dôveru, bez `-k` či vypnutého overovania |
| Certifikát | Let's Encrypt YE1, SAN IPv4 `46.62.223.67`, platný do 1. 11. 2026 08:10:06 UTC |
| Obnova | Existujúci certifikát obnovuje pôvodný cron; nový hodinový cron synchronizuje iba vlastný TLS zväzok a reloaduje vlastný nginx |
| API v živých JS balíkoch | Všetky tri obsahujú `https://46.62.223.67:8453` |
| CORS | Tri vlastné originy a OPTIONS prešli; cudzí origin dostal 403 |
| Administrátorské API | Bez relácie HTTP 401 |
| Produkčný režim | Bez demo katalógu a demo účtov, platby vypnuté |
| Databáza | Nový samostatný zväzok, 0 ponúk |
| Zálohy | Online SQLite backup, integrita aj kontrolný súčet overené; denný cyklus, retencia 30 dní |
| Kontajnery | API, proxy aj backup `healthy` |
| Ostatné projekty | Všetkých 25 pôvodných kontajnerov zachovalo pôvodné ID |
| Flutter analyzer | Bez nálezov |
| HTTP integračné testy klientov | 3/3 prešli, vrátane spoločného skladu predajcu a zákazníka |
| Android | `artifacts/save-food-hetzner.apk`, debug podpis; skontrolovaná HTTPS adresa priamo v APK |
| iOS | Release `apps/mobile/build/ios/iphoneos/Runner.app` zostavený bez podpisu; HTTPS adresa skontrolovaná v binárke |

Priebežná spotreba troch nových kontajnerov bola približne 16 MiB RAM.
Obmedzenia pamäte: API 512 MiB, proxy 128 MiB, backup 128 MiB.

Reprodukcia vonkajších kontrol: `python3 tool/verify_hetzner.py`.
Strojový súhrn je v `artifacts/hetzner-verification.json`, snímka v
`artifacts/hetzner-live-web.png`.

E-mail, Firebase, sociálne prihlasovanie, push a ostré platby nemajú dodané
poverenia a nie sú aktivované. Produkčný katalóg, prevádzkovateľ, podmienky
a overený správca sa musia doplniť. Zálohy sú zatiaľ na rovnakom serveri.
Android nebol skúšaný na fyzickom telefóne; iOS balík vyžaduje podpis pred
inštaláciou na zariadenie. Do obchodov sa nič nepublikovalo.
