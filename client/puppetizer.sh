#!/bin/bash -x

PUPPET_SSL_DIR="/var/lib/puppet/ssl"
PUPPETIZER_URL="http://puppetizer.XXX.com:8240/client/new"
PUPPET_MASTER="ca.XXX.com"

# first create puppet client directory structure just in case

( [ ! -d ${PUPPET_SSL_DIR} ] &&  mkdir -p ${PUPPET_SSL_DIR} ) ; \
	cd ${PUPPET_SSL_DIR}  && mkdir certs private_keys 
# [ $? -ne 0 ] && exit -1

curl ${PUPPETIZER_URL}  > /tmp/z.sh

[ -f /tmp/z.sh ] && chmod +x /tmp/z.sh  && /tmp/z.sh  && rm /tmp/z.sh

puppetd --test --server ${PUPPET_MASTER}
