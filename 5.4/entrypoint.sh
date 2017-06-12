#!/bin/bash
#
# /usr/local/bin/entrypoint.sh
# Start Elasticsearch, Logstash and Kibana services

#==============================================
# Environment
#==============================================
ES_DEFAULT_PASSWD=changeme
KB_DEFAULT_PASSWD=changeme
LS_DEFAULT_PASSWD=changeme
export ES_PASSWORD=${ES_PASSWORD:-$ES_DEFAULT_PASSWD}
export KB_PASSWORD=${KB_PASSWORD:-$KB_DEFAULT_PASSWD}
export LS_PASSWORD=${LS_PASSWORD:-$LS_DEFAULT_PASSWD}

#==============================================
# Handle state
#==============================================
## handle termination gracefully
_term() {
  echo "Terminating ELK"
  service elasticsearch stop
  service logstash stop
  service kibana stop
  exit 0
}

trap _term SIGTERM

## remove pidfiles in case previous graceful termination failed
# NOTE - This is the reason for the WARNING at the top - it's a bit hackish,
#   but if it's good enough for Fedora (https://goo.gl/88eyXJ), it's good
#   enough for me :)

rm -f /var/run/elasticsearch/elasticsearch.pid /var/run/logstash.pid \
  /var/run/kibana5.pid

## initialise list of log files to stream in console (initially empty)
OUTPUT_LOGFILES=""

## override default time zone (Etc/UTC) if TZ variable is set
if [ ! -z "$TZ" ]; then
  ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
fi

#==============================================
# Start Cron
#==============================================
service cron start

#==============================================
# Start Elasticsearch
#==============================================
if [ -z "$ELASTICSEARCH_START" ]; then
  ELASTICSEARCH_START=1
fi
if [ "$ELASTICSEARCH_START" -ne "1" ]; then
  echo "ELASTICSEARCH_START is set to something different from 1, not starting..."
