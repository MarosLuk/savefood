# Hetzner · dočasné HTTPS na IP

## Existujúci zdieľaný server

Nasadenie z 25. 10. 2026 používa `marosko@46.62.223.67`, adresár
`/home/marosko/save-food`, Compose projekt `nevyhadzuj` a
[konfiguráciu zdieľaného servera](../infra/hetzner/compose.yaml).

| Vstup | Živá adresa |
|---|---|
| Zákazník | <https://46.62.223.67:8452> |
| API | <https://46.62.223.67:8453> |
| Predajca | <https://46.62.223.67:8454> |
| Administrácia | <https://46.62.223.67:8455> |

Porty 80/443 používa Gardenyx a 8443 ďalší projekt. Vlastný nginx Save Food
používa voľné 8452–8455. Súkromná sieť, databáza, zálohy, pamäťové limity
a logy sú samostatné. API 8080 sa verejne nepublikuje.

Existujúci Certbot obnovuje IP certifikát `volkanditat-ip` v
`plants-be_certbot-certs`. Vlastný `sync-ip-tls.sh` ho každú hodinu skopíruje
do `nevyhadzuj_tls`, overí konfiguráciu a znovu načíta iba nginx Save Food.
Existujúci vydavateľ, cron obnovy a ostatné proxy sa nemenia. Prvá synchronizácia
prebehne pred spustením. IP certifikát sa overuje bežnou systémovou dôverou.

[Výsledky živého overenia](HETZNER_OVERENIE.md) · opakovateľný test:
`python3 tool/verify_hetzner.py`.

### Aktualizácia

Z koreňa projektu na Macu s Flutterom a Dockerom:

```sh
bash tool/deploy_hetzner.sh
```

Skript lokálne zostaví všetky tri weby aj linux/amd64 API obraz, prenesie
ich cez SSH kľúč `~/.ssh/hetzner_gateway`, zachová existujúci súkromný
`deploy/.env`, prepne vydanie a spustí iba vlastný Compose projekt.
Pri neúspešnom štarte sa vráti na predošlé vydanie a obraz. Neukončuje iné
kontajnery ani nečistí Docker cache. Existujúce vydania ostávajú v `releases/`.
Po zmene schémy treba pred návratom skontrolovať kompatibilitu databázy.

### Mobilné aplikácie

Predvolená adresa v `apps/mobile/lib/main.dart` a verejný
`config/hetzner.json` používajú `https://46.62.223.67:8453`. Rovnaký server
používa zákaznícky, predajcovský aj administrátorský vstup.

```sh
bash tool/build_hetzner_mobile.sh android # artifacts/save-food-hetzner.apk
bash tool/build_hetzner_mobile.sh ios     # release Runner.app bez podpisu
bash tool/build_hetzner_mobile.sh ipa     # vyžaduje Apple distribučný profil
```

APK je podpísané vývojovým Android kľúčom na priame testovanie.
Publikovanie do obchodov nie je súčasťou serverového nasadenia.
Staršie offline demo APK sa na server nepripojí; treba nainštalovať nový build.

### Dáta a prevádzka

Nasadenie používa produkčný režim, prázdnu novú databázu, bez demo účtov
a s vypnutými platbami. Registrácia heslom potrebuje `RESEND_API_KEY`
a `MAIL_FROM`; Apple/Google prihlasovanie vyžaduje samostatné Firebase
nastavenie. Existujúce projekty neposkytujú tieto poverenia Save Food.
Po ich nastavení reštartuj iba `api`. Údaje prevádzkovateľa, podmienky,
katalóg a overeného správcu treba doplniť pred verejným predajom.

Denná online SQLite záloha sa ukladá do `nevyhadzuj_backups`, kontroluje
integritu a má 30-dňovú retenciu. Je na rovnakom serveri; offsite úložisko
ešte nie je pripojené. Databáza je v `nevyhadzuj_marketplace`.

```sh
ssh -i ~/.ssh/hetzner_gateway marosko@46.62.223.67
cd ~/save-food/deploy
docker compose ps
docker compose logs --tail=50 api proxy backup
curl --fail https://46.62.223.67:8453/health/ready
bash sync-ip-tls.sh
```

## Šablóna pre samostatný nový server

Nasledujúci postup a `compose.hetzner.yaml` sú pre prázdny server s voľnými
80/443/8443/9443/10443. Na aktuálnom zdieľanom serveri používaj postup vyššie.

Potvrdené 25. 10. 2026: hosting Hetzner, zatiaľ bez domény, doklady za potraviny vystavuje predajňa. ERP/POS a účtovníctvo ešte nie sú vybrané; zostáva všeobecný konektor. Platby sa aktivujú na konci.

## Adresy a certifikát

Samostatné porty zachovávajú existujúce Flutter weby, základné cesty assetov a oddelené prehliadačové originy:

| Vstup | Adresa — nahraď PUBLIC_IPV4 pridelenou IPv4 |
|---|---|
| Zákazník | `https://PUBLIC_IPV4` |
| API | `https://PUBLIC_IPV4:8443` |
| Predajca | `https://PUBLIC_IPV4:9443` |
| Administrácia | `https://PUBLIC_IPV4:10443` |

Let’s Encrypt vydáva verejne dôveryhodné IP certifikáty s platnosťou 160 hodín cez ACME profil `shortlived`. Compose používa pripnutý Caddy 2.11.7; [Caddyfile.ip](../infra/Caddyfile.ip) explicitne nastavuje verejného ACME vystavovateľa, profil a `default_sni` pre klientov bez SNI za Docker NAT. Caddy certifikát získava a automaticky obnovuje, jeho `/data` aj `/config` sú trvalé zväzky. Kontrola certifikátu v aplikácii ostáva zapnutá.

