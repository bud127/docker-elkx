#!/bin/bash
# This script must exit with:
# 0 on success
# 1 on error

# Abort if no healthcheck
[ "$NO_HEALTHCHECK" == "true" ] && exit 0

curl -f http://localhost:5601/ || exit 1
