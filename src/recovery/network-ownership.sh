#!/usr/bin/env bash
set -euo pipefail
network_capture_ownership() { local d=$1; printf 'resource\towner\tmarker\nqdisc\tbbrv3-universal\ttransaction:%s\nrps\tbbrv3-universal\ttransaction:%s\nmss\tbbrv3-universal\ttransaction:%s\nroute\tbbrv3-universal\ttransaction:%s\n' "$(basename "$d")" "$(basename "$d")" "$(basename "$d")" "$(basename "$d")" >"$d/ownership.tsv"; }
