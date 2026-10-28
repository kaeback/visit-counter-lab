# 1단계: Gradle로 JAR 빌드
# Gradle 8.14 + JDK 21 이미지를 빌드 전용 단계로 쓰고, builder 라는 이름을 붙인다
FROM gradle:8.14-jdk21 AS builder
# 이후 명령이 실행될 작업 디렉터리를 /build 로 정한다(없으면 만든다)
WORKDIR /build
# 빌드 설정 파일만 먼저 복사한다. 소스가 바뀌어도 아래 의존성 레이어는 캐시를 재사용한다
COPY settings.gradle build.gradle ./
# 의존성만 미리 내려받아 별도 레이어로 캐시한다(출력은 버린다)
RUN gradle dependencies --no-daemon > /dev/null
# 애플리케이션 소스를 복사한다
COPY src ./src
# 실행 가능한 Spring Boot JAR 를 만든다(컨테이너에서는 Gradle 데몬이 필요 없다)
RUN gradle bootJar --no-daemon
# 2단계: JRE만 포함한 경량 실행 이미지
# 실행에는 JDK·Gradle 이 필요 없으므로 JRE 21 이미지에서 새로 시작한다
FROM eclipse-temurin:21-jre
# 실행 단계의 작업 디렉터리를 /app 으로 정한다
WORKDIR /app
# builder 단계에서 만든 JAR 만 가져와 app.jar 라는 이름으로 둔다
COPY --from=builder /build/build/libs/visit-counter-1.0.0.jar \
    app.jar
# 시크릿을 환경 변수로 옮겨 주는 시작 스크립트를 복사한다
COPY docker-entrypoint.sh /docker-entrypoint.sh
# 스크립트에 실행 권한을 준다
RUN chmod +x /docker-entrypoint.sh
# root 대신 쓸 시스템 그룹 app 과, 홈 디렉터리 없는 시스템 계정 app 을 만든다
RUN groupadd --system app && \
    useradd --system --gid app --no-create-home app
# 이후 명령과 컨테이너 프로세스를 app 계정으로 실행한다
USER app
# 컨테이너가 8080 포트를 쓴다고 문서화한다
EXPOSE 8080
# 항상 먼저 실행될 진입점: 시크릿을 읽은 뒤 CMD 를 exec 로 실행한다
ENTRYPOINT ["/docker-entrypoint.sh"]
# ENTRYPOINT 에 인자로 넘어갈 기본 명령: JAR 실행
CMD ["java", "-jar", "app.jar"]