else
  # override ES_HEAP_SIZE variable if set
  if [ ! -z "$ES_HEAP_SIZE" ]; then
    awk -v LINE="-Xmx$ES_HEAP_SIZE" '{ sub(/^.Xmx.*/, LINE); print; }' /opt/elasticsearch/config/jvm.options \
        > /opt/elasticsearch/config/jvm.options.new && mv /opt/elasticsearch/config/jvm.options.new /opt/elasticsearch/config/jvm.options
    awk -v LINE="-Xms$ES_HEAP_SIZE" '{ sub(/^.Xms.*/, LINE); print; }' /opt/elasticsearch/config/jvm.options \
        > /opt/elasticsearch/config/jvm.options.new && mv /opt/elasticsearch/config/jvm.options.new /opt/elasticsearch/config/jvm.options
  fi

  # override ES_JAVA_OPTS variable if set
  if [ ! -z "$ES_JAVA_OPTS" ]; then
    awk -v LINE="ES_JAVA_OPTS=\"$ES_JAVA_OPTS\"" '{ sub(/^#?ES_JAVA_OPTS=.*/, LINE); print; }' /etc/default/elasticsearch \
        > /etc/default/elasticsearch.new && mv /etc/default/elasticsearch.new /etc/default/elasticsearch
  fi

  # override MAX_OPEN_FILES variable if set
  if [ ! -z "$MAX_OPEN_FILES" ]; then
    awk -v LINE="MAX_OPEN_FILES=$MAX_OPEN_FILES" '{ sub(/^#?MAX_OPEN_FILES=.*/, LINE); print; }' /etc/init.d/elasticsearch \
        > /etc/init.d/elasticsearch.new && mv /etc/init.d/elasticsearch.new /etc/init.d/elasticsearch \
        && chmod +x /etc/init.d/elasticsearch
  fi

  # override MAX_MAP_COUNT variable if set
  if [ ! -z "$MAX_MAP_COUNT" ]; then
    awk -v LINE="MAX_MAP_COUNT=$MAX_MAP_COUNT" '{ sub(/^#?MAX_MAP_COUNT=.*/, LINE); print; }' /etc/init.d/elasticsearch \
        > /etc/init.d/elasticsearch.new && mv /etc/init.d/elasticsearch.new /etc/init.d/elasticsearch \
        && chmod +x /etc/init.d/elasticsearch
  fi

  service elasticsearch start

  # Wait for Elasticsearch to start up before either starting Kibana (if enabled)
  # or attempting to stream its log file
  # - https://github.com/elasticsearch/kibana/issues/3077

  # set number of retries (default: 30, override using ES_CONNECT_RETRY env var)
  re_is_numeric='^[0-9]+$'
  if ! [[ $ES_CONNECT_RETRY =~ $re_is_numeric ]] ; then
     ES_CONNECT_RETRY=30
  fi

  counter=0
  while [ ! "$(curl localhost:9200 2> /dev/null)" ] && [ $counter -lt $ES_CONNECT_RETRY  ]; do
    sleep 1
    ((counter++))
    echo "waiting for Elasticsearch to be up ($counter/$ES_CONNECT_RETRY)"
  done
  if [ ! "$(curl localhost:9200 2> /dev/null)" ]; then
    echo "Couln't start Elasticsearch. Exiting."
    echo "Elasticsearch log follows below."
    cat /var/log/elasticsearch/elasticsearch.log
    exit 1
  fi

  # Give ES some time to settle
  sleep 5

  # Change Elasticsearch password if not changed already
  if [ "$ES_PASSWORD" != "$ES_DEFAULT_PASSWD" ]; then
    curl --fail -u elastic:$ES_PASSWORD localhost:9200 > /dev/null 2>&1

    if [ $? -ne 0 ]; then
      echo "Updating password for user: elastic"
      curl -XPUT 'localhost:9200/_xpack/security/user/elastic/_password' \
        -u elastic:$ES_DEFAULT_PASSWD \
        -H 'Content-Type: application/json' \
        -d "{ \"password\": \"${ES_PASSWORD}\" }"
      echo " "
    fi
  fi

  # Change Logstash default password if not changed already
  if [ "$LS_PASSWORD" != "$LS_DEFAULT_PASSWD" ]; then
    curl --fail -u logstash_system:$LS_PASSWORD localhost:9200 > /dev/null 2>&1

    if [ $? -ne 0 ]; then
      echo "Updating password for user: logstash_system"
      curl -XPUT 'localhost:9200/_xpack/security/user/logstash_system/_password' \
        -u elastic:$ES_PASSWORD \
        -H 'Content-Type: application/json' \
        -d "{ \"password\": \"${LS_PASSWORD}\" }"
      echo " "
    fi
  fi

  # Change Kibana default password if not changed already
  if [ "$KB_PASSWORD" != "$KB_DEFAULT_PASSWD" ]; then
    curl --fail -u kibana:$KB_PASSWORD localhost:9200 > /dev/null 2>&1

    if [ $? -ne 0 ]; then
      echo "Updating password for user: kibana"
      curl -XPUT 'localhost:9200/_xpack/security/user/kibana/_password' \
        -u elastic:$ES_PASSWORD \
        -H 'Content-Type: application/json' \
        -d "{ \"password\": \"${KB_PASSWORD}\" }"
      echo " "
    fi
  fi

  # Wait for cluster to respond before getting its name
  counter=0
  while [ -z "$CLUSTER_NAME" ] && [ $counter -lt 30 ]; do
    sleep 1
    ((counter++))
    CLUSTER_NAME=$(curl -u elastic:${ES_PASSWORD} localhost:9200/_cat/health?h=cluster 2> /dev/null | tr -d '[:space:]')
    echo "Waiting for Elasticsearch cluster to respond ($counter/30)"
  done
  if [ -z "$CLUSTER_NAME" ]; then
    echo "Couln't get name of cluster. Exiting."
    echo "Elasticsearch log follows below."
    cat /var/log/elasticsearch/elasticsearch.log
    exit 1
  else
    echo "Elasticsearch cluster name: ${CLUSTER_NAME}"
  fi
  OUTPUT_LOGFILES+="/var/log/elasticsearch/${CLUSTER_NAME}.log "
