#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

policy_buffer() {
    local profile=$1 bw=$2 ram=$3 region=asia buffer=0
    [[ $profile == OVERSEAS_ORIGINAL ]] && region=overseas
    if [[ $region == asia ]]; then
      case $bw in 100) buffer=6;;200) buffer=8;;300) buffer=10;;500) buffer=12;;700) buffer=14;;1000) buffer=16;;1500) buffer=20;;2000) buffer=24;;2500) buffer=28;;*) ((bw<500))&&buffer=8||((bw<1000))&&buffer=12||((bw<2000))&&buffer=16||((bw<5000))&&buffer=24||((bw<10000))&&buffer=28||buffer=32;; esac
    else
      case $bw in 100) buffer=8;;200) buffer=16;;300) buffer=20;;500) buffer=32;;700) buffer=48;;1000|1500|2000|2500) buffer=64;;*) ((bw<500))&&buffer=16||((bw<1000))&&buffer=48||buffer=64;; esac
    fi
    local guard=NONE; (( ram < 2048 && buffer >= 64 )) && guard=REVIEW_LOW_MEMORY
    policy_kv buffer_original_mb "$buffer"; policy_kv buffer_guard "$guard"; policy_kv buffer_effective_mb "$buffer"; policy_kv buffer_source original_table
}
