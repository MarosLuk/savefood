# VISA, Apple Pay a Google Pay

Všetky tri možnosti spracuje jeden Stripe účet. VISA je kartová sieť; Apple Pay a Google Pay sú peňaženky nad uloženou kartou. Natívny Flutter klient používa **Stripe PaymentSheet 13.0.0**, web používa Stripe hosted Checkout. Pripnutá verzia je kompatibilná s Flutter 3.38.1; Stripe 14.2 vyžaduje novšie Flutter SDK.

## Aktivácia

1. Na serveri nastav `PAYMENT_MODE=stripe`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`. Pre natívne okno aj `STRIPE_PUBLISHABLE_KEY`. Tajný kľúč zostáva výhradne na serveri; verejný kľúč dostane aplikácia cez `/v1/config`. `MERCHANT_COUNTRY=SK`, mena aplikácie je EUR.
2. Použi zhodné `sk_test_` + `pk_test_` alebo `sk_live_` + `pk_live_` kľúče. Produkčný štart odmietne testovacie kľúče a pomiešané prostredia. Stripe testovací režim je označený v pokladni. Sandbox Stripe vôbec nevolá. Na ostré prijímanie platieb musí byť účet overený a aktivovaný.
3. V Stripe Dashboard nastav Cards a dostupné Apple Pay/Google Pay. Webová hosted pokladňa ponúkne peňaženku podľa zariadenia, nastavenia používateľa a účtu. Natívny klient používa systémové tlačidlá zo Stripe SDK; v aplikácii sú metódy uvedené informačne, ich skutočný výber je v platobnom okne.
4. Webhook `https://<api>/v1/payments/webhook` má prijímať `payment_intent.succeeded`, `payment_intent.canceled`, `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `customer.subscription.updated`, `customer.subscription.deleted`, `charge.refunded`, `charge.dispute.created`.

## Apple Pay v iOS

V Apple Developer vytvor vlastný Merchant ID. V Stripe Apple Pay nastaveniach pripoj aplikáciu a dokonči vytvorenie/pripojenie certifikátu. V Runner → Signing & Capabilities v Xcode zapni **Apple Pay**, vyber ten istý Merchant ID a obnov provisioning.

Rovnaký identifikátor nastav na serveri do `APPLE_PAY_MERCHANT_ID`. Kým chýba, natívne okno Apple Pay neaktivuje a ponechá kartu. Vzor podpisových oprávnení je v `apps/mobile/ios/Runner/ApplePay.entitlements.example`; buď nechaj Xcode upraviť existujúci `Runner.entitlements`, alebo nastav príslušný `CODE_SIGN_ENTITLEMENTS` a build setting `APPLE_PAY_MERCHANT_ID` pre pripravený vzor. Nevytvorený Merchant ID sa do podpisu nevkladá. Návrat `com.dakoty.savefood://stripe-redirect` je pripravený.

## Google Pay v Androide

Manifest zapína Google Pay API. Aktivita je `FlutterFragmentActivity`, témy sú AppCompat a release obsahuje pravidlá pre Stripe. Testovací/ostrý režim Google Pay sa odvodí zo Stripe prostredia. Pred distribúciou dokonči príslušné schválenie pre svoju aplikáciu v Google Pay & Wallet Console a distribučné podpisovanie. Peňaženku SDK ponúkne podľa podpory zariadenia a jeho nastavenia; karta zostáva dostupná.

## Platobná logika a overenie

Pri rezervácii mobil pošle `paymentFlow=native`. Server vytvorí jeden PaymentIntent so serverovou cenou a typom `card`, ktorý zahŕňa podporované karty aj kartové peňaženky. Web a staršie klienty vytvoria Checkout Session. Typ platby je uložený v objednávke a zachová sa spolu s idempotency key aj po výpadku a reštarte.

`POST /v1/orders/<id>/payment-sheet` je autorizovaný len pre vlastníka čakajúcej natívnej objednávky. Kontroluje sumu, menu a order metadata. Client secret je bez cache a neukladá sa do objednávky, histórie ani preferencií. Úspech, zatvorenie alebo prerušená odpoveď SDK sa preveria na serveri. Klient nemôže sám označiť objednávku za zaplatenú.

Po zatvorení okna možno tú istú rezerváciu znovu zaplatiť cez detail, s tým istým PaymentIntent. Natívnu rozpracovanú platbu dokončí mobilná aplikácia; web ju môže skontrolovať alebo zrušiť, ale nevytvára k nej druhú úhradu. Staré hosted objednávky ďalej otvárajú webovú pokladňu.

Číslo, platnosť a CVC sa zadávajú výhradne do Stripe UI. Aplikácia ich neukladá. Bankové overenie 3D Secure vybaví SDK/Checkout. Nezaplatená rezervácia po 30 minútach pri kontrole servera zruší aj možnosť platby pred uvoľnením skladu. Storno zaplatenej objednávky odošle idempotentnú refundáciu; pripísanie na kartu závisí od poskytovateľa a banky.

Pri EUR platbe a EUR vyrovnaní je minimálna externá úhrada 0,50 €. Ak kredit nepokryje celú sumu, použije sa z neho najviac suma, ktorá nechá platný doplatok; nevyužitý kredit zostane na účte. Pri plnom krytí kreditom sa SDK ani prehliadač neotvárajú. Pri inom vyrovnávacom účte over limity poskytovateľa.

Natívne zostavenia a kontrakty sú overované automaticky; **živá VISA/Apple Pay/Google Pay transakcia bez účtu a kľúčov prevádzkovateľa nebola vykonaná**.

Zdroje: [karty a VISA](https://docs.stripe.com/payments/cards), [Apple Pay](https://docs.stripe.com/apple-pay), [Google Pay](https://docs.stripe.com/google-pay), [Flutter PaymentSheet](https://docs.page/flutter-stripe/flutter_stripe/sheet), [limity mien](https://docs.stripe.com/currencies).

## Peniaze predajcov a reklamácie

Connect Accounts v2 onboarding, rozdelenie spoločného košíka, províziu, vyúčtovanie po výdaji, financovanie kreditu, reverzie a operátorské refundácie opisuje [Financie a zákaznícka podpora](FINANCIE_A_PODPORA.md). Zobrazený transfer je pripísanie na Stripe účet predajcu; banková výplata má samostatný harmonogram. Účtovný CSV je prevádzkový podklad bez automaticky určenej DPH.
