#!/bin/bash
# 위 줄(shebang): 이 스크립트를 bash 로 실행한다
# -e: 명령이 실패하면 즉시 종료 / -u: 정의 안 된 변수를 쓰면 오류 / -o pipefail: 파이프 중간 실패도 실패로 본다
set -euo pipefail

# GitHub 사용자명 (소문자로)
GH_USER="CHANGE_ME"

TAG="${1:?이미지 태그를 인자로 넘겨야 한다}"           # 첫 번째 인자를 태그로 쓴다. 없으면 메시지를 내고 종료한다
IMAGE="ghcr.io/${GH_USER}/visit-counter:${TAG}"        # GitHub Container Registry 의 전체 이미지 주소
INC="/etc/nginx/conf.d/service-url.inc"                # nginx 가 프록시할 주소를 담은 include 파일

# ── 0. 동시에 두 번 돌지 않게 잠근다 ───────────────────────
# 워크플로의 concurrency 는 Actions 끼리만 막는다. 사람이 서버에서 직접
# 돌린 배포와 겹치는 것까지 막으려면 서버 쪽에도 잠금이 있어야 한다.
exec 9> /tmp/deploy.lock                               # 파일 디스크립터 9 로 잠금 파일을 연다
flock -n 9 || { echo "!!  다른 배포가 진행 중이다. 끝난 뒤 다시 실행한다."; exit 1; }  # 잠금을 기다리지 않고(-n) 시도, 실패하면 종료

# ── 1. 지금 서비스 중인 색을 판별한다 ───────────────────────
CURRENT_PORT="$(sed -n 's#.*127\.0\.0\.1:\([0-9]\{4\}\).*#\1#p' "$INC")"  # include 파일에서 127.0.0.1: 뒤의 4자리 포트만 뽑는다
case "$CURRENT_PORT" in
  8081) CURRENT=blue;  TARGET=green; TARGET_PORT=8082 ;;  # 지금 blue(8081)면 green(8082)을 새로 띄운다
  8082) CURRENT=green; TARGET=blue;  TARGET_PORT=8081 ;;  # 지금 green(8082)이면 blue(8081)를 새로 띄운다
  *)    echo "!!  $INC 에서 포트를 읽지 못했다 (읽은 값: '${CURRENT_PORT}')"  # 그 밖의 값이면
        echo "    아무것도 바꾸지 않고 중단한다."; exit 1 ;;               # 안전하게 중단한다
esac
echo "==> 현재 $CURRENT(:$CURRENT_PORT) / 새로 띄울 쪽 $TARGET(:$TARGET_PORT)"

# ── 2. 쉬고 있는 쪽에 새 버전을 띄운다 ──────────────────────
docker pull "$IMAGE"                                   # 레지스트리에서 새 이미지를 받는다
docker rm -f "visit-counter-$TARGET" 2>/dev/null || true  # 같은 이름의 남은 컨테이너를 지운다. 없어도 실패로 치지 않는다
# -d: 백그라운드 / --name: visit-counter-blue 또는 -green / -p: 호스트의 127.0.0.1 에만 포트를 연다
# --env-file: 홈의 app.env 에서 환경 변수를 읽는다 / --restart: 직접 멈추지 않는 한 다시 띄운다
docker run -d \
  --name "visit-counter-$TARGET" \
  -p "127.0.0.1:${TARGET_PORT}:8080" \
  --env-file "$HOME/app.env" \
  --restart unless-stopped \
  "$IMAGE"

# ── 3. 준비될 때까지 기다린다 ───────────────────────────────
echo "==> 헬스 체크"
READY=0                                                # 준비 여부 플래그(0: 아직)
for i in $(seq 1 30); do                               # 2초 간격으로 최대 30번(약 60초) 시도한다
  # -f: HTTP 오류면 실패 / -s: 진행 표시 숨김. 응답 본문에 "status":"UP" 이 있으면 준비 완료
  if curl -fs "http://127.0.0.1:${TARGET_PORT}/actuator/health" | grep -q '"status":"UP"'; then
    echo "    준비 완료 ($(( (i-1) * 2 ))초)"           # 기다린 시간을 계산해 보여준다
    READY=1                                            # 준비됨으로 표시
    break                                              # 반복 종료
  fi
  sleep 2                                              # 2초 쉬고 다시 시도한다
