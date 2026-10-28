#!/bin/bash
# 위 줄(shebang): 이 스크립트를 bash 로 실행한다
# -u: 정의 안 된 변수를 쓰면 오류로 멈춘다(-e 는 쓰지 않고 실패를 직접 처리한다)
set -u

APP="visit-counter"                  # 이미지 이름
NETWORK="dsa_service_network"        # 컨테이너들이 함께 쓰는 Docker 네트워크
NGINX="dsa-nginx"                    # 트래픽을 전환할 nginx 컨테이너 이름

BASE="/service/docker"               # 서버의 배포 기준 디렉터리
BUILD_DIR="$BASE/build"              # Dockerfile-service 와 JAR 가 있는 빌드 컨텍스트
NGINX_CONF_DIR="$BASE/config/nginx"  # blue/green 용 nginx 설정 파일 위치
ENV_FILE="$BASE/service.env"         # 앱 컨테이너에 넘길 환경 변수 파일
DEPLOY_LOG="$BASE/deploy.log"        # 배포 기록 파일

# 전환 후 이전 컨테이너를 지우기 전에 기다릴 시간(초)
DRAIN_SECONDS=10

# 레지스트리에 올리고 싶을 때만 값을 준다.
#   REGISTRY=docker.io/<내계정> ./deploy.sh
REGISTRY="${REGISTRY:-}"             # 환경 변수가 없으면 빈 문자열(-u 에 걸리지 않게 기본값을 준다)

# 로그는 덧붙인다(-a). 덮어쓰면 실행할 때마다 지워져,
# 정작 필요한 "직전 실패의 기록" 이 남지 않는다.
exec > >(tee -a "$DEPLOY_LOG")       # 이후 표준 출력을 화면과 로그 파일 양쪽으로 보낸다
exec 2>&1                            # 표준 오류도 표준 출력과 같은 곳으로 보낸다

echo "===== $(date '+%Y-%m-%d %H:%M:%S') 배포 시작 ====="  # 시작 시각을 기록한다

TAG=$(date +%Y%m%d%H%M%S)            # 현재 시각을 이미지 태그로 쓴다(배포마다 고유)

# ── 1. 서비스 이미지 빌드 ────────────────────────────────────
# 컨텍스트는 build/ 하나뿐이다. /service/docker 를 통째로 넘기면
# volumes/ 아래의 MySQL 데이터까지 데몬으로 전송된다.
echo "[INFO] 이미지를 빌드한다: $APP:$TAG"
# -t: 이미지 이름:태그 / -f: 사용할 Dockerfile / 마지막 인자: 빌드 컨텍스트. 실패하면 { } 안을 실행한다
docker build -t "$APP:$TAG" -f "$BUILD_DIR/Dockerfile-service" "$BUILD_DIR" || {
  echo "[ERROR] 이미지 빌드에 실패했다."; exit 1  # 오류를 알리고 종료한다
}

# ── 2. (선택) 레지스트리 업로드 ──────────────────────────────
if [ -n "$REGISTRY" ]; then                                # REGISTRY 값이 있을 때만
  echo "[INFO] $REGISTRY/$APP:$TAG 로 업로드한다."
  docker tag "$APP:$TAG" "$REGISTRY/$APP:$TAG" || exit 1   # 레지스트리 주소가 붙은 태그를 하나 더 단다
  docker push "$REGISTRY/$APP:$TAG" || {                   # 레지스트리로 올린다
    echo "[ERROR] 업로드에 실패했다. docker login 을 했는지 확인한다."; exit 1
  }
else                                                       # REGISTRY 가 비어 있으면
  echo "[INFO] REGISTRY 가 비어 있어 업로드는 건너뛴다."
fi

# ── 3. 지금 서비스 중인 색을 nginx 설정에서 읽는다 ───────────
# 컨테이너 상태가 아니라 "트래픽이 실제로 어디로 가는가" 를 기준으로 정한다.
# nginx 설정에서 blue-service / green-service 중 처음 나오는 이름 하나를 뽑는다
current=$(docker exec "$NGINX" cat /etc/nginx/conf.d/default.conf 2>/dev/null \
          | grep -oE '(blue|green)-service' | head -n 1)

if [ "$current" = "blue-service" ]; then                                      # 지금 blue 가 서비스 중이면
  new_target="green-service"; new_port=8081; old_target="blue-service"        # green 을 새로 띄운다
else                                                                          # green 이거나 첫 배포(빈 값)이면
  new_target="blue-service";  new_port=8080; old_target="green-service"       # blue 를 새로 띄운다
