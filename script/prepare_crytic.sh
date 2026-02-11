#!/usr/bin/env bash

set -ux

j=$((0x10))
SEARCH_DIRS=(
  src/market/libraries
  src/market/token/libraries
  lib/rheo-solidity/src/market/libraries
  lib/rheo-solidity/src/market/token/libraries
  lib/rheo-solidity/src/factory/libraries
  test/helpers/libraries
)
EXISTING_DIRS=()
for d in "${SEARCH_DIRS[@]}"; do
    if [ -d "$d" ]; then
        EXISTING_DIRS+=("$d")
    fi
done

if [ "${#EXISTING_DIRS[@]}" -eq 0 ]; then
    SOLIDITY_FILES=""
else
    SOLIDITY_FILES=$(find "${EXISTING_DIRS[@]}" -type f -name '*.sol' -printf '%f\n' | sed 's/\.sol$//' | sort -u)
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
