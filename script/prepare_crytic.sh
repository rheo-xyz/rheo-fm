#!/usr/bin/env bash

set -ux

j=$((0x10))
BASE_SEARCH_DIRS=(
  src/market/libraries
  src/market/token/libraries
  src/factory/libraries
  test/helpers/libraries
)
LEGACY_SEARCH_DIRS=(
  lib/rheo-solidity/src/market/libraries
  lib/rheo-solidity/src/market/token/libraries
  lib/rheo-solidity/src/factory/libraries
)

BASE_EXISTING_DIRS=()
for d in "${BASE_SEARCH_DIRS[@]}"; do
    if [ -d "$d" ]; then
        BASE_EXISTING_DIRS+=("$d")
    fi
done

LEGACY_EXISTING_DIRS=()
for d in "${LEGACY_SEARCH_DIRS[@]}"; do
    if [ -d "$d" ]; then
        LEGACY_EXISTING_DIRS+=("$d")
    fi
done

if [ "${#BASE_EXISTING_DIRS[@]}" -eq 0 ]; then
    BASE_SOLIDITY_FILES=""
else
    BASE_SOLIDITY_FILES=$(find "${BASE_EXISTING_DIRS[@]}" -type f -name '*.sol' -printf '%f\n' | sed 's/\.sol$//' | sort -u)
fi

if [ "${#LEGACY_EXISTING_DIRS[@]}" -eq 0 ]; then
    LEGACY_SOLIDITY_FILES=""
else
    LEGACY_SOLIDITY_FILES=$(find "${LEGACY_EXISTING_DIRS[@]}" -type f -name '*.sol' -printf '%f\n' | sed 's/\.sol$//' | sort -u)
fi

if [ -n "$LEGACY_SOLIDITY_FILES" ] && [ -n "$BASE_SOLIDITY_FILES" ]; then
    # Keep local Rheo libraries authoritative and only import additional legacy libs.
    LEGACY_SOLIDITY_FILES=$(grep -vxF -f <(printf "%s\n" "$BASE_SOLIDITY_FILES") <(printf "%s\n" "$LEGACY_SOLIDITY_FILES") || true)
fi

SOLIDITY_FILES=$(printf "%s\n%s\n" "$BASE_SOLIDITY_FILES" "$LEGACY_SOLIDITY_FILES" | sed '/^$/d')
if [ -n "$SOLIDITY_FILES" ]; then
    SOLIDITY_FILES=$(printf "%s\n" "$SOLIDITY_FILES" | sort -u)
fi

rm COMPILE_LIBRARIES.txt || true
rm DEPLOY_CONTRACTS.txt || true
rm PREDEPLOYED_CONTRACTS.txt || true
: > COMPILE_LIBRARIES.txt
: > DEPLOY_CONTRACTS.txt
: > PREDEPLOYED_CONTRACTS.txt

while read -r i; do
    [ -z "$i" ] && continue
    echo "($i,$(printf "0x%x" $j))" >> COMPILE_LIBRARIES.txt
    echo "[$(printf "\"0x%x\"" $j), \"$i\"]" >> DEPLOY_CONTRACTS.txt
    echo "\"$i\": $(printf "\"0x%x\"" $j)" >> PREDEPLOYED_CONTRACTS.txt
    j=$((j+1))
done <<< "$SOLIDITY_FILES"

COMPILE_LIBRARIES=$(cat COMPILE_LIBRARIES.txt | paste -sd, -)
DEPLOY_CONTRACTS=$(cat DEPLOY_CONTRACTS.txt | paste -sd, -)
PREDEPLOYED_CONTRACTS=$(cat PREDEPLOYED_CONTRACTS.txt | paste -sd, -)

echo $COMPILE_LIBRARIES
echo $DEPLOY_CONTRACTS
echo $PREDEPLOYED_CONTRACTS

sed -i "s/cryticArgs.*/cryticArgs: [\"--compile-libraries=$COMPILE_LIBRARIES\",\"--foundry-compile-all\"]/" echidna.yaml
sed -i "s/\"args\".*/\"args\": [\"--compile-libraries=$COMPILE_LIBRARIES\",\"--foundry-compile-all\"]/" medusa.json
sed -i "s/deployContracts.*/deployContracts: [$DEPLOY_CONTRACTS]/g" echidna.yaml
sed -i "s/\"predeployedContracts\".*/\"predeployedContracts\": {$PREDEPLOYED_CONTRACTS},/g" medusa.json

# Foundry specific imports
sed -i "s|\"src/|\"./|" lib/ERC-7540-Reference/src/*.sol

rm COMPILE_LIBRARIES.txt || true
rm DEPLOY_CONTRACTS.txt || true
rm PREDEPLOYED_CONTRACTS.txt || true
