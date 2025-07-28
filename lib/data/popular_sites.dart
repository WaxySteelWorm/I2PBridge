// lib/data/popular_sites.dart

class Site {
  final String name;
  final String url;
  final String description;

  Site({required this.name, required this.url, required this.description});
}

final List<Site> popularSites = [
  Site(
    name: 'NotBob',
    url: 'notbob.i2p',
    description: 'The xxxx',
  ),
  Site(
    name: 'I2P Forum',
    url: 'i2pforum.i2p',
    description: 'Community discussion forums for I2P.',
  ),
  Site(
    name: 'Shinobi',
    url: 'shinobi.i2p',
    description: 'The largest I2P Search Engine.',
  ),
  Site(
    name: 'Ramble',
    url: 'ramble.i2p',
    description: 'A popular I2P-based social media platform.',
  ),
    Site(
    name: 'Natter',
    url: 'natter.i2p',
    description: 'Twitter alternative on I2P.',
  ),
];
