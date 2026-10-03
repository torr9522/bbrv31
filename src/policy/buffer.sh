#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

policy_buffer() {
    local profile=$1 bw=$2 ram=$3 region=asia buffer=0
    [[ $profile == OVERSEAS_ORIGINAL ]] && region=overseas
    if ! [[ $bw =~ ^[0-9]+$ ]] || (( bw <= 0 )); then
      [[ $region == overseas ]] && buffer=64 || buffer=16
      policy_kv buffer_original_mb "$buffer"; policy_kv buffer_guard NONE; policy_kv buffer_effective_mb "$buffer"; policy_kv buffer_source original_invalid_fallback
      return
    fi
    if [[ $region == asia ]]; then
      case $bw in 100) buffer=6;;200) buffer=8;;300) buffer=10;;500) buffer=12;;700) buffer=14;;1000) buffer=16;;1500) buffer=20;;2000) buffer=24;;2500) buffer=28;;*) if ((bw<500)); then buffer=8; elif ((bw<1000)); then buffer=12; elif ((bw<2000)); then buffer=16; elif ((bw<5000)); then buffer=24; elif ((bw<10000)); then buffer=28; else buffer=32; fi;; esac
    else
      case $bw in 100) buffer=8;;200) buffer=16;;300) buffer=20;;500) buffer=32;;700) buffer=48;;1000|1500|2000|2500) buffer=64;;*) if ((bw<500)); then buffer=16; elif ((bw<1000)); then buffer=48; else buffer=64; fi;; esac
    fi
    local guard=NONE; (( ram < 2048 && buffer >= 64 )) && guard=REVIEW_LOW_MEMORY
    policy_kv buffer_original_mb "$buffer"; policy_kv buffer_guard "$guard"; policy_kv buffer_effective_mb "$buffer"; policy_kv buffer_source original_table
}
