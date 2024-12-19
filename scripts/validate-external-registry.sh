#!/bin/bash


eval "$(jq -r '@sh "url=\(.url) password=\(.password) username=\(.username)"')"
valid=1
error_message="none"

if [ -n "$url" ]; then
#If URL is set

    #Then Username must be provided
    if [ -z "$username" ]; then
        valid 0
        error_message="Username is required"
        exit 1
    fi

   #Then Password must be provided
    if [ -z "$password" ]; then
        valid = 0
        error_message="Password is required"
        exit 1
    fi
fi

validity_encoded=$(echo ${valid} | base64 -w 0)
error_encoded=$(echo ${error_message} | base64 -w 0)

jq -n --arg validity_encoded "$validity_encoded" --arg error_encoded "$error_encoded" '{"validity_encoded":$validity_encoded, "error_encoded":$error_encoded}'


