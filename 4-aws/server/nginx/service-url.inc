# 프록시할 주소를 담는 변수. 처음에는 blue 포트를 가리킨다(blue 는 8081, green 은 8082)
# deploy-bluegreen.sh 가 전환할 때마다 이 파일을 한 줄로 덮어쓰므로, 이 주석은 첫 배포 뒤 사라진다
set $service_url http://127.0.0.1:8081;