fi
echo "[INFO] 현재 대상: ${current:-없음(첫 배포)} / 새로 띄울 대상: $new_target(:$new_port)"  # 빈 값이면 "없음" 으로 표시

# ── 4. 같은 이름의 컨테이너가 남아 있으면 지운다 ─────────────
if docker inspect "$new_target" > /dev/null 2>&1; then     # 같은 이름의 컨테이너가 존재하면
  echo "[INFO] 이전에 남은 $new_target 컨테이너를 제거한다."
  docker rm -f "$new_target" > /dev/null || exit 1         # 강제로 지운다. 실패하면 종료
fi

# ── 5. 새 컨테이너 실행 ──────────────────────────────────────
echo "[INFO] $new_target 컨테이너를 실행한다."
# -d: 백그라운드 / --name: blue-service 또는 green-service / --network: nginx·DB 와 같은 네트워크
# -p: 호스트의 127.0.0.1 에만 포트를 연다(외부 직접 접근 차단) / --env-file: 앱 환경 변수
# --log-opt: 컨테이너 로그를 10MB × 최대 3개 파일로 제한한다. 출력(컨테이너 ID)은 버린다
docker run -d \
  --name "$new_target" \
  --network "$NETWORK" \
  -p "127.0.0.1:$new_port:8080" \
  --env-file "$ENV_FILE" \
  --log-opt max-size=10m --log-opt max-file=3 \
  "$APP:$TAG" > /dev/null || {
  echo "[ERROR] $new_target 실행에 실패했다."; exit 1
}

