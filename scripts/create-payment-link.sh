#!/usr/bin/env bash
# Create the "buy me a coffee" Stripe Payment Link.
#
#   bash scripts/create-payment-link.sh            # dry run: show the account, change nothing
#   bash scripts/create-payment-link.sh --live     # actually create it, in live mode
#
# Needs `stripe login` first. This touches a real payments account, so the
# default is a dry run and live mode has to be asked for by name.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIVE=false
[ "${1:-}" = "--live" ] && LIVE=true
MODE_FLAG=""
$LIVE && MODE_FLAG="--live"

# The CLI prints a "▸ Running in ..." banner ahead of the JSON body.
json_only() { sed -n '/^[[:space:]]*{/,$p'; }

command -v stripe >/dev/null || { echo "Stripe CLI not installed: brew install stripe/stripe-cli/stripe"; exit 1; }

echo "==> Which account are we on?"
# Reading the account is harmless in either mode, and the CLI refuses a bare
# read while the context is live - so always ask for live here.
ACCOUNT="$(stripe get /v1/account --live 2>&1 | json_only)" || true
if [ -z "$ACCOUNT" ]; then
  stripe get /v1/account --live 2>&1 | tail -5
  echo
  echo "Not authenticated. Run: stripe login"
  exit 1
fi
echo "$ACCOUNT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
p = d.get('business_profile') or {}
for label, value in (('account', d.get('id')),
                     ('business', p.get('name')),
                     ('email', d.get('email')),
                     ('country', d.get('country')),
                     ('default currency', d.get('default_currency')),
                     ('charges enabled', d.get('charges_enabled')),
                     ('payouts enabled', d.get('payouts_enabled'))):
    if value is not None:
        print('    %-17s %s' % (label, value))
"

if ! $LIVE; then
  echo
  echo "Dry run. Nothing was created."
  echo "If that's the right account, re-run with --live."
  exit 0
fi

echo
echo "==> Creating product"
PRODUCT="$(stripe products create --live \
  --name="Buy me a coffee" \
  --description="A tip for WaterBar, the menu bar app that counts the water Claude Code drinks." \
  | json_only | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')"
echo "    $PRODUCT"

# custom_unit_amount is Stripe's pay-what-you-want. No currency_options on
# purpose: Payment Links always run Adaptive Pricing, which presents the
# buyer's local currency automatically - but it skips any currency that's
# already pinned in currency_options. Listing them would switch that off.
echo "==> Creating price (pay what you want, minimum USD 5)"
PRICE="$(stripe prices create --live \
  --product="$PRODUCT" \
  --currency=usd \
  -d "custom_unit_amount[enabled]=true" \
  -d "custom_unit_amount[minimum]=500" \
  -d "custom_unit_amount[preset]=500" \
  | json_only | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')"
echo "    $PRICE"

echo "==> Creating payment link"
LINK_JSON="$(stripe payment_links create --live \
  -d "line_items[0][price]=$PRICE" \
  -d "line_items[0][quantity]=1" \
  -d "submit_type=donate" \
  -d "after_completion[type]=hosted_confirmation" \
  -d "after_completion[hosted_confirmation][custom_message]=Thank you. That is roughly 140 litres of water you have just sponsored." | json_only)"
URL="$(echo "$LINK_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["url"])')"

echo
echo "    $URL"
echo
read -r -p "Write this into SupportLink.swift and rebuild? [y/N] " reply
if [ "$reply" = "y" ] || [ "$reply" = "Y" ]; then
  sed -i '' "s|static let builtIn = \".*\"|static let builtIn = \"$URL\"|" \
    "$ROOT/WaterBar/Sources/WaterBar/Engine/SupportLink.swift"
  bash "$ROOT/WaterBar/build.sh"
  echo "Done. Reinstall with: cp -R WaterBar/WaterBar.app /Applications/"
else
  echo "Left the app alone. The URL is above when you want it."
fi