done

# ── 4. 준비되지 않았으면 전환하지 않는다 ────────────────────
if [ "$READY" -ne 1 ]; then                            # 끝내 준비되지 않았으면
  echo "!!  기동 실패 - 전환하지 않는다. $CURRENT 가 계속 서비스한다."
  # 진짜 원인은 긴 스택 트레이스 위쪽에 있어 마지막 몇 줄로는 안 보인다.
  # 원인이 적히는 줄(FATAL, SQLState)을 먼저 뽑아 보여준다.
  echo "    ---- 원인 ----"
  docker logs "visit-counter-$TARGET" 2>&1 | grep -m 4 -E 'FATAL|SQLState' || true  # 원인 줄 최대 4개. 없어도 실패로 치지 않는다
  echo "    ---- 마지막 15줄 ----"
  docker logs --tail 15 "visit-counter-$TARGET" 2>&1 || true  # 마지막 15줄을 보여준다
  docker rm -f "visit-counter-$TARGET"                 # 실패한 컨테이너를 지운다
  exit 1                                               # 전환하지 않고 종료한다
fi

# ── 5. 전환 — 검사에 실패하면 되돌린다 ──────────────────────
PREV="$(cat "$INC")"                                   # 되돌릴 수 있게 현재 include 내용을 보관한다
echo "set \$service_url http://127.0.0.1:${TARGET_PORT};" | sudo tee "$INC" > /dev/null  # 새 포트를 가리키도록 include 파일을 덮어쓴다(\$ 는 nginx 변수라 셸이 치환하지 않게 한다)
if ! sudo nginx -t; then                               # 새 설정의 문법을 검사한다
  printf '%s\n' "$PREV" | sudo tee "$INC" > /dev/null  # 실패하면 보관해 둔 내용으로 되돌린다
  echo "!!  nginx 설정 검사 실패 - 원래 설정으로 되돌렸다."
  docker rm -f "visit-counter-$TARGET"                 # 새 컨테이너를 지운다
  exit 1
fi
sudo systemctl reload nginx                            # 중단 없이 새 설정을 적용한다
echo "==> $TARGET 으로 전환 완료"

# ── 6. 이전 쪽 정리 ─────────────────────────────────────────
# reload 직후에도 옛 워커가 진행 중이던 요청을 마저 처리하고 있다.
# 곧바로 지우면 그 요청들만 502 가 된다.
sleep 5
# rm -f 는 SIGKILL 이라 처리 중인 요청을 그 자리에서 끊는다.
# stop 은 SIGTERM 을 보내 Spring Boot 가 남은 요청을 마무리하고 내려가게 한다.
docker stop -t 30 "visit-counter-$CURRENT" > /dev/null 2>&1 || true  # 최대 30초 기다린 뒤 강제 종료. 없어도 무시
docker rm "visit-counter-$CURRENT" > /dev/null 2>&1 || true          # 멈춘 컨테이너를 지운다. 없어도 무시

# 낡은 이미지를 치우지 않으면 디스크가 찬다.
# 방금 배포한 태그만 남기고 같은 저장소의 나머지 태그를 지운다.
# 저장소:태그 목록 → 이번 태그를 뺀 나머지 → 있으면(-r) docker rmi 로 삭제
docker images "ghcr.io/${GH_USER}/visit-counter" --format '{{.Repository}}:{{.Tag}}' \
  | grep -v ":${TAG}$" | xargs -r docker rmi -f > /dev/null 2>&1 || true
docker image prune -f > /dev/null          # 태그가 떨어져 나간 <none> 이미지까지
echo "==> 정리 완료"
