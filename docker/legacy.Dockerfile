# Builds and runs the unmodified legacy app on a current JDK base.
# The upstream Dockerfile cannot be used as-is: its base image (openjdk:25) no
# longer exists on Docker Hub. See docs/design/03-problems-and-learnings.md (P-4).
#
# Build context must be the upstream/ submodule:
#   docker build -f docker/legacy.Dockerfile -t jpetstore-legacy upstream/
#   docker run -d --name jpetstore-legacy-demo -p 8090:8080 jpetstore-legacy
#   # -> http://localhost:8090/jpetstore/
FROM eclipse-temurin:21-jdk
COPY . /usr/src/myapp
WORKDIR /usr/src/myapp
RUN ./mvnw clean package -DskipTests
EXPOSE 8080
CMD ["./mvnw", "cargo:run", "-P", "tomcat9", "-Dcargo.servlet.port=8080"]
