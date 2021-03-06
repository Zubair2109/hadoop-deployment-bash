#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright Clairvoyant 2015

# ARGV:
# 1 - TLS certificate Common Name - required
# 2 - JKS store password - required
# 3 - JKS key password - required
# 4 - Extra parameters for keytool (ie Subject Alternative Name (SAN)) - optional

echo "********************************************************************************"
echo "*** $(basename $0)"
echo "********************************************************************************"
#"CN=cmhost.sec.cloudera.com,OU=Support,O=Cloudera,L=Denver,ST=Colorado,C=US"
DN="$1"
SP="$2"
KP="$3"
#"SAN=DNS:`hostname`,DNS:my-lb.domain.com"
EXT="$4"
if [ -z "$DN" ]; then
  echo "ERROR: Missing distinguished name."
  exit 1
fi
if [ -z "$SP" ]; then
  echo "ERROR: Missing keystore password."
  exit 2
fi
if [ -z "$KP" ]; then
  echo "ERROR: Missing private key password."
  exit 3
fi
if [ -n "$EXT" ]; then
  EXT="-ext $EXT"
fi

echo "Generating TLS CSRs..."
if [ -f /etc/profile.d/jdk.sh ]; then
  . /etc/profile.d/jdk.sh
elif [ -f /etc/profile.d/java.sh ]; then
  . /etc/profile.d/java.sh
fi

keytool -genkeypair -alias localhost -keyalg RSA -sigalg SHA256withRSA \
-keystore /opt/cloudera/security/jks/localhost-keystore.jks \
-keysize 2048 -dname "$DN" -storepass $SP -keypass $KP

chmod 0644 /opt/cloudera/security/jks/localhost-keystore.jks
chown root:root /opt/cloudera/security/jks/localhost-keystore.jks

# https://www.cloudera.com/documentation/enterprise/5-9-x/topics/cm_sg_create_deploy_certs.html#concept_frd_1px_nw
# X509v3 Extended Key Usage:
#   TLS Web Server Authentication, TLS Web Client Authentication
keytool -certreq -alias localhost \
-keystore /opt/cloudera/security/jks/localhost-keystore.jks \
-file /opt/cloudera/security/x509/localhost.csr -storepass $SP \
-keypass $KP -ext EKU=serverAuth,clientAuth $EXT

rm -f /tmp/localhost-keystore.p12.$$

keytool -importkeystore -srckeystore /opt/cloudera/security/jks/localhost-keystore.jks \
-srcstorepass $SP -srckeypass $KP -destkeystore /tmp/localhost-keystore.p12.$$ \
-deststoretype PKCS12 -srcalias localhost -deststorepass $SP -destkeypass $KP

openssl pkcs12 -in /tmp/localhost-keystore.p12.$$ -passin pass:$KP -nocerts \
-out /opt/cloudera/security/x509/localhost.e.key -passout pass:$KP

openssl rsa -in /opt/cloudera/security/x509/localhost.e.key \
-passin pass:$KP -out /opt/cloudera/security/x509/localhost.key

chmod 0400 /opt/cloudera/security/x509/localhost.e.key /opt/cloudera/security/x509/localhost.key

rm -f /tmp/localhost-keystore.p12.$$

install -o root -g root -m 0755 -d /etc/cloudera-scm-agent
install -o root -g root -m 0600 /dev/null /etc/cloudera-scm-agent/agentkey.pw
echo "$SP" >/etc/cloudera-scm-agent/agentkey.pw

