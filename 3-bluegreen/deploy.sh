#!/bin/bash
set -u

APP="visit-counter"
NETWORK="dsa_service_network"
NGINX="dsa-nginx"

BASE="/service/docker"
BUILD_DIR="$BASE/build"
NGINX_CONF_DIR="$BASE/config/nginx"
ENV_FILE="$BASE/service.env"
DEPLOY_LOG="$BASE/deploy.log"

# 전환 후 이전 컨테이너를 지우기 전에 기다릴 시간(초)
DRAIN_SECONDS=10

# 레지스트리에 올리고 싶을 때만 값을 준다.
#   REGISTRY=docker.io/<내계정> ./deploy.sh
REGISTRY="${REGISTRY:-}"

# 로그는 덧붙인다(-a). 덮어쓰면 실행할 때마다 지워져,
# 정작 필요한 "직전 실패의 기록" 이 남지 않는다.
exec > >(tee -a "$DEPLOY_LOG")
exec 2>&1

echo "===== $(date '+%Y-%m-%d %H:%M:%S') 배포 시작 ====="

TAG=$(date +%Y%m%d%H%M%S)

# ── 1. 서비스 이미지 빌드 ────────────────────────────────────
# 컨텍스트는 build/ 하나뿐이다. /service/docker 를 통째로 넘기면
# volumes/ 아래의 MySQL 데이터까지 데몬으로 전송된다.
echo "[INFO] 이미지를 빌드한다: $APP:$TAG"
docker build -t "$APP:$TAG" -f "$BUILD_DIR/Dockerfile-service" "$BUILD_DIR" || {
  echo "[ERROR] 이미지 빌드에 실패했다."; exit 1
}

# ── 2. (선택) 레지스트리 업로드 ──────────────────────────────
if [ -n "$REGISTRY" ]; then
  echo "[INFO] $REGISTRY/$APP:$TAG 로 업로드한다."
  docker tag "$APP:$TAG" "$REGISTRY/$APP:$TAG" || exit 1
  docker push "$REGISTRY/$APP:$TAG" || {
    echo "[ERROR] 업로드에 실패했다. docker login 을 했는지 확인한다."; exit 1
  }
else
  echo "[INFO] REGISTRY 가 비어 있어 업로드는 건너뛴다."
fi

# ── 3. 지금 서비스 중인 색을 nginx 설정에서 읽는다 ───────────
# 컨테이너 상태가 아니라 "트래픽이 실제로 어디로 가는가" 를 기준으로 정한다.
current=$(docker exec "$NGINX" cat /etc/nginx/conf.d/default.conf 2>/dev/null \
          | grep -oE '(blue|green)-service' | head -n 1)

if [ "$current" = "blue-service" ]; then
  new_target="green-service"; new_port=8081; old_target="blue-service"
else
  new_target="blue-service";  new_port=8080; old_target="green-service"
fi
echo "[INFO] 현재 대상: ${current:-없음(첫 배포)} / 새로 띄울 대상: $new_target(:$new_port)"

# ── 4. 같은 이름의 컨테이너가 남아 있으면 지운다 ─────────────
if docker inspect "$new_target" > /dev/null 2>&1; then
  echo "[INFO] 이전에 남은 $new_target 컨테이너를 제거한다."
  docker rm -f "$new_target" > /dev/null || exit 1
fi

