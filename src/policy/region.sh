#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

policy_region() {
    local requested=${REQUESTED_PROFILE:-auto} country evidence profile confidence reason
    case $requested in
      asia|asia-original|ASIA_ORIGINAL) policy_kv profile ASIA_ORIGINAL; policy_kv profile_confidence HIGH; policy_kv profile_reason USER_OVERRIDE_ASIA; policy_kv profile_evidence user_override; return;;
      overseas|overseas-original|OVERSEAS_ORIGINAL) policy_kv profile OVERSEAS_ORIGINAL; policy_kv profile_confidence HIGH; policy_kv profile_reason USER_OVERRIDE_OVERSEAS; policy_kv profile_evidence user_override; return;;
      global|global-mixed|GLOBAL_MIXED) policy_kv profile GLOBAL_MIXED; policy_kv profile_confidence HIGH; policy_kv profile_reason USER_OVERRIDE_GLOBAL_MIXED; policy_kv profile_evidence user_override; return;;
      system|system-default|SYSTEM_DEFAULT) policy_kv profile SYSTEM_DEFAULT; policy_kv profile_confidence HIGH; policy_kv profile_reason USER_OVERRIDE_SYSTEM_DEFAULT; policy_kv profile_evidence user_override; return;;
      compat|compat-original|COMPAT_ORIGINAL) policy_kv profile COMPAT_ORIGINAL; policy_kv profile_confidence HIGH; policy_kv profile_reason COMPATIBILITY_MODE; policy_kv profile_evidence compatibility; return;;
    esac
    country=$(policy_get evidence.server_country)
    case ${country,,} in
      cn|hk|jp|kr|sg|tw|asia|apac) profile=ASIA_ORIGINAL; confidence=MEDIUM; reason=LOCAL_ASIA_EVIDENCE; evidence=server_country;;
      us|ca|de|fr|gb|nl|eu|europe|overseas) profile=OVERSEAS_ORIGINAL; confidence=MEDIUM; reason=LOCAL_OVERSEAS_EVIDENCE; evidence=server_country;;
      *) profile=ASIA_ORIGINAL; confidence=LOW; reason=INSUFFICIENT_REGION_EVIDENCE; evidence=none;;
    esac
    policy_kv profile "$profile"; policy_kv profile_confidence "$confidence"; policy_kv profile_reason "$reason"; policy_kv profile_evidence "$evidence"
    policy_kv profile_evidence_missing "$([[ -n $country ]] && printf none || printf server_country,rtt_probe,asn_region)"
}