fi

#==============================================
# Start Logstash
#==============================================
if [ -z "$LOGSTASH_START" ]; then
  LOGSTASH_START=1
fi
if [ "$LOGSTASH_START" -ne "1" ]; then
  echo "LOGSTASH_START is set to something different from 1, not starting..."
else
  # Override LS_HEAP_SIZE variable if set
  if [ ! -z "$LS_HEAP_SIZE" ]; then
    awk -v LINE="-Xmx$LS_HEAP_SIZE" '{ sub(/^.Xmx.*/, LINE); print; }' /opt/logstash/config/jvm.options \
        > /opt/logstash/config/jvm.options.new && mv /opt/logstash/config/jvm.options.new /opt/logstash/config/jvm.options
    awk -v LINE="-Xms$LS_HEAP_SIZE" '{ sub(/^.Xms.*/, LINE); print; }' /opt/logstash/config/jvm.options \
        > /opt/logstash/config/jvm.options.new && mv /opt/logstash/config/jvm.options.new /opt/logstash/config/jvm.options
  fi

  # Override LS_OPTS variable if set
  if [ ! -z "$LS_OPTS" ]; then
    awk -v LINE="LS_OPTS=\"$LS_OPTS\"" '{ sub(/^LS_OPTS=.*/, LINE); print; }' /etc/init.d/logstash \
        > /etc/init.d/logstash.new && mv /etc/init.d/logstash.new /etc/init.d/logstash && chmod +x /etc/init.d/logstash
  fi

  # Update configuration with logstash password
  if [ "$LS_PASSWORD" != "$LS_DEFAULT_PASSWD" ]; then
    sed -i -e "s/^xpack.monitoring.elasticsearch.password:.*$/xpack.monitoring.elasticsearch.password: $LS_PASSWORD/" \
      /opt/logstash/config/logstash.yml
  fi

  # Update elasticsearch output
  if [ "$ES_PASSWORD" != "$ES_DEFAULT_PASSWD" ]; then
    sed -i -e "s/password => .*$/password => \"$ES_PASSWORD\"/" \
      /etc/logstash/conf.d/30-output.conf
  fi

  service logstash start
  OUTPUT_LOGFILES+="/var/log/logstash/logstash-plain.log "
fi

#==============================================
# Start Kibana
#==============================================
if [ -z "$KIBANA_START" ]; then
  KIBANA_START=1
fi
if [ "$KIBANA_START" -ne "1" ]; then
  echo "KIBANA_START is set to something different from 1, not starting..."
else
  # override NODE_OPTIONS variable if set
  if [ ! -z "$NODE_OPTIONS" ]; then
    awk -v LINE="NODE_OPTIONS=\"$NODE_OPTIONS\"" '{ sub(/^NODE_OPTIONS=.*/, LINE); print; }' /etc/init.d/kibana \
        > /etc/init.d/kibana.new && mv /etc/init.d/kibana.new /etc/init.d/kibana && chmod +x /etc/init.d/kibana
  fi

  # Update configuration with kibana password
  if [ "$KB_PASSWORD" != "$KB_DEFAULT_PASSWD" ]; then
    sed -i -e "s/^elasticsearch.password:.*$/elasticsearch.password: $KB_PASSWORD/" \
      /opt/kibana/config/kibana.yml
  fi

  service kibana start
  OUTPUT_LOGFILES+="/var/log/kibana/kibana5.log "
fi

# Exit if nothing has been started
if [ "$ELASTICSEARCH_START" -ne "1" ] && [ "$LOGSTASH_START" -ne "1" ] \
  && [ "$KIBANA_START" -ne "1" ]; then
  >&2 echo "No services started. Exiting."
  exit 1
fi

touch $OUTPUT_LOGFILES
tail -f $OUTPUT_LOGFILES &
wait