# ── 6. 새 컨테이너 헬스체크 ──────────────────────────────────
echo "[INFO] $new_target 헬스체크 (최대 60초)"
health=000                                                 # 아직 응답 없음을 뜻하는 초기값
for i in $(seq 1 30); do                                   # 2초 간격으로 최대 30번 시도한다
  # 앱이 죽어 컨테이너가 Exited 가 되면 더 기다릴 이유가 없다.
  if [ "$(docker inspect -f '{{.State.Running}}' "$new_target" 2>/dev/null)" != "true" ]; then
    echo "[ERROR] $new_target 컨테이너가 종료됐다."
    break                                                  # 반복을 끝내고 아래 실패 처리로 간다
  fi
  # 아직 기동 중이거나 curl 이 실패하면 빈 문자열이 온다.
  # 숫자 비교 대신 문자열 비교를 쓰고, 빈 값은 000 으로 바꿔 둔다.
  # 컨테이너 안에서 curl 로 actuator 를 호출하고 HTTP 상태 코드만 받는다
  health=$(docker exec "$new_target" \
           curl -s -o /dev/null -w '%{http_code}' \
           http://localhost:8080/actuator/health 2>/dev/null)
  health="${health:-000}"                                  # 빈 값이면 000 으로 바꾼다
  [ "$health" = "200" ] && break                           # 200 이면 준비 완료, 반복 종료
  echo "[INFO] 대기 중 ($i/30) - 현재 $health"
  sleep 2                                                  # 2초 쉬고 다시 시도한다
done

if [ "$health" != "200" ]; then                            # 끝내 200 을 받지 못했으면
  echo "[ERROR] $new_target 가 200 을 돌려주지 않는다($health). 전환하지 않는다."
  # 진짜 원인은 긴 스택 트레이스 위쪽에 있다. 원인이 적히는 줄을 먼저 뽑는다.
  echo "[ERROR] ---- 원인 ----"
  docker logs "$new_target" 2>&1 | grep -m 4 -E 'Access denied|SQLState|FATAL' || true  # 원인 줄 최대 4개. 없어도 실패로 치지 않는다
  echo "[ERROR] ---- 애플리케이션 로그 (마지막 15줄) ----"
  docker logs --tail 15 "$new_target" 2>&1                 # 마지막 15줄을 보여준다
  echo "[ERROR] 원인을 더 볼 수 있도록 $new_target 컨테이너는 지우지 않는다."
  echo "[ERROR]   docker logs $new_target 2>&1 | less"
  echo "[ERROR] 다음 배포가 4번 단계에서 이 컨테이너를 자동으로 치운다."
  exit 1                                                   # 전환하지 않고 종료한다
fi
echo "[INFO] $new_target 준비 완료 (HTTP 200)"

# ── 7. nginx 설정 교체 → 검사 → 리로드 ──────────────────────
echo "[INFO] nginx 설정을 $new_target 로 바꾼다."
docker exec "$NGINX" cp /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak  # 되돌릴 수 있게 현재 설정을 백업한다

rollback() {                                               # 전환 실패 시 호출할 되돌리기 함수
  echo "[WARN] nginx 설정을 이전 상태로 되돌린다."
  docker exec "$NGINX" cp /etc/nginx/conf.d/default.conf.bak /etc/nginx/conf.d/default.conf  # 백업본으로 복원한다
  docker exec "$NGINX" nginx -s reload                     # 복원한 설정을 적용한다
  docker rm -f "$new_target" > /dev/null                   # 새로 띄운 컨테이너를 지운다
}

# 새 대상용 설정 파일을 호스트에서 nginx 컨테이너 안으로 복사한다
docker cp "$NGINX_CONF_DIR/default-$new_target.conf" \
          "$NGINX:/etc/nginx/conf.d/default.conf" || {
  echo "[ERROR] 설정 파일 복사에 실패했다. $NGINX_CONF_DIR 를 확인한다."
  docker rm -f "$new_target" > /dev/null                   # 설정은 그대로이므로 새 컨테이너만 지운다
  exit 1
}

if ! docker exec "$NGINX" nginx -t; then                   # 새 설정의 문법을 검사한다
  echo "[ERROR] 새 설정이 nginx 검사를 통과하지 못했다."
  rollback                                                 # 실패하면 되돌린다
  exit 1
fi

docker exec "$NGINX" nginx -s reload || {                  # 중단 없이 새 설정을 적용한다
  echo "[ERROR] 리로드에 실패했다."; rollback; exit 1
}

# ── 8. nginx(80) 를 통해 실제로 응답하는지 확인 ──────────────
# nginx -s reload 가 0 을 돌려준 것은 "마스터에 시그널을 보냈다" 는 뜻일 뿐,
# 새 설정이 적용됐다는 증명이 아니다. 응답으로 확인한다.
echo "[INFO] nginx 를 통해 응답을 확인한다."
via=000                                                    # 아직 응답 없음을 뜻하는 초기값
for i in $(seq 1 10); do                                   # 2초 간격으로 최대 10번 시도한다
  # 같은 네트워크의 새 컨테이너 안에서 nginx 컨테이너 이름으로 요청해 상태 코드만 받는다
  via=$(docker exec "$new_target" \
        curl -s -o /dev/null -w '%{http_code}' \
        "http://$NGINX/actuator/health" 2>/dev/null)
  via="${via:-000}"                                        # 빈 값이면 000 으로 바꾼다
  [ "$via" = "200" ] && break                              # 200 이면 반복 종료
  sleep 2
done

if [ "$via" != "200" ]; then                               # nginx 경유 응답이 200 이 아니면
  echo "[ERROR] nginx 를 통한 응답이 $via 다. 전환을 취소한다."
  docker logs --tail 20 "$NGINX"                           # nginx 로그 마지막 20줄을 보여준다
  rollback                                                 # 이전 설정으로 되돌린다
  exit 1
fi
echo "[INFO] nginx 를 통한 응답 확인 (HTTP 200)"

# ── 9. 이전 컨테이너 정리 ────────────────────────────────────
# 리로드 직후에도 예전 워커 프로세스가 처리 중인 요청이 남아 있다.
# 바로 지우면 그 요청들이 502 로 끝난다.
echo "[INFO] 처리 중인 요청이 끝나도록 ${DRAIN_SECONDS}초 기다린다."
sleep "$DRAIN_SECONDS"                                     # 기존 요청이 빠질 시간을 준다

if docker inspect "$old_target" > /dev/null 2>&1; then     # 이전 컨테이너가 있으면(첫 배포면 없다)
  echo "[INFO] 이전 컨테이너($old_target)를 내리고 제거한다."
  # rm -f 는 SIGKILL 이다. stop 으로 SIGTERM 을 보내야 앱이 남은 요청을 마무리한다.
  docker stop -t 30 "$old_target" > /dev/null              # 최대 30초 기다린 뒤에도 안 끝나면 강제 종료
  docker rm "$old_target" > /dev/null                      # 멈춘 컨테이너를 지운다
fi

# 태그가 밀려난 이미지 정리
docker image prune -f --filter "dangling=true" > /dev/null # 태그 없는 <none> 이미지를 확인 없이 지운다

echo "===== $(date '+%Y-%m-%d %H:%M:%S') 배포 완료: $new_target ($APP:$TAG) ====="  # 완료 시각과 결과를 기록한다
