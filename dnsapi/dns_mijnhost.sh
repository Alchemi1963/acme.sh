#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_myapi_info='mijn.host
 A mijn.host API script
Site: mijn.host/api/doc
Docs: github.com/slchemi1963/acme.sh/wiki/dnsapi#dns_mijnhost
Options:
 mijnhost_apikey Your mijn.host API key
Issues: github.com/slchemi1963/acme.sh
Author: Melody Smit <linux@personaltardis.me>
'

#_post body url [needbase64] [post|put|delete] [contenttype]
#_get url getheader timeout
#Note: Wildcard certificates require two TXT values. When implementing the method make sure that you append the value instead of replacing it

mijnhost_api="https://mijn.host/api/v2"

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_mijnhost_add() {
    fulldomain=$1
    txtvalue=$2

    mijnhost_apikey="${mijnhost_apikey:-$(_readaccountconf_mutable mijnhost_apikey)}"
    if [ -z "$mijnhost_apikey" ]; then
        mijnhost_apikey=""
        _err "You didn't specify your mijn.host API key yet."
        _err "Please request the API key and try again."
        _err "Visit https://mijn.host/api/doc/ for more information."
        return 1
    fi

    #save api key to the account conf file
    _saveaccountconf_mutable mijnhost_apikey "$mijnhost_apikey"

    _debug "First detect the root zone"
    if ! _get_root "$fulldomain"; then
        _err "Invalid domain"
        return 1
    fi

    _debug _sub_domain "$_sub_domain"
    _debug _domain "$_domain"

    if [ -z "$_sub_domain" ] || [ -z "$_domain" ]; then
        _err "Invalid domain"
        _err "$_sub_domain.$_domain"
        return 1
    fi

    _info "Adding record"
    if _mijnhost_put_record "$_domain" "$_sub_domain" "$txtvalue"; then
        _info "Added, OK"
        return 0
    fi

    _err "Add txt record error"
    return 1
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_mijnhost_rm() {
    fulldomain=$1
    txtvalue=$2

    mijnhost_apikey="${mijnhost_apikey:-$(_readaccountconf_mutable mijnhost_apikey)}"
    if [ -z "$mijnhost_apikey" ]; then
        mijnhost_apikey=""
        _err "You didn't specify your mijn.host API key yet."
        _err "Please request the API key and try again."
        _err "Visit https://mijn.host/api/doc/ for more information."
        return 1
    fi

    _debug "First detect the root zone"
    if ! _get_root "$fulldomain"; then
        _err "Invalid domain"
        return 1
    fi

    _debug _sub_domain "$_sub_domain"
    _debug _domain "$_domain"

    if [ -z "$_sub_domain" ] || [ -z "$_domain" ]; then
        _err "Invalid domain"
        _err "$_sub_domain.$_domain"
        return 1
    fi

    _info "Removing record"
    if _mijnhost_del_record "$_domain" "$_sub_domain"; then
        _info "Removed, OK"
        return 0
    fi

    _err "Remove txt record error"
    return 1
}

####################  Private functions below ##################################

# usage: _acme-challenge.www.domain.com
# returns
#  _sub_domain=_acme-challenge.www
#  _domain=domain.com
_get_root() {
    domain=$1
    _mijnhost_domains

    i=1

    while true; do
        sub="$(printf "%s" "$domain" | cut -d . -f "$i"-100)" # split $domain by . and display fields $i until 100 (i increases until match is found)
        _debug sub "$sub"

        if [ -z "$sub" ]; then # if $sub is empty
            _err "Invalid domain: $domain"
            return 1
        elif [[ "$domains" =~ "$sub" ]]; then # if $sub is in $domains
            _domain="$sub"
            _sub_domain="$(printf "%s" "$domain" | cut -d . -f 1-"$(_math "$i" - 1)")"
            return 0
        else
            i=$(_math "$i" + 1)
        fi
    done
    _err "Root domain not found."
    return 1
}

# Usage: GET|PUT request data
_mijnhost_rest(){
    method=$1
    request=$2
    data=$3
    _debug request "$request"


    export _H1="Accept: application/json"
    export _H2="API-Key: $mijnhost_apikey"

    if [ "$method" == "GET" ]; then
        response="$(_get "$mijnhost_api/$request")"
    elif [ "$method" == "PUT" ]; then
        _debug data "$data"
        response="$(_post "$data" "$mijnhost_api/$request" "" "PUT" "application/json")"
        _err $response
    else
        _err "Invalid method: $method"
        return 1
    fi
    _debug response "$response"

    if [ $(echo $response | jq '.status') != 200 ]; then
        return 1
    fi

    return 0
}

# returns
#  domains
_mijnhost_domains(){
    if ! _mijnhost_rest "GET" "domains/"; then
        return 1
    fi

    domains="$(echo $response | jq '.data.domains.[] | .domain')"
    return 0
}

# Usage: domain
# returns
#  records
_mijnhost_get_records(){
    domain=$1

    if ! _mijnhost_rest "GET" "domains/$domain/dns"; then
        return 1
    fi

    records="$(echo $response | jq '.data.records')"
    return 0
}

# Usage: domain subdomain value
_mijnhost_put_record(){
    domain=$1
    sub_domain=$2
    value=$3
    if ! _mijnhost_get_records "$domain"; then
        return 1
    fi

    new_records="$(echo $records | jq --arg value "$value" --arg fulldomain "$_sub_domain.$domain." '. + [{"type":"TXT","name":$fulldomain,"value":$value,"ttl":900}]')" ## ADD TO RECORDS
    if ! _mijnhost_rest "PUT" "domains/$domain/dns" "{\"records\":$new_records}"; then
        return 1
    fi
    return 0
}

# Usage: domain subdomain
_mijnhost_del_record() {
    domain=$1
    sub_domain=$2
    if ! _mijnhost_get_records "$domain"; then
        return 1
    fi

    new_records="$(echo $records | jq --arg fulldomain "$_sub_domain.$domain." ' map(select(.name != $fulldomain))')" ## REMOVE FROM RECORDS BY NAME THIS REMOVES ALL
    if ! _mijnhost_rest "PUT" "domains/$domain/dns" "{\"records\":$new_records}"; then
        return 1
    fi
    return 0
}
