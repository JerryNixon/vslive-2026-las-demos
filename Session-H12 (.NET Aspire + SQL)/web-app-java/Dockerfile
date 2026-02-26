FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /app
COPY Server.java .
RUN javac Server.java

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/*.class .
COPY static/ static/
EXPOSE 3000
CMD ["java", "Server"]
