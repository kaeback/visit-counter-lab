# 1단계: Gradle로 JAR 빌드
FROM gradle:8.14-jdk21 AS builder
WORKDIR /build
COPY settings.gradle build.gradle ./
RUN gradle dependencies --no-daemon > /dev/null
COPY src ./src
RUN gradle bootJar --no-daemon
# 2단계: JRE만 포함한 경량 실행 이미지
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /build/build/libs/visit-counter-1.0.0.jar \
    app.jar
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
RUN groupadd --system app && \
    useradd --system --gid app --no-create-home app
USER app
EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["java", "-jar", "app.jar"]
