# Nasadenie Save Food · 25. 10. 2026

Cieľ: nasadiť web, predajcu, administráciu a API na existujúci Hetzner
`46.62.223.67`; Android aj iOS používajú to isté API cez dôveryhodné HTTPS.

Server je zdieľaný. Porty 80, 443 a 8443 sú obsadené, má 12 GB voľného
disku a približne 4,5 GB dostupnej pamäte. Existujúci IP certifikát Let's
Encrypt je platný a obnovuje ho nezávislý existujúci cron.

Možnosti: samostatný Caddy by kolidoval s 80/443; úprava spoločného nginx
by zasahovala do Gardenyxu. Zvolený postup používa vlastný nginx na
8452–8455, vlastný Compose projekt a kópiu existujúceho IP certifikátu
vo vlastnom TLS zväzku. Obrazy sa zostavia lokálne pre amd64, aby na
serveri nevznikala ďalšia veľká build cache. Databáza aj zálohy sú nové
samostatné zväzky. Existujúce projekty a ich obnovovanie sa nemenia.

- [x] Overiť SSH, server, porty, certifikát a kapacitu.
- [x] Upraviť predvolené API a pripraviť zdieľanú produkčnú konfiguráciu.
- [x] Zostaviť tri weby, API pre amd64 a mobilné balíky (Android APK, nepodpísaný iOS release).
- [x] Nasadiť API, nginx, zálohy a synchronizáciu obnoveného certifikátu.
- [x] Overiť HTTPS bez výnimiek, CORS, API, weby, zálohu a pôvodné kontajnery.
- [x] Zapísať adresy, postup aktualizácie a obmedzenia integrácií.

Pri neplatnom certifikáte alebo konflikte portov sa nasadenie zastaví.
Produkcia má prázdny katalóg, zakázané platby a žiadne demo identity;
e-mail a Firebase potrebujú vlastnú konfiguráciu poskytovateľa.

Výsledok: všetky tri kontajnery sú zdravé. Prvé nasadenie odhalilo správanie
Compose v5 pri obraze s vypnutým healthcheckom; zálohovací kontajner preto
kontroluje čerstvosť overenej zálohy vlastným healthcheckom. Kontrola
zdieľaného certifikátu, jeho kopírovanie a načítanie v nginx prešli.
Pôvodných 25 kontajnerov má rovnaké ID. Súhrn je v
`docs/HETZNER_OVERENIE.md`.
