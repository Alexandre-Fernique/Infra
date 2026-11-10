#!/usr/bin/env bash
# Génère la paire de clés qui signe les tokens du registry, et le JWKS que le
# registry (Distribution v3) utilise pour les vérifier.
#
# Pourquoi un JWKS ? docker_auth met dans ses tokens un "kid" au format libtrust
# (ex. ABCD:EFGH:...). Distribution v3 n'accepte plus ce format via
# rootcertbundle : on lui fournit donc la clé publique sous ce kid via un JWKS.
#
# Usage : ./gen-keys.sh          (ne régénère pas une clé existante)
#         ./gen-keys.sh --force  (rotation : invalide tous les tokens en cours)
set -euo pipefail
cd "$(dirname "$0")"
CERTS=auth/certs

if [[ "${1:-}" == "--force" || ! -f $CERTS/auth.key ]]; then
  mkdir -p $CERTS
  openssl req -x509 -newkey rsa:4096 -nodes -sha256 -days 3650 \
    -keyout $CERTS/auth.key -out $CERTS/auth.crt -subj "/CN=registry-token-issuer" 2>/dev/null
  chmod 600 $CERTS/auth.key
  echo "Nouvelle clé de signature générée."
fi

PUB_DER_B64=$(openssl x509 -in $CERTS/auth.crt -pubkey -noout | openssl pkey -pubin -outform DER | base64 | tr -d '\n')
MOD_HEX=$(openssl x509 -in $CERTS/auth.crt -noout -modulus | cut -d= -f2)

python3 -I - "$PUB_DER_B64" "$MOD_HEX" > config/jwks.json <<'EOF'
import base64, hashlib, json, sys
der = base64.b64decode(sys.argv[1])
mod = bytes.fromhex(sys.argv[2])
b64u = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
# kid libtrust : base32(sha256(DER)[:30]) découpé par blocs de 4
s = base64.b32encode(hashlib.sha256(der).digest()[:30]).decode().rstrip("=")
kid = ":".join(s[i:i + 4] for i in range(0, len(s), 4))
print(json.dumps({"keys": [{
    "kty": "RSA", "use": "sig", "alg": "RS256", "kid": kid,
    "n": b64u(mod), "e": b64u((65537).to_bytes(3, "big")),
}]}, indent=2))
EOF
echo "config/jwks.json écrit (kid=$(python3 -c 'import json;print(json.load(open("config/jwks.json"))["keys"][0]["kid"])'))."
echo "Pensez à redémarrer : docker compose restart"
