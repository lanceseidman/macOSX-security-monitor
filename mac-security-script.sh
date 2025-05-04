#!/bin/bash

# macOS Sonoma Security Script
# This script provides:
# 1. Camera photo capture
# 2. Remote photo upload
# 3. Remote management capabilities

# ======== Configuration ========
# Directory to store photos
PHOTO_DIR="$HOME/.security/photos"
# Log file location
LOG_FILE="$HOME/.security/security.log"
# Remote server details (change these)
REMOTE_USER="your-username"
REMOTE_SERVER="your-server.com"
REMOTE_DIR="/home/$REMOTE_USER/security"
# How often to take photos (in seconds)
CAPTURE_INTERVAL=300
# Email for notifications
NOTIFICATION_EMAIL="your-email@example.com"

# ======== Ensure Dependencies ========
install_dependencies() {
    echo "Checking and installing dependencies..."
    
    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Install ImageSnap for camera capture
    if ! command -v imagesnap &> /dev/null; then
        echo "Installing ImageSnap..."
        brew install imagesnap
    fi
    
    # Create necessary directories
    mkdir -p "$PHOTO_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    echo "Dependencies installed successfully."
}

# ======== Camera Functions ========
take_photo() {
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local filename="$PHOTO_DIR/security-$timestamp.jpg"
    
    # Log the attempt
    echo "$(date): Attempting to capture photo..." >> "$LOG_FILE"
    
    # Take the photo with ImageSnap - wait 1 second for camera to warm up
    if imagesnap -w 1 "$filename"; then
        echo "$(date): Photo captured successfully: $filename" >> "$LOG_FILE"
        echo "$filename"
    else
        echo "$(date): Failed to capture photo" >> "$LOG_FILE"
        return 1
    fi
}

# ======== Remote Upload Functions ========
upload_photo() {
    local photo_path="$1"
    local photo_name=$(basename "$photo_path")
    
    # Log the attempt
    echo "$(date): Attempting to upload photo: $photo_name..." >> "$LOG_FILE"
    
    # Upload the photo using scp
    if scp -q "$photo_path" "$REMOTE_USER@$REMOTE_SERVER:$REMOTE_DIR/$photo_name"; then
        echo "$(date): Photo uploaded successfully: $photo_name" >> "$LOG_FILE"
        
        # Send notification email
        send_notification "Security Photo Uploaded" "A new security photo ($photo_name) has been uploaded."
        return 0
    else
        echo "$(date): Failed to upload photo: $photo_name" >> "$LOG_FILE"
        return 1
    fi
}

# ======== Notification Functions ========
send_notification() {
    local subject="$1"
    local message="$2"
    
    echo "$(date): Sending notification: $subject" >> "$LOG_FILE"
    echo "$message" | mail -s "$subject" "$NOTIFICATION_EMAIL"
}

# ======== Remote Management Functions ========
setup_remote_management() {
    echo "Setting up remote management..."
    
    # Enable Remote Management (formerly Apple Remote Desktop)
    echo "Enabling Remote Management..."
    sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
        -activate -configure -access -on \
        -clientopts -setvnclegacy -vnclegacy yes \
        -clientopts -setvncpw -vncpw "your-secure-password-here" \
        -restart -agent -privs -all
    
    # Enable SSH remote login
    echo "Enabling SSH remote login..."
    sudo systemsetup -setremotelogin on
    
    echo "Remote management setup complete."
}

# ======== User Verification Function ========
verify_user() {
    # Take a photo when user logs in
    local photo_path=$(take_photo)
    
    if [ -n "$photo_path" ]; then
        # Upload the photo for verification
        upload_photo "$photo_path"
        
        # Log the verification attempt
        echo "$(date): User verification photo captured and uploaded." >> "$LOG_FILE"
    else
        echo "$(date): Failed to capture user verification photo." >> "$LOG_FILE"
    fi
}

# ======== Main Service Function ========
start_monitoring_service() {
    echo "Starting security monitoring service..."
    
    # Create a LaunchAgent plist to run this script at login
    cat > "$HOME/Library/LaunchAgents/com.security.monitor.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.security.monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$(realpath "$0")</string>
        <string>run_service</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>$HOME/.security/error.log</string>
    <key>StandardOutPath</key>
    <string>$HOME/.security/output.log</string>
</dict>
</plist>
EOF
    
    # Load the LaunchAgent
    launchctl load "$HOME/Library/LaunchAgents/com.security.monitor.plist"
    
    echo "Security monitoring service started."
}

run_service() {
    # Service is running
    echo "$(date): Security monitoring service started" >> "$LOG_FILE"
    
    # Main monitoring loop
    while true; do
        # Take photo
        local photo_path=$(take_photo)
        
        # Upload if successful
        if [ -n "$photo_path" ]; then
            upload_photo "$photo_path"
        fi
        
        # Wait for next interval
        sleep "$CAPTURE_INTERVAL"
    done
}

# ======== Login Hook ========
setup_login_hook() {
    echo "Setting up login hook for user verification..."
    
    # Create the login hook script
    cat > "$HOME/.security/login-hook.sh" << EOF
#!/bin/bash
# This script runs when a user logs in
"$(realpath "$0")" verify_user
EOF
    
    # Make it executable
    chmod +x "$HOME/.security/login-hook.sh"
    
    # Set as login hook
    sudo defaults write com.apple.loginwindow LoginHook "$HOME/.security/login-hook.sh"
    
    echo "Login hook setup complete."
}

# ======== Script Execution ========
# Check arguments
if [ $# -eq 0 ]; then
    echo "MacOS Sonoma Security Script"
    echo "-----------------------------"
    echo "Usage: $0 [command]"
    echo "Commands:"
    echo "  install          - Install dependencies and setup"
    echo "  start            - Start the security monitoring service"
    echo "  take_photo       - Take a single photo"
    echo "  setup_remote     - Setup remote management"
    echo "  verify_user      - Capture and upload a photo for user verification"
    echo "  run_service      - Run the monitoring service (used internally)"
    exit 0
fi

# Execute the requested command
case "$1" in
    "install")
        install_dependencies
        ;;
    "start")
        start_monitoring_service
        ;;
    "take_photo")
        take_photo
        ;;
    "setup_remote")
        setup_remote_management
        ;;
    "verify_user")
        verify_user
        ;;
    "run_service")
        run_service
        ;;
    *)
        echo "Unknown command: $1"
        exit 1
        ;;
esac

exit 0
