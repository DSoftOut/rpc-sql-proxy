#!/bin/bash
set -ve

dub build --build=release
dub build --build=unittest

CONNINFO=`jq '.sqlServer.connString' ${1}`
CONNINFO_UNQUOTED=`echo $CONNINFO | xargs`

# Setup Postgres test scheme
psql -v ON_ERROR_STOP=ON -f .test_pgator_rpc_table.sql "$CONNINFO_UNQUOTED"

# Test calls table by preparing statements
`./pgator --config=${1} --debug=true --check=true > /dev/null; if [ $? -ne 2 ]; then exit 1; fi` # Some statements should be bad

# Start pgator server
./pgator --config=${1} --debug=true &
trap "kill %%" EXIT

# broken at ~Jan 2020 by unknown reason:
#ADDRESS=`jq '.listenAddresses[0]' ${1}`
#PORT=`jq '.listenPort' ${1}`
ADDRESS="127.0.0.1"
PORT=8080

ADDRESS_UNQUOTED=`echo $ADDRESS | xargs`

# Start test client
dub run pgator:test --build=unittest -- "$ADDRESS_UNQUOTED" "$PORT"
