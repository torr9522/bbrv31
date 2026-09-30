#!/usr/bin/env bash

detect_qdisc() {
    local text='' json=NO iface kind='unknown' mq=NO fq=NO cake=NO htb=NO tbf=NO filters=NO classes=NO
    if ! available tc; then
        kv qdisc.tc MISSING; kv qdisc.root UNKNOWN; kv qdisc.policy BLOCKED; return
    fi
    text=$(tc -j qdisc show 2>/dev/null || true)
    if [[ $text == \[* ]]; then json=YES; else text=$(tc qdisc show 2>/dev/null || true); fi
    while read -r token; do
        case $token in
          mq) mq=YES;; fq) fq=YES;; cake) cake=YES;; htb) htb=YES;; tbf) tbf=YES;;
          pfifo_fast|pfifo|fq_codel|noqueue) [[ $kind == unknown ]] && kind=$token;;
        esac
    done < <(grep -oE '"kind"[[:space:]]*:[[:space:]]*"[^"]+"|qdisc[[:space:]]+[A-Za-z0-9_+-]+' <<<"$text" | sed -E 's/.*"kind"[[:space:]]*:[[:space:]]*"([^"]+)"/\1/; s/^qdisc[[:space:]]+//' | sort -u)
    grep -Eq 'filter|"filters"' <<<"$text" && filters=YES || true
    grep -Eq 'class|"classes"' <<<"$text" && classes=YES || true
    [[ $kind == unknown && $text =~ qdisc[[:space:]]+([^[:space:]]+) ]] && kind=${BASH_REMATCH[1]}
    [[ $kind == mq ]] && mq=YES
    kv qdisc.tc PRESENT
    kv qdisc.json "$json"
    kv qdisc.interface UNKNOWN
    kv qdisc.root "$kind"
    kv qdisc.root_handle UNKNOWN
    kv qdisc.parent ROOT
    kv qdisc.leaf_qdiscs "$kind"
    kv qdisc.mq_root "$mq"
    kv qdisc.fq_present "$fq"
    kv qdisc.cake_present "$cake"
    kv qdisc.htb_present "$htb"
    kv qdisc.tbf_present "$tbf"
    kv qdisc.filters "$filters"
    kv qdisc.classes "$classes"
}
