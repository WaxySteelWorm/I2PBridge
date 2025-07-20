// lib/data/popular_sites.dart

class Site {
  final String name;
  final String url;
  final String description;

  Site({required this.name, required this.url, required this.description});
}

final List<Site> popularSites = [
  Site(
    name: 'I2P Project Homepage',
    url: 'i2p-projekt.i2p',
    description: 'The official homepage for the I2P project.',
  ),
  Site(
    name: 'I2P Forum',
    url: 'i2pforum.i2p',
    description: 'Community discussion forums for I2P.',
  ),
  Site(
    name: 'The Onion Router',
    url: 'torproject.org',
    description: 'The main website for the Tor Project.',
  ),
  Site(
    name: 'Ramble',
    url: 'ramble.i2p',
    description: 'A popular I2P-based social media platform.',
  ),
];
