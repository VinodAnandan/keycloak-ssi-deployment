#!/bin/bash

# Source common env variables
. .env

# Check and create directories
if [ ! -d "$TARGET_DIR" ]; then
    echo "Directory $TARGET_DIR does not exist, creating..."
    mkdir -p "$TARGET_DIR"
    echo "Directory $TARGET_DIR created."
else
    echo "Directory $TARGET_DIR already exists."
fi

if [ ! -d "$TOOLS_DIR" ]; then
    echo "Directory $TOOLS_DIR does not exist, creating..."
    mkdir -p "$TOOLS_DIR"
    echo "Directory $TOOLS_DIR created."
else
    echo "Directory $TOOLS_DIR already exists."
fi

# change to you TARGET_DIR and checkout keycloak
# checkout keycloak
if [ ! -d "$TARGET_DIR/$KC_OID4VCI" ]; then
    echo "Directory $TARGET_DIR/$KC_OID4VCI does not exist, cloning repo..."
    cd $TARGET_DIR && git clone --depth 1 --branch $KC_TARGET_BRANCH https://github.com/adorsys/keycloak-oid4vc.git $TARGET_DIR/$KC_OID4VCI
    echo "Keycloak cloned into $TARGET_DIR/$KC_OID4VCI."
else
    echo "Directory $TARGET_DIR/$KC_OID4VCI already exists."
fi

if [ ! -f "$KC_TRUST_STORE" ]; then
    echo "Generating SSl keys..." && \
    source $WORK_DIR/generate-kc-certs.sh
fi

# change into keycloak directory & build keycloak
if [ ! -f "$TARGET_DIR/$KC_OID4VCI/quarkus/dist/target/keycloak-999.0.0-SNAPSHOT.tar.gz" ]; then
    echo "File $TARGET_DIR/$KC_OID4VCI/quarkus/dist/target/keycloak-999.0.0-SNAPSHOT.tar.gz does not exist, building keycloak..."
    cd $TARGET_DIR/$KC_OID4VCI && $TARGET_DIR/$KC_OID4VCI/mvnw clean install -DskipTests || { echo 'Could not build keycloak' ; exit 1; }
    echo "Keycloak installed"
else
    echo "Keycloak already installed, will skip build."
fi

# Shutdown keycloak if any
# Determine OS platform and shutdown Keycloak if running
OS=$(uname -s)
case "$OS" in
    Linux*|Darwin*)
        keycloak_pid=$(pgrep -f keycloak)
        if [ -n "$keycloak_pid" ]; then
            echo "Keycloak instance found (PID: $keycloak_pid) on $OS. Shutting it down..."
            kill $keycloak_pid
        fi
        ;;
    *)
        echo "This script supports only Linux or macOS."
        ;;
esac

# Change to the tools directory and unpack keycloak
if [ -d "$KC_INSTALL_DIR" ]; then
    echo "Directory KC_INSTALL_DIR exists,  remove it"
    cd $TOOLS_DIR && rm -rf $KC_INSTALL_DIR || { echo 'Could not remove keycloak install' ; exit 1; }
fi

echo "unpacking keycloak ..."
cd $TOOLS_DIR && tar xzf $TARGET_DIR/$KC_OID4VCI/quarkus/dist/target/keycloak-999.0.0-SNAPSHOT.tar.gz || { echo 'Could not unpack keycloak' ; exit 1; }

# Start database container
if [ -z "${KC_DB_OPTS}" ]; then
    echo "Starting the database container"
    docker-compose up -d db || { echo 'Could not start database container' ; exit 1; }
    KC_DB_OPTS="--db postgres --db-url-port $KC_DB_EXPOSED_PORT --db-url-database $KC_DB_NAME --db-username $KC_DB_USERNAME --db-password $KC_DB_PASSWORD"
fi

# Start keycloak with OID4VCI feature
####
# Use org.keycloak.quarkus._private.IDELauncher if you want to debug through keycloak sources
export KEYCLOAK_ADMIN=$KEYCLOAK_ADMIN && export KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD && cd $KC_INSTALL_DIR && bin/kc.sh $KC_START $KC_DB_OPTS --features=oid4vc-vci &