IP musí byť verejne routovateľná a pridelená serveru. `203.0.113.10` je iba dokumentačný príklad; privátne IP ani localhost sa nepoužijú. Tento postup používa stabilnú verejnú IPv4; IPv6 treba nakonfigurovať a overiť samostatne.

Hetzner aj lokálny firewall musia povoľovať TCP 80, 443, 8443, 9443 a 10443. Porty 80/443 sú potrebné pre ACME overovanie a obnovu. UDP na HTTPS portoch umožní HTTP/3; bez neho funguje TCP HTTPS. SSH obmedz na správcovský zdroj. API port 8080, databáza a Caddy administračné API nemajú verejné mapovanie.

## Príprava

1. Skopíruj `.env.hetzner.example` do súkromného `.env.hetzner`, nastav `chmod 600 .env.hetzner`, nahraď všetky výskyty ilustračnej IP a doplň skutočný kontaktný `TLS_EMAIL`. Originy obsahujú porty, bez koncovej lomky. Poverenia neposielaj do chatu.
2. Aktivuj mailovú službu a overenú odosielaciu doménu. Web na IP nepotrebuje vlastnú doménu, ale tým nevzniká doména pre odosielanie e-mailov. Resend adaptér je pripravený, poskytovateľ ešte nie je vybraný. Bez nakonfigurovaného mailu nefunguje produkčná registrácia heslom. Overené Apple/Google identity používajú samostatný [Firebase tok](FIREBASE.md).
3. Na počítači s Flutter SDK zostav z koreňa projektu všetky tri weby pre pridelenú IP:

~~~sh
bash tool/build_hetzner_web.sh PUBLIC_IPV4
# Po dodaní projektu možno pridať config/app.web.json ako druhý argument.
~~~

Skript odmietne ilustračné a privátne IP. Výstupy `apps/mobile/build/hetzner-web`, `hetzner-merchant-web` a `hetzner-admin-web` neprepíšu lokálne demo. Mobilný klient potrebuje zostavu s `--dart-define=API_BASE_URL=https://PUBLIC_IPV4:8443`; offline demo APK nie je klient ostrého API.

4. Na Hetzner prenes projekt a tieto zostavené adresáre; server potrebuje Docker Engine a Compose plugin, Flutter SDK nemusí mať. Súkromnú konfiguráciu nastav na serveri. Potom:

~~~sh
docker compose --env-file .env.hetzner -f compose.hetzner.yaml config --quiet
docker compose --env-file .env.hetzner -f compose.hetzner.yaml up -d --build
docker compose --env-file .env.hetzner -f compose.hetzner.yaml ps
docker compose --env-file .env.hetzner -f compose.hetzner.yaml logs --tail=100 proxy
curl --fail https://PUBLIC_IPV4:8443/health/ready
~~~

`curl` používa systémové dôveryhodné certifikáty. Vydanie a obnovu certifikátu treba overiť na pridelenom serveri; lokálna validácia konfigurácie ich nepreukazuje. Zachovaj Caddy dátové zväzky pri aktualizácii a monitoruj dostupnosť a platnosť certifikátu zvonka. Denná záloha v Compose je lokálna; doplň nezávislé offsite úložisko a test obnovy podľa [PREVADZKA.md](PREVADZKA.md).

5. Po aktivácii mailu zaregistruj a over účet správcu, nastav jeho e-mail v `PLATFORM_ADMIN_EMAILS` a reštartuj API. V administrácii publikuj skutočné podmienky, identitu a schválené retenčné pravidlá. Každá predajňa vyplní vlastný fakturačný profil.

Compose vynucuje produkčný režim bez dema, `PAYMENT_MODE=disabled` a `BILLING_SELLER_MODEL=merchantSeller`. Sklad a katalóg možno pripravovať, platené objednávky nevzniknú cez sandbox.

## Doklady a neskorší prechod

Za potraviny vystavuje doklad právny subjekt predajne. Zmiešaný košík má oddelené predajné doklady. Opravný doklad zachová pôvodného vystavovateľa a daňové podiely. Poplatok platformy, ak sa účtuje, má samostatný doklad platformy.

Konfigurácia nastaví `merchantSeller` pri prázdnom nastavení a zablokuje prepnutie na platformového predávajúceho cez administráciu. Pri konflikte s existujúcou databázou server odmietne štart; pôvodný model neprepíše. Zmena vyžaduje schválenú migráciu.

Určenie vystavovateľa nenahrádza obchodné meno, adresu, IČO, DIČ/IČ DPH, sadzby, retenčné lehoty ani identitu prevádzkovateľa platformy. Tieto údaje ešte chýbajú. Účtovník musí pred aktiváciou platieb schváliť aj režim platieb vopred; aktuálny predajný doklad vzniká po výdaji.

Pri prechode na doménu zachovaj databázu aj zálohy, aktualizuj verejné URL, CORS, API adresy v klientoch a callbacky poskytovateľov. Použi doménovú šablónu `compose.production.yaml`. Zachovaj Compose projekt cez `-p nevyhadzuj`, aby nový súbor neotvoril iný dátový zväzok. Pri migrácii nepoužívaj `down --volumes`. Znovu over účty, médiá, doklady a TLS.

Zdroje: [Let’s Encrypt — IP a platnosť](https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability), [Caddy — ACME profil](https://caddyserver.com/docs/caddyfile/directives/tls), [Caddy — default_sni](https://caddyserver.com/docs/caddyfile/options#default-sni), [Caddy — IP certifikát za NAT](https://github.com/caddyserver/caddy/issues/7526).
