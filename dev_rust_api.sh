#!/bin/bash

# Check if the project name parameter is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <project_name>"
    exit 1
fi

# Variables
PROJECT_NAME="$1"
SOURCE_DIR="/var/www/$PROJECT_NAME"
BUILD_DIR="/tmp/$PROJECT_NAME-build"
TARGET_DIR="$SOURCE_DIR/target"
LOG_DIR="/var/log/rust"
RUN_LOG="$LOG_DIR/${PROJECT_NAME}_dev_run.log"
PID_FILE="$LOG_DIR/${PROJECT_NAME}_dev.pid"
BINARY_NAME="$PROJECT_NAME" # Assumes the binary has the same name as the project

# Ensure the log directory exists
mkdir -p $LOG_DIR

# Check if the application is already running and terminate it
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null 2>&1; then
        echo "Stopping currently running $PROJECT_NAME process (PID: $PID)..."
        kill $PID
        sleep 2  # Give some time for the process to terminate
        if ps -p $PID > /dev/null 2>&1; then
            echo "Force killing $PROJECT_NAME process (PID: $PID)..."
            kill -9 $PID
        fi
    fi
    rm -f "$PID_FILE"
else
    echo "No running $PROJECT_NAME process found."
fi

# Cleanup previous build
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

# Copy source code to the temporary build directory
cp -r $SOURCE_DIR $BUILD_DIR

# Navigate to the copied project directory
cd $BUILD_DIR/$PROJECT_NAME || { echo "Failed to navigate to build directory."; exit 1; }

# Ensure a clean target directory
rm -rf $BUILD_DIR/$PROJECT_NAME/target/debug

# Build the Rust project in debug mode for development
echo "Building Rust project: $PROJECT_NAME in debug mode..."
RUST_BACKTRACE=1 cargo build 2>&1 | tee $RUN_LOG

# Check build status
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "Build succeeded for $PROJECT_NAME. Copying build artifacts..."

    # Create target directory if it doesn't exist
    mkdir -p $TARGET_DIR/debug

    # Use rsync to handle locked or missing files
    rsync -av --ignore-errors --exclude '*.rmeta' --exclude '.cargo-lock' $BUILD_DIR/$PROJECT_NAME/target/debug/ $TARGET_DIR/debug/

    echo "Build artifacts copied to $TARGET_DIR."

    # Set required environment variables
    export DB_CONNECTION="mysql"
    export DB_HOST="127.0.0.1"
    export DB_PORT="3306"
    export DB_DATABASE="paymentswitchaggregator_staging"
    export DB_USERNAME="root"
    export DB_PASSWORD="root"

    # Run the built binary
    BINARY_PATH="$TARGET_DIR/debug/$BINARY_NAME"
    if [ -f "$BINARY_PATH" ]; then
        nohup "$BINARY_PATH" > "$RUN_LOG" 2>&1 &
        echo $! > "$PID_FILE"
        echo "Application is running in development mode. Logs are being written to $RUN_LOG."
    else
        echo "Error: Built binary not found at $BINARY_PATH."
        exit 1
    fi
else
    echo "Build failed for $PROJECT_NAME. Check the log file at $RUN_LOG for details."

    # Cleanup build directory
    rm -rf $BUILD_DIR
    exit 1
fi

# Cleanup temporary build directory
rm -rf $BUILD_DIR

exit 0
