#!/bin/zsh

export $(grep -v '^#' .env | xargs)
forge test -vv --match-test test_publishToUniswap -f http://127.0.0.1:8545