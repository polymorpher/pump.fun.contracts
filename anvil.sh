#!/bin/zsh

export $(grep -v '^#' .env | xargs)

anvil -f https://a.api.s0.t.hmny.io/ --fork-block-number 66513894

#anvil -f https://mainnet.infura.io/v3/${INFURA_KEY} --fork-block-number 20488727