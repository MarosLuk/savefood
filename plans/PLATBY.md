# Platby kartou VISA, Apple Pay a Google Pay

Cieľ: jeden Stripe účet, karta a podporovaná peňaženka v natívnom Flutter platobnom okne; web zachová Stripe Checkout. Sklad, ceny, kredit, idempotencia, storno a potvrdenie objednávky zostávajú serverové. Bez dodaných poskytovateľských kľúčov sa nevykonáva živá transakcia.

Zvážené možnosti: (1) iba hosted Checkout, ktorý už podporuje karty a peňaženky, s minimálnou zmenou; (2) natívny Stripe PaymentSheet na iOS/Androide a hosted Checkout pre web. Volíme (2) pre použiteľnosť mobilnej aplikácie. Riziko: dva rozdielne platobné objekty môžu spôsobiť dvojité platby. Každá objednávka preto uloží nemenný paymentFlow, má jeden identifikátor platby, tvorbu s rovnakým idempotency key a potvrdenie iba po overení na serveri. Existujúce objednávky zostanú hosted.

Postup:
- [x] Overiť Flutter Stripe 13.0.0 a kompatibilitu so SDK projektu.
- [x] Natívny PaymentIntent: serverové ceny, opakovanie, zrušenie/refundácia, webhook a autorizovaný prístup ku client secret bez uloženia do modelu objednávky.
- [x] Flutter PaymentSheet, VISA a systémové peňaženky, 3DS návrat, opakovanie rozpracovanej platby a nulová úhrada kreditom.
- [x] Konfigurácia Android/iOS a návod na aktiváciu merchant účtov; žiadne tajné kľúče v klientovi.
- [x] Cielené kontraktové testy a obchodný tok; analyzer; web a natívne zostavenia.

Podklady: https://docs.stripe.com/payments/cards, https://docs.stripe.com/payments/mobile/accept-payment, https://docs.page/flutter-stripe/flutter_stripe/sheet, https://pub.dev/packages/flutter_stripe/versions/13.0.0.

Overenie kompatibility: 14.2.0 vyžaduje Flutter 3.41; projekt má 3.38.1. Použije sa pripnutá kompatibilná 13.0.0, bez upgradu celého Flutter SDK.
