#!/bin/bash

set -o errexit

: ${DEBUG:=0}
[[ ${DEBUG} -eq 1 ]] && set -x

# Enable HTTP proxy server
: ${HTTPD_HTTP_ENABLED:=0}

# Enable Status page
: ${HTTPD_STATUS_ENABLED:=0}
: ${HTTPD_STATUS_LOCATION:=/status}
: ${HTTPD_STATUS_ALLOW:=127.0.0.1/8}
: ${HTTPD_STATUS_DENY:=all}

# OpenID Connect Provider
: ${OIDC_URL:?Not defined}
: ${OIDC_REALM:?Not defined}
# OpenID Connect Relying Party
: ${OIDC_CLIENT_ID:?Not defined}
: ${OIDC_CLIENT_SECRET:?Not defined}
: ${OIDC_SSL_VALIDATE_SERVER:=On}

# Proxy configuration
: ${PROXY_REQUIRE_DIRECTIVE:=valid-user}
: ${PROXY_BASE_URL:?Not defined}
: ${PROXY_LOCATION_MATCH:=$(echo ${PROXY_BASE_URL} | sed -e "s#\(http\|https\)://[^/]*[/]\?\(.*\)#/\2#")}
: ${REMOTE_BASE_URL:?Not defined}

echo "Proxy location ${PROXY_LOCATION_MATCH} to remote base URL: ${REMOTE_BASE_URL}"

[[ ${HTTPD_HTTP_ENABLED} -ne 1 && ${HTTPD_HTTPS_ENABLED} -ne 1 ]] \
  && >&2 echo "At least one of 'HTTPD_HTTP_ENABLED' or 'HTTPD_HTTPS_ENABLED' must be '1'!" \
  && exit 1

# Replace all set environment variables from in the current shell session.
# The environment variables present in the file but are unset will remain untouched.
# Replaced pattern is: ${<ENV_VAR>}
function substenv {
  local in_file="$1"
  local out_file="$2"
  local temp_file=$(mktemp -t substenv.XXXX)
  cat "${in_file}" > ${temp_file}
  compgen -v | while read var ; do
    sed -i "s/\${$var}/$(echo ${!var} | sed -e 's/\\/\\\\/g' -e 's/\//\\\//g' -e 's/&/\\\&/g')/g" "${temp_file}"
  done
  cat "${temp_file}" > "${out_file}" && rm -f "${temp_file}"
}

# Map user to current UID/GID
function map_uid() {
  export USER_ID="$(id -u)"
  export GROUP_ID="$(id -g)"
  substenv ${DOL_TMPL_DIR}/passwd.in /tmp/passwd
  substenv ${DOL_TMPL_DIR}/group.in /tmp/group
  export NSS_WRAPPER_PASSWD=/tmp/passwd
  export NSS_WRAPPER_GROUP=/tmp/group
  export LD_PRELOAD=/usr/lib64/libnss_wrapper.so
}

map_uid

# Generate core config for nginx server
echo "Configure Apache core server."
substenv ${DOL_TMPL_DIR}/httpd.conf.in /etc/httpd/conf/httpd.conf

# Generate proxy config for nginx server
echo "Configure Apache proxy server."
substenv ${DOL_TMPL_DIR}/httpd.vh.proxy.conf.in /etc/httpd/conf.d/proxy.conf

# Configure default server block locations
echo "Configure Apache proxy pass."
substenv ${DOL_TMPL_DIR}/httpd.location.root.conf.in /etc/httpd/default.d/root.conf

if [[ ${HTTPD_STATUS_ENABLED} -eq 1 ]] ; then
  echo "Enable Apache Status page."
  substenv ${DOL_TMPL_DIR}/httpd.location.status.conf.in /etc/httpd/default.d/status.conf
fi

# Configure HTTP server
if [[ ${HTTPD_HTTP_ENABLED} -eq 1 ]] ; then
  echo "Enable HTTPD proxy server."
  substenv ${DOL_TMPL_DIR}/httpd.vh.proxy-http.conf.in /etc/httpd/conf.d/proxy-http.conf
fi

if [[ $# -ge 1 ]]; then
  echo "$@"
  exec $@
else
  echo "Starting HTTPD proxy server."
  exec httpd -DFOREGROUND
fi
