#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/policy-tests
cc -std=c11 -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined \
    -I Sources/Policy/include Sources/Policy/Policy.c Tests/PolicyTests/policy_tests.c \
    -lm -o .build/policy-tests/policy-tests
.build/policy-tests/policy-tests
