/// Bundled illustrative photography, available offline in customer and seller UI.
const demoImageNames = {
  'bakery',
  'bread',
  'cafe',
  'coffee',
  'dessert',
  'flowers',
  'meal',
  'salad',
  'toast',
  'vegetables',
};

class DemoPersona {
  const DemoPersona(
    this.id,
    this.title,
    this.description,
    this.image, {
    this.merchant = true,
  });
  final String id, title, description, image;
  final bool merchant;
}

const demoPersonas = [
  DemoPersona(
    'customer',
    'Sofia · zákazníčka',
    'Obľúbené miesta, kredit, Klub a pripravené objednávky.',
    'salad',
    merchant: false,
  ),
  DemoPersona(
    'bakery',
    'Pekáreň Maslo',
    'Dve pobočky, voňavé pečivo a balíčky na schválenie.',
    'bakery',
  ),
  DemoPersona(
    'restaurant',
    'Bistro Záhrada',
    'Denné menu, chladený sklad a jednoduchý výdaj.',
    'meal',
  ),
  DemoPersona(
    'grocery',
    'Dobrý obchod',
    'Potraviny, šarže, kontrola kvality a automatizácia.',
    'vegetables',
  ),
  DemoPersona(
    'support',
    'Nina · zákaznícka podpora',
    'Prijaté požiadavky, reklamácie, odpovede a refundácie.',
    'cafe',
    merchant: false,
  ),
];

/// Only the illustrative bundled gallery gets related images. A merchant's own
/// photo is shown on its own; unrelated stock imagery is never added to it.
List<String> offerGallery(String image) => switch (image) {
  'bakery' || 'bread' => {image, 'bakery', 'bread'}.toList(),
  'meal' || 'salad' => {image, 'meal', 'salad'}.toList(),
  'dessert' || 'toast' => {image, 'dessert', 'toast'}.toList(),
  'coffee' || 'cafe' => {image, 'coffee', 'cafe'}.toList(),
  _ => [image],
};
