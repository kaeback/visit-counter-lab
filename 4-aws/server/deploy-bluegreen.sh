#!/bin/bash
set -euo pipefail

# GitHub 사용자명 (소문자로)
GH_USER="CHANGE_ME"

TAG="${1:?이미지 태그를 인자로 넘겨야 한다}"
IMAGE="ghcr.io/${GH_USER}/visit-counter:${TAG}"
INC="/etc/nginx/conf.d/service-url.inc"

# ── 0. 동시에 두 번 돌지 않게 잠근다 ───────────────────────
# 워크플로의 concurrency 는 Actions 끼리만 막는다. 사람이 서버에서 직접
# 돌린 배포와 겹치는 것까지 막으려면 서버 쪽에도 잠금이 있어야 한다.
exec 9> /tmp/deploy.lock
flock -n 9 || { echo "!!  다른 배포가 진행 중이다. 끝난 뒤 다시 실행한다."; exit 1; }

# ── 1. 지금 서비스 중인 색을 판별한다 ───────────────────────
CURRENT_PORT="$(sed -n 's#.*127\.0\.0\.1:\([0-9]\{4\}\).*#\1#p' "$INC")"
case "$CURRENT_PORT" in
  8081) CURRENT=blue;  TARGET=green; TARGET_PORT=8082 ;;
  8082) CURRENT=green; TARGET=blue;  TARGET_PORT=8081 ;;
  *)    echo "!!  $INC 에서 포트를 읽지 못했다 (읽은 값: '${CURRENT_PORT}')"
        echo "    아무것도 바꾸지 않고 중단한다."; exit 1 ;;
esac
echo "==> 현재 $CURRENT(:$CURRENT_PORT) / 새로 띄울 쪽 $TARGET(:$TARGET_PORT)"

# ── 2. 쉬고 있는 쪽에 새 버전을 띄운다 ──────────────────────
docker pull "$IMAGE"
docker rm -f "visit-counter-$TARGET" 2>/dev/null || true
docker run -d \
  --name "visit-counter-$TARGET" \
  -p "127.0.0.1:${TARGET_PORT}:8080" \
  --env-file "$HOME/app.env" \
  --restart unless-stopped \
  "$IMAGE"

# ── 3. 준비될 때까지 기다린다 ───────────────────────────────
echo "==> 헬스 체크"
READY=0
for i in $(seq 1 30); do
  if curl -fs "http://127.0.0.1:${TARGET_PORT}/actuator/health" | grep -q '"status":"UP"'; then
    echo "    준비 완료 ($(( (i-1) * 2 ))초)"
    READY=1
    break
  fi
  sleep 2
done

# ── 4. 준비되지 않았으면 전환하지 않는다 ────────────────────
if [ "$READY" -ne 1 ]; then
  echo "!!  기동 실패 - 전환하지 않는다. $CURRENT 가 계속 서비스한다."
  # 진짜 원인은 긴 스택 트레이스 위쪽에 있어 마지막 몇 줄로는 안 보인다.
  # 원인이 적히는 줄(FATAL, SQLState)을 먼저 뽑아 보여준다.
  echo "    ---- 원인 ----"
  docker logs "visit-counter-$TARGET" 2>&1 | grep -m 4 -E 'FATAL|SQLState' || true
  echo "    ---- 마지막 15줄 ----"
  docker logs --tail 15 "visit-counter-$TARGET" 2>&1 || true
  docker rm -f "visit-counter-$TARGET"
  exit 1
fi

# ── 5. 전환 — 검사에 실패하면 되돌린다 ──────────────────────
PREV="$(cat "$INC")"
echo "set \$service_url http://127.0.0.1:${TARGET_PORT};" | sudo tee "$INC" > /dev/null
if ! sudo nginx -t; then
  printf '%s\n' "$PREV" | sudo tee "$INC" > /dev/null
  echo "!!  nginx 설정 검사 실패 - 원래 설정으로 되돌렸다."
  docker rm -f "visit-counter-$TARGET"
  exit 1
fi
sudo systemctl reload nginx
echo "==> $TARGET 으로 전환 완료"

# ── 6. 이전 쪽 정리 ─────────────────────────────────────────
# reload 직후에도 옛 워커가 진행 중이던 요청을 마저 처리하고 있다.
# 곧바로 지우면 그 요청들만 502 가 된다.
sleep 5
# rm -f 는 SIGKILL 이라 처리 중인 요청을 그 자리에서 끊는다.
# stop 은 SIGTERM 을 보내 Spring Boot 가 남은 요청을 마무리하고 내려가게 한다.
docker stop -t 30 "visit-counter-$CURRENT" > /dev/null 2>&1 || true
docker rm "visit-counter-$CURRENT" > /dev/null 2>&1 || true

# 낡은 이미지를 치우지 않으면 디스크가 찬다.
# 방금 배포한 태그만 남기고 같은 저장소의 나머지 태그를 지운다.
docker images "ghcr.io/${GH_USER}/visit-counter" --format '{{.Repository}}:{{.Tag}}' \
  | grep -v ":${TAG}$" | xargs -r docker rmi -f > /dev/null 2>&1 || true
docker image prune -f > /dev/null          # 태그가 떨어져 나간 <none> 이미지까지
echo "==> 정리 완료"
