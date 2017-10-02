# Elasticsearch, Logstash, Kibana, XPack (ELKX) Docker image

[![Build Status](https://travis-ci.org/maestrano/docker-elkx.svg?branch=master)](https://travis-ci.org/maestrano/docker-elkx)

This Docker image provides a convenient centralised log server and log management web interface, by packaging Elasticsearch, Logstash, Kibana and XPack (ELKX).

Originally started from the excellent https://github.com/spujadas/elk-docker repo.

## Examples

Standard run with support for Kibana (5601), Elasticsearch (9200), Filebeat (5044) and Gelf (12201)
```
docker run -p 5601:5601 -p 9200:9200 -p 5044:5044 -p 12201:12201/udp -it --name elk maestrano/elkx
```

Run and specify passwords for elastic, kibana and logstash_system users (respectively)
```
docker run -p 5601:5601 -p 9200:9200 -p 5044:5044 -p 12201:12201/udp -it --name elk \
  -e ES_PASSWORD=bl1bl1 \
  -e KB_PASSWORD=bl2bl2 \
  -e LS_PASSWORD=bl2bl2 \
  maestrano/elkx
```
