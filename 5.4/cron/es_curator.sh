#!/bin/sh
set -e

test -x /usr/local/bin/curator || exit 0
test -f /etc/elasticsearch/curator.yml || exit 0
test -f /etc/elasticsearch/curator_action.yml || exit 0
/usr/local/bin/curator --config /etc/elasticsearch/curator.yml /etc/elasticsearch/curator_action.yml