# ── 5. 새 컨테이너 실행 ──────────────────────────────────────
echo "[INFO] $new_target 컨테이너를 실행한다."
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
health=000
for i in $(seq 1 30); do
  # 앱이 죽어 컨테이너가 Exited 가 되면 더 기다릴 이유가 없다.
  if [ "$(docker inspect -f '{{.State.Running}}' "$new_target" 2>/dev/null)" != "true" ]; then
    echo "[ERROR] $new_target 컨테이너가 종료됐다."
    break
  fi
  # 아직 기동 중이거나 curl 이 실패하면 빈 문자열이 온다.
  # 숫자 비교 대신 문자열 비교를 쓰고, 빈 값은 000 으로 바꿔 둔다.
  health=$(docker exec "$new_target" \
           curl -s -o /dev/null -w '%{http_code}' \
           http://localhost:8080/actuator/health 2>/dev/null)
  health="${health:-000}"
  [ "$health" = "200" ] && break
  echo "[INFO] 대기 중 ($i/30) - 현재 $health"
  sleep 2
done

if [ "$health" != "200" ]; then
  echo "[ERROR] $new_target 가 200 을 돌려주지 않는다($health). 전환하지 않는다."
  # 진짜 원인은 긴 스택 트레이스 위쪽에 있다. 원인이 적히는 줄을 먼저 뽑는다.
  echo "[ERROR] ---- 원인 ----"
  docker logs "$new_target" 2>&1 | grep -m 4 -E 'Access denied|SQLState|FATAL' || true
  echo "[ERROR] ---- 애플리케이션 로그 (마지막 15줄) ----"
  docker logs --tail 15 "$new_target" 2>&1
  echo "[ERROR] 원인을 더 볼 수 있도록 $new_target 컨테이너는 지우지 않는다."
  echo "[ERROR]   docker logs $new_target 2>&1 | less"
  echo "[ERROR] 다음 배포가 4번 단계에서 이 컨테이너를 자동으로 치운다."
  exit 1
fi
echo "[INFO] $new_target 준비 완료 (HTTP 200)"

# ── 7. nginx 설정 교체 → 검사 → 리로드 ──────────────────────
echo "[INFO] nginx 설정을 $new_target 로 바꾼다."
docker exec "$NGINX" cp /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak

rollback() {
  echo "[WARN] nginx 설정을 이전 상태로 되돌린다."
  docker exec "$NGINX" cp /etc/nginx/conf.d/default.conf.bak /etc/nginx/conf.d/default.conf
  docker exec "$NGINX" nginx -s reload
  docker rm -f "$new_target" > /dev/null
}

docker cp "$NGINX_CONF_DIR/default-$new_target.conf" \
          "$NGINX:/etc/nginx/conf.d/default.conf" || {
  echo "[ERROR] 설정 파일 복사에 실패했다. $NGINX_CONF_DIR 를 확인한다."
  docker rm -f "$new_target" > /dev/null
  exit 1
}

if ! docker exec "$NGINX" nginx -t; then
  echo "[ERROR] 새 설정이 nginx 검사를 통과하지 못했다."
  rollback
  exit 1
fi

docker exec "$NGINX" nginx -s reload || {
  echo "[ERROR] 리로드에 실패했다."; rollback; exit 1
}

# ── 8. nginx(80) 를 통해 실제로 응답하는지 확인 ──────────────
# nginx -s reload 가 0 을 돌려준 것은 "마스터에 시그널을 보냈다" 는 뜻일 뿐,
# 새 설정이 적용됐다는 증명이 아니다. 응답으로 확인한다.
echo "[INFO] nginx 를 통해 응답을 확인한다."
via=000
for i in $(seq 1 10); do
  via=$(docker exec "$new_target" \
        curl -s -o /dev/null -w '%{http_code}' \
        "http://$NGINX/actuator/health" 2>/dev/null)
  via="${via:-000}"
  [ "$via" = "200" ] && break
  sleep 2
done

if [ "$via" != "200" ]; then
  echo "[ERROR] nginx 를 통한 응답이 $via 다. 전환을 취소한다."
  docker logs --tail 20 "$NGINX"
  rollback
  exit 1
fi
echo "[INFO] nginx 를 통한 응답 확인 (HTTP 200)"

# ── 9. 이전 컨테이너 정리 ────────────────────────────────────
# 리로드 직후에도 예전 워커 프로세스가 처리 중인 요청이 남아 있다.
# 바로 지우면 그 요청들이 502 로 끝난다.
echo "[INFO] 처리 중인 요청이 끝나도록 ${DRAIN_SECONDS}초 기다린다."
sleep "$DRAIN_SECONDS"

if docker inspect "$old_target" > /dev/null 2>&1; then
  echo "[INFO] 이전 컨테이너($old_target)를 내리고 제거한다."
  # rm -f 는 SIGKILL 이다. stop 으로 SIGTERM 을 보내야 앱이 남은 요청을 마무리한다.
  docker stop -t 30 "$old_target" > /dev/null
  docker rm "$old_target" > /dev/null
fi

# 태그가 밀려난 이미지 정리
docker image prune -f --filter "dangling=true" > /dev/null

echo "===== $(date '+%Y-%m-%d %H:%M:%S') 배포 완료: $new_target ($APP:$TAG) ====="
