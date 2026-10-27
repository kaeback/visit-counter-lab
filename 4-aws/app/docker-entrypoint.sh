#!/bin/sh
if [ -f /run/secrets/mysql_user_password ]; then
  export SPRING_DATASOURCE_PASSWORD=$(cat /run/secrets/mysql_user_password)
fi
exec "$@"
