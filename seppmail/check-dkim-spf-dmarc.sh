#!/usr/bin/env bash

# ------------------------------------------------------------
# Mail Auth Checker (SPF / DMARC / DKIM)
# - kompakte Ausgabe
# - keine Ausgaben für nicht existierende DKIM-Selectoren
# - folgt CNAME (z.B. Microsoft 365)
# ------------------------------------------------------------

command -v dig >/dev/null 2>&1 || {
  echo "ERROR: dig not installed"
  exit 1
}

read -rp "Domain: " DOMAIN
echo
echo "=================================================="
echo " Mail Auth Check: $DOMAIN"
echo "=================================================="

############################################
# SPF
############################################
echo
echo "[SPF]"
SPF=$(dig +short TXT "$DOMAIN" | tr -d '"')

SPF_MATCH=$(echo "$SPF" | grep -i "v=spf1")

if [[ -n "$SPF_MATCH" ]]; then
  echo "$SPF_MATCH"
else
  echo "NO SPF RECORD FOUND"
fi

############################################
# DMARC
############################################
echo
echo "[DMARC]"
DMARC=$(dig +short TXT "_dmarc.$DOMAIN" | tr -d '"')

if [[ -n "$DMARC" ]]; then
  echo "$DMARC" | tr ' ' '\n' | grep -E "v=|p=|rua=|ruf=|adkim=|aspf=|fo="

  POLICY=$(echo "$DMARC" | grep -o "p=[a-zA-Z]*" | cut -d= -f2)

  echo "----"
  if [[ "$POLICY" == "reject" ]]; then
    echo "Policy: STRICT (reject)"
  elif [[ "$POLICY" == "quarantine" ]]; then
    echo "Policy: MEDIUM (quarantine)"
  elif [[ "$POLICY" == "none" ]]; then
    echo "Policy: MONITOR (none)"
  else
    echo "Policy: UNKNOWN"
  fi
else
  echo "NO DMARC RECORD FOUND"
fi

############################################
# DKIM
############################################
echo
echo "[DKIM]"

SELECTORS=(
  "selector1"
  "selector2"
  "default"
  "google"
  "mail"
  "dkim"
  "s1"
  "s2"
)

for SEL in "${SELECTORS[@]}"; do
  HOST="${SEL}._domainkey.${DOMAIN}"

  CNAME=$(dig +short CNAME "$HOST")

  if [[ -n "$CNAME" ]]; then
    TXT=$(dig +short TXT "$CNAME" | tr -d '"')

    if [[ "$TXT" == *"v=DKIM1"* ]]; then
      echo "[$SEL]"
      echo "CNAME: $CNAME"
      echo "DKIM : ${TXT:0:90}..."
      echo
    fi

    continue
  fi

  TXT=$(dig +short TXT "$HOST" | tr -d '"')

  if [[ "$TXT" == *"v=DKIM1"* ]]; then
    echo "[$SEL]"
    echo "DKIM : ${TXT:0:90}..."
    echo
  fi
done

echo "=================================================="
echo "Done"
echo "=================================================="
