#!/bin/zsh

export $(grep -v '^#' .env | xargs)
forge script script/Power.s.sol --rpc-url http://127.0.0.1:8545 \
  -vv

