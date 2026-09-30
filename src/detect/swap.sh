#!/usr/bin/env bash

detect_swap() {
    local lines='' count=0 kind=none total=0 devices=''
    if available swapon; then lines=$(swapon --show=NAME,TYPE,SIZE,PRIO --bytes --noheadings 2>/dev/null || true); fi
    if [[ -n $lines ]]; then
        count=$(wc -l <<<"$lines")
        while read -r name type size priority; do
            [[ -n $name ]] || continue
            total=$((total + size))
            [[ $name == /dev/zram* ]] && this=zram || [[ $type == partition ]] && this=partition || this=file
            [[ $kind == none ]] && kind=$this || [[ $kind != "$this" ]] && kind=multiple
            devices+="${devices:+,}${name}:${this}:${priority}"
        done <<<"$lines"
        (( count > 1 )) && kind=multiple
    fi
    kv swap.present "$( (( count > 0 )) && printf YES || printf NO )"
    kv swap.kind "$kind"
    kv swap.count "$count"
    kv swap.total_mib "$((total / 1024 / 1024))"
    kv swap.devices "$devices"
    kv swap.owned NO
}
