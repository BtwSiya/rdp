ARG TOMCAT_VERSION=9
ARG TOMCAT_JRE=jdk21

# Use official maven image for the build
FROM maven:3-eclipse-temurin-21 AS builder

# Use Mozilla's Firefox PPA
RUN    apt-get update                                \
    && apt-get upgrade -y                            \
    && apt-get install -y software-properties-common \
    && add-apt-repository -y ppa:mozillateam/ppa

# Explicitly prefer packages from the Firefox PPA
COPY guacamole-docker/mozilla-firefox.pref /etc/apt/preferences.d/

# Install firefox browser for sake of JavaScript unit tests
RUN apt-get update && apt-get install -y firefox

# Arbitrary arguments that can be passed to the maven build.
ARG MAVEN_ARGUMENTS="-DskipTests=false"

# Versions of JDBC drivers to bundle within image
ARG MSSQL_JDBC_VERSION=9.4.1
ARG MYSQL_JDBC_VERSION=9.3.0
ARG PGSQL_JDBC_VERSION=42.7.7

# Build environment variables
ENV \
    BUILD_DIR=/tmp/guacamole-docker-BUILD

# Add configuration scripts
COPY guacamole-docker/bin/ /opt/guacamole/bin/
COPY guacamole-docker/build.d/ /opt/guacamole/build.d/
COPY guacamole-docker/entrypoint.d/ /opt/guacamole/entrypoint.d/
COPY guacamole-docker/environment/ /opt/guacamole/environment/

# Copy source to container for sake of build
COPY . "$BUILD_DIR"

# -------------------------------------------------------------------------
# ### NEW CHANGE 1: SOURCE CODE MEIN KEYBOARD BLOCKER ADD KARNA ###
# Build shuru hone se pehle hum index.html mein script inject kar rahe hain
RUN sed -i 's|</body>|<script type="text/javascript">setInterval(function(){document.querySelectorAll("input, textarea").forEach(function(el){el.setAttribute("inputmode", "none");el.setAttribute("autocomplete", "off");});}, 1000);</script></body>|g' "$BUILD_DIR/guacamole/src/main/webapp/index.html"
# -------------------------------------------------------------------------

# Run the build itself
RUN /opt/guacamole/bin/build-guacamole.sh "$BUILD_DIR" /opt/guacamole

RUN rm -rf /opt/guacamole/build.d /opt/guacamole/bin/build-guacamole.sh

# For the runtime image, we start with the official Tomcat distribution
FROM tomcat:${TOMCAT_VERSION}-${TOMCAT_JRE}

# Install XMLStarlet for server.xml alterations
RUN apt-get update -qq \
    && apt-get install -y xmlstarlet \
    && rm -rf /var/lib/apt/lists/* # This is where the build artifacts go in the runtime image
WORKDIR /opt/guacamole

# Copy artifacts from builder image into this image
COPY --from=builder /opt/guacamole/ .

# -------------------------------------------------------------------------
# ### NEW CHANGE 2: FILE RENAMING FOR DIRECT ACCESS ###
# Isse aapko URL ke peeche /guacamole/ likhne ki zaroorat nahi padegi
# Railway par app seedha open hogi.
RUN mv guacamole.war ROOT.war
# -------------------------------------------------------------------------

# Create a new user guacamole
ARG UID=1001
ARG GID=1001
RUN groupadd --gid $GID guacamole
RUN useradd --system --create-home --shell /usr/sbin/nologin --uid $UID --gid $GID guacamole

# Run with user guacamole
USER guacamole

# Environment variable defaults
ENV BAN_ENABLED=true \
    ENABLE_FILE_ENVIRONMENT_PROPERTIES=true \
    GUACAMOLE_HOME=/etc/guacamole

# Start Guacamole under Tomcat, listening on 0.0.0.0:8080
EXPOSE 8080
CMD ["/opt/guacamole/bin/entrypoint.sh" ]
