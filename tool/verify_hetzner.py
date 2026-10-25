#!/usr/bin/env python3
"""Read-only deployment smoke checks using normal system TLS validation."""
import json
import ssl
import urllib.error
import urllib.request

HOST = '46.62.223.67'
API = f'https://{HOST}:8453'
CONTEXT = ssl.create_default_context()


def request(url, method='GET', headers=None, expected=200):
    req = urllib.request.Request(url, method=method, headers=headers or {})
    try:
        response = urllib.request.urlopen(req, context=CONTEXT, timeout=30)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.status == expected, (url, response.status, body[:200])
        return body, response.headers


def main():
    ready, _ = request(f'{API}/health/ready')
    assert json.loads(ready)['ready'] is True
    config, _ = request(f'{API}/v1/config')
    config = json.loads(config)
    assert config['paymentMode'] == 'disabled'
    assert config['paymentsEnabled'] is False
    assert config['demoCatalog'] is False
    assert config['demoShowcase'] is False
    catalog, _ = request(f'{API}/v1/catalog')
    assert isinstance(json.loads(catalog)['offers'], list)
    for port, title in [(8452, 'Save Food'), (8454, 'Save Food Predajca'),
                        (8455, 'Save Food Administrácia')]:
        origin = f'https://{HOST}:{port}'
        page, headers = request(origin)
        assert f'<title>{title}</title>' in page.decode()
        assert 'no-cache' in headers['Cache-Control']
        js, _ = request(f'{origin}/main.dart.js')
        assert API.encode() in js, (port, 'Incorrect API in deployed bundle')
        manifest, _ = request(f'{origin}/manifest.json')
        assert json.loads(manifest)['name'] == title
        _, headers = request(f'{API}/v1/catalog', headers={'Origin': origin})
        assert headers['Access-Control-Allow-Origin'] == origin
        _, headers = request(f'{API}/v1/auth/login', 'OPTIONS', {
            'Origin': origin,
            'Access-Control-Request-Method': 'POST',
            'Access-Control-Request-Headers': 'Content-Type,Authorization',
        }, expected=204)
        assert headers['Access-Control-Allow-Origin'] == origin
    request(f'{API}/v1/catalog', headers={'Origin': 'https://untrusted.invalid'},
            expected=403)
    request(f'{API}/v1/platform/readiness', expected=401)
    print(json.dumps({
        'https': 'verified on all four ports without TLS exceptions',
        'webs': ['customer', 'merchant', 'admin'],
        'api': API,
        'cors': 'all three allowed origins; untrusted origin rejected',
        'admin': 'requires authentication',
        'demo': False,
        'payments': config['paymentMode'],
        'emailConfigured': config['emailEnabled'],
        'pushConfigured': config['pushEnabled'],
        'offers': len(json.loads(catalog)['offers']),
    }, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
