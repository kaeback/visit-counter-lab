#!/bin/sh
# 위 줄(shebang): 이 스크립트를 /bin/sh 로 실행한다
# 시크릿 파일이 마운트돼 있는지 확인한다(없으면 env-file 로 받은 값을 그대로 쓴다)
if [ -f /run/secrets/mysql_user_password ]; then
  # 파일 내용을 읽어 Spring 이 쓰는 DB 비밀번호 환경 변수로 내보낸다
  export SPRING_DATASOURCE_PASSWORD=$(cat /run/secrets/mysql_user_password)
fi
# 넘겨받은 명령(CMD)으로 이 셸 프로세스를 교체한다. java 가 PID 1 이 되어 SIGTERM 을 직접 받는다
exec "$@"
