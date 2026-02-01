#!/bin/bash
#===============================================================================
# YouTube Downloader - yt-dlp made easy
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
YTDLP_BIN="$SCRIPT_DIR/yt-dlp"

# Desktop entry location
DESKTOP_FILE="$HOME/.local/share/applications/${SCRIPT_NAME}.desktop"

#-------------------------------------------------------------------------------
# Colors and Printing
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

print_error()   { echo -e "${RED}✗ $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✓ $1${NC}" >&2; }
print_warning() { echo -e "${YELLOW}! $1${NC}" >&2; }
print_info()    { echo -e "${BLUE}→ $1${NC}" >&2; }
print_header()  { echo -e "\n${BOLD}${CYAN}═══ $1 ═══${NC}\n" >&2; }

#-------------------------------------------------------------------------------
# Utility Functions
#-------------------------------------------------------------------------------
command_exists() {
    command -v "$1" &>/dev/null
}

python_module_exists() {
    python3 -c "import $1" 2>/dev/null
}

get_config_value() {
    local key="$1"
    if [[ -f "$CONFIG_FILE" ]]; then
        jq -r ".$key // empty" "$CONFIG_FILE" 2>/dev/null || echo ""
    fi
}

set_config_value() {
    local key="$1"
    local value="$2"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        local temp
        temp=$(mktemp)
        jq ".$key = \"$value\"" "$CONFIG_FILE" > "$temp" && mv "$temp" "$CONFIG_FILE"
    else
        echo "{\"$key\": \"$value\"}" > "$CONFIG_FILE"
    fi
}

find_cookies() {
    local download_dir
    download_dir=$(get_config_value "DownloadDir")
    
    for dir in "$SCRIPT_DIR" "$download_dir"; do
        if [[ -n "$dir" && -f "$dir/cookies.txt" ]]; then
            echo "$dir/cookies.txt"
            return 0
        fi
    done
    return 1
}

sanitize_filename() {
    echo "$1" | tr -cd '[:alnum:] ._-' | tr ' ' '_' | head -c 200
}

#-------------------------------------------------------------------------------
# Dependency Management
#-------------------------------------------------------------------------------
detect_package_manager() {
    if command_exists pacman; then
        echo "pacman"
    elif command_exists apt-get; then
        echo "apt"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists zypper; then
        echo "zypper"
    elif command_exists apk; then
        echo "apk"
    elif command_exists brew; then
        echo "brew"
    else
        echo "unknown"
    fi
}

get_mutagen_package_name() {
    local pm
    pm=$(detect_package_manager)
    
    case "$pm" in
        pacman)
            echo "python-mutagen"
            ;;
        apt|dnf|zypper)
            echo "python3-mutagen"
            ;;
        apk)
            echo "py3-mutagen"
            ;;
        brew)
            echo "mutagen"
            ;;
        *)
            echo "python3-mutagen"
            ;;
    esac
}

get_nodejs_package_name() {
    local pm
    pm=$(detect_package_manager)
    
    case "$pm" in
        brew)
            echo "node"
            ;;
        *)
            echo "nodejs"
            ;;
    esac
}

check_dependencies() {
    print_header "CHECKING DEPENDENCIES"
    
    local missing=()
    local optional_missing=()
    
    # Required
    for cmd in curl ffmpeg jq; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        else
            print_success "$cmd found"
        fi
    done
    
    # Check for Node.js (required for YouTube JS challenges)
    if command_exists node; then
        print_success "nodejs found"
    else
        local nodejs_pkg
        nodejs_pkg=$(get_nodejs_package_name)
        missing+=("$nodejs_pkg")
    fi
    
    # Check for mutagen (required for proper metadata embedding)
    if python_module_exists "mutagen"; then
        print_success "mutagen found"
    else
        local mutagen_pkg
        mutagen_pkg=$(get_mutagen_package_name)
        missing+=("$mutagen_pkg")
    fi
    
    # Optional but recommended
    if ! command_exists atomicparsley; then
        optional_missing+=("atomicparsley")
    fi
    
    # Handle missing required deps
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo
        print_warning "Missing required dependencies: ${missing[*]}"
        echo
        
        read -rp "Attempt automatic installation? [Y/n]: " response
        if [[ ! "$response" =~ ^[Nn] ]]; then
            if ! install_packages "${missing[@]}"; then
                echo
                print_error "Automatic installation failed"
                echo
                echo "Please install manually:"
                echo "  sudo apt install ${missing[*]}"
                echo "  # or for your package manager"
                echo
                echo "If apt-get update fails, you may have broken repositories."
                echo "Try: sudo apt-get update --fix-missing"
                echo "Or remove problematic repos from /etc/apt/sources.list.d/"
                echo
                read -rp "Continue anyway? [y/N]: " continue_anyway
                if [[ ! "$continue_anyway" =~ ^[Yy] ]]; then
                    exit 1
                fi
            fi
        else
            print_error "Cannot continue without: ${missing[*]}"
            echo
            echo "Install manually using your package manager:"
            echo "  Debian/Ubuntu: sudo apt install ${missing[*]}"
            echo "  Fedora:        sudo dnf install ${missing[*]}"
            echo "  Arch:          sudo pacman -S ${missing[*]}"
            echo "  macOS:         brew install ${missing[*]}"
            exit 1
        fi
    fi
    
    # Notify about optional deps
    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        print_warning "Optional (fallback for thumbnails): ${optional_missing[*]}"
    fi
    
    print_success "All required dependencies satisfied"
}

install_packages() {
    local pkgs=("$@")
    local pm
    pm=$(detect_package_manager)
    
    print_info "Using package manager: $pm"
    
    case "$pm" in
        pacman)
            sudo pacman -Sy --noconfirm "${pkgs[@]}"
            ;;
        apt)
            # Try update but don't fail if it has errors (broken repos)
            print_info "Updating package lists..."
            if ! sudo apt-get update 2>&1; then
                print_warning "apt-get update had errors (possibly broken repos)"
                print_info "Attempting to install packages anyway..."
            fi
            # Try to install - this is what actually matters
            if ! sudo apt-get install -y "${pkgs[@]}"; then
                print_error "Failed to install packages"
                return 1
            fi
            ;;
        dnf)
            sudo dnf install -y "${pkgs[@]}"
            ;;
        zypper)
            sudo zypper install -y "${pkgs[@]}"
            ;;
        apk)
            sudo apk add "${pkgs[@]}"
            ;;
        brew)
            brew install "${pkgs[@]}"
            ;;
        *)
            print_error "No supported package manager found"
            print_info "Please install manually: ${pkgs[*]}"
            return 1
            ;;
    esac
}

#-------------------------------------------------------------------------------
# yt-dlp Management
#-------------------------------------------------------------------------------
ensure_ytdlp() {
    if [[ ! -f "$YTDLP_BIN" ]]; then
        print_header "INSTALLING YT-DLP"
        print_info "Downloading latest yt-dlp..."
        
        local url="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
        
        if curl -L --progress-bar "$url" -o "$YTDLP_BIN"; then
            chmod +x "$YTDLP_BIN"
            print_success "yt-dlp installed successfully"
            "$YTDLP_BIN" --version
        else
            print_error "Failed to download yt-dlp"
            echo "You can manually download it from:"
            echo "  https://github.com/yt-dlp/yt-dlp/releases"
            exit 1
        fi
    fi
}

update_ytdlp() {
    print_info "Checking for yt-dlp updates..."
    "$YTDLP_BIN" -U 2>&1 || true
    echo
}

# Get common yt-dlp args including JS runtime fix
get_common_ytdlp_args() {
    local -a args=()
    
    # Fix JavaScript runtime warning - enable node if available
    if command_exists node; then
        args+=('--js-runtimes' 'node')
    fi
    
    # Retry options
    args+=(
        '--retries' '10'
        '--fragment-retries' '999'
        '--file-access-retries' '10'
        '--extractor-retries' '5'
    )
    
    printf '%s\0' "${args[@]}"
}

#-------------------------------------------------------------------------------
# Alias Management
#-------------------------------------------------------------------------------
get_shell_rc_file() {
    local shell_name
    shell_name=$(basename "$SHELL")
    
    case "$shell_name" in
        bash)
            if [[ -f "$HOME/.bashrc" ]]; then
                echo "$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        zsh)
            echo "$HOME/.zshrc"
            ;;
        fish)
            echo "$HOME/.config/fish/config.fish"
            ;;
        *)
            echo "$HOME/.bashrc"
            ;;
    esac
}

setup_alias() {
    echo
    read -rp "Create terminal alias? [Y/n]: " create_alias
    if [[ "$create_alias" =~ ^[Nn] ]]; then
        return 0
    fi
    
    read -rp "Enter alias name (default: ytdl): " alias_name
    alias_name="${alias_name:-ytdl}"
    
    # Validate alias name
    if [[ ! "$alias_name" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
        print_error "Invalid alias name. Use only letters, numbers, underscores, and hyphens."
        return 1
    fi
    
    local rc_file
    rc_file=$(get_shell_rc_file)
    local shell_name
    shell_name=$(basename "$SHELL")
    
    local alias_line
    local alias_marker="# YouTube Downloader alias"
    
    # Create alias line based on shell type
    if [[ "$shell_name" == "fish" ]]; then
        alias_line="alias $alias_name='$SCRIPT_PATH'"
    else
        alias_line="alias $alias_name='$SCRIPT_PATH'"
    fi
    
    # Check if alias already exists
    if [[ -f "$rc_file" ]] && grep -q "$alias_marker" "$rc_file"; then
        print_warning "Alias already configured in $rc_file"
        read -rp "Update existing alias? [Y/n]: " update_alias
        if [[ "$update_alias" =~ ^[Nn] ]]; then
            return 0
        fi
        # Remove old alias
        local temp_file
        temp_file=$(mktemp)
        grep -v "$alias_marker" "$rc_file" | grep -v "alias.*='$SCRIPT_PATH'" > "$temp_file" || true
        mv "$temp_file" "$rc_file"
    fi
    
    # Ensure rc file exists
    mkdir -p "$(dirname "$rc_file")"
    touch "$rc_file"
    
    # Add alias
    {
        echo ""
        echo "$alias_marker"
        echo "$alias_line"
    } >> "$rc_file"
    
    print_success "Alias '$alias_name' added to $rc_file"
    
    # Save alias name to config
    set_config_value "AliasName" "$alias_name"
    
    echo
    print_warning "To use the alias now, run one of these:"
    echo "  source $rc_file"
    echo "  OR restart your terminal"
    echo
    print_info "Then you can simply type: $alias_name"
}

#-------------------------------------------------------------------------------
# Setup Wizard
#-------------------------------------------------------------------------------
run_setup() {
    print_header "YOUTUBE DOWNLOADER SETUP"
    
    # Check dependencies
    check_dependencies
    
    # Install yt-dlp
    ensure_ytdlp
    
    # Ask for download directory
    echo
    print_info "Configure Download Location"
    echo
    echo "Default location: $SCRIPT_DIR"
    echo
    read -rp "Enter download directory (or press Enter for default): " input_dir
    
    local download_dir
    if [[ -z "$input_dir" ]]; then
        download_dir="$SCRIPT_DIR"
    else
        # Expand ~ and resolve path
        download_dir="${input_dir/#\~/$HOME}"
        download_dir="$(realpath -m "$download_dir" 2>/dev/null || echo "$download_dir")"
    fi
    
    # Create directory
    if [[ ! -d "$download_dir" ]]; then
        print_info "Creating directory: $download_dir"
        if ! mkdir -p "$download_dir"; then
            print_error "Failed to create directory"
            exit 1
        fi
    fi
    
    # Verify writable
    if [[ ! -w "$download_dir" ]]; then
        print_error "Directory is not writable: $download_dir"
        exit 1
    fi
    
    # Save config
    set_config_value "DownloadDir" "$download_dir"
    print_success "Configuration saved"
    
    # Create desktop entry
    echo
    read -rp "Create desktop shortcut? [Y/n]: " create_shortcut
    if [[ ! "$create_shortcut" =~ ^[Nn] ]]; then
        create_desktop_entry
    fi
    
    # Setup terminal alias
    setup_alias
    
    echo
    print_success "Setup complete!"
    print_info "Download directory: $download_dir"
    echo
}

create_desktop_entry() {
    mkdir -p "$(dirname "$DESKTOP_FILE")"
    
    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=YouTube Downloader
Comment=Download videos from YouTube
Exec=bash -c 'cd "\$(dirname "$SCRIPT_PATH")" && "$SCRIPT_PATH"; exec bash'
Icon=video-x-generic
Terminal=true
Categories=AudioVideo;Network;
EOF
    
    chmod +x "$DESKTOP_FILE"
    
    # Update desktop database if available
    if command_exists update-desktop-database; then
        update-desktop-database "$(dirname "$DESKTOP_FILE")" 2>/dev/null || true
    fi
    
    print_success "Desktop shortcut created"
}

#-------------------------------------------------------------------------------
# Download Functions
#-------------------------------------------------------------------------------

# Try download without cookies first, retry with cookies on failure
download_with_fallback() {
    local mode="$1"  # "video" or "audio"
    local url="$2"
    local output_template="${3:-}"
    
    # First attempt: without cookies
    print_info "Attempting download..."
    if attempt_download "$mode" "$url" "" "$output_template" "false"; then
        return 0
    fi
    
    # Second attempt: with cookies if available
    local cookies_file=""
    if cookies_file=$(find_cookies 2>/dev/null); then
        echo
        print_warning "First attempt failed. Retrying with cookies..."
        print_warning "Using cookies: $cookies_file"
        
        if attempt_download "$mode" "$url" "$cookies_file" "$output_template" "false"; then
            return 0
        fi
        
        # Third attempt: cookies + mobile clients as last resort
        echo
        print_warning "Retrying with mobile clients..."
        if attempt_download "$mode" "$url" "$cookies_file" "$output_template" "true"; then
            return 0
        fi
    fi
    
    # All attempts failed
    echo
    print_error "Download failed"
    echo
    echo "Troubleshooting tips:"
    echo "  1. Make sure yt-dlp is up to date (option U)"
    echo "  2. Export fresh cookies from your browser"
    echo "  3. Try again later (YouTube may be rate-limiting)"
    
    return 1
}

attempt_download() {
    local mode="$1"
    local url="$2"
    local cookies_file="${3:-}"
    local output_template="${4:-}"
    local use_mobile="${5:-false}"
    
    # Get common args
    local -a args=()
    while IFS= read -r -d '' arg; do
        args+=("$arg")
    done < <(get_common_ytdlp_args)
    
    # Add cookies if provided
    if [[ -n "$cookies_file" ]]; then
        args+=('--cookies' "$cookies_file")
    fi
    
    # Use mobile clients only as fallback (they often have lower quality)
    if [[ "$use_mobile" == "true" ]]; then
        args+=('--extractor-args' 'youtube:player_client=android,ios,web')
    fi
    
    if [[ "$mode" == "video" ]]; then
        # Video-specific args - prefer highest quality
        args+=(
            '-f' 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best'
            '-S' 'res:2160,res:1440,res:1080,res:720,ext:mp4:m4a'
            '--merge-output-format' 'mp4'
            '--embed-thumbnail'
            '--embed-chapters'
            '--embed-subs'
            '--sub-langs' 'en'
            '--write-auto-subs'
            '--abort-on-unavailable-fragment'
        )
    else
        # Audio-specific args - high quality with all metadata
        args+=(
            '-f' 'bestaudio[ext=m4a]/bestaudio'
            '-S' 'ext:m4a:mp3:ogg'
            '--embed-thumbnail'
            '--embed-metadata'
            '--embed-chapters'
            '--write-subs'
            '--write-auto-subs'
            '--sub-langs' 'en'
            '--convert-subs' 'srt'
        )
    fi
    
    # Output template if specified
    if [[ -n "$output_template" ]]; then
        args+=('-o' "$output_template")
    fi
    
    args+=("$url")
    
    "$YTDLP_BIN" "${args[@]}"
}

download_video() {
    local url="$1"
    
    print_header "DOWNLOADING VIDEO"
    download_with_fallback "video" "$url"
}

download_audio() {
    local url="$1"
    
    print_header "DOWNLOADING AUDIO"
    print_info "High quality audio with embedded metadata, chapters, and thumbnail"
    print_info "Subtitles saved as separate .srt file"
    echo
    
    download_with_fallback "audio" "$url"
}

#-------------------------------------------------------------------------------
# Main Menu
#-------------------------------------------------------------------------------
show_menu() {
    echo
    echo -e "${CYAN}┌─────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}${BOLD}${YELLOW}       YOUTUBE DOWNLOADER - LINUX        ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}1)${NC} ${BOLD}VIDEO${NC}    ${WHITE}(BEST QUALITY MP4)${NC}         ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${GREEN}2)${NC} ${BOLD}AUDIO${NC}    ${WHITE}(BEST QUALITY + METADATA)${NC}  ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}                                         ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${MAGENTA}S)${NC} ${BOLD}SETUP${NC}    ${WHITE}(RECONFIGURE)${NC}              ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${MAGENTA}U)${NC} ${BOLD}UPDATE${NC}   ${WHITE}(UPDATE YT-DLP)${NC}            ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${RED}Q)${NC} ${BOLD}QUIT${NC}                                ${CYAN}│${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────┘${NC}"
    echo
}

get_url() {
    local url
    while true; do
        read -rp "ENTER URL: " url
        if [[ "$url" =~ ^https?:// ]]; then
            echo "$url"
            return 0
        fi
        print_error "INVALID URL. MUST START WITH HTTP:// OR HTTPS://"
    done
}

#-------------------------------------------------------------------------------
# Main Entry Point
#-------------------------------------------------------------------------------
main() {
    # Initial checks
    local download_dir
    download_dir=$(get_config_value "DownloadDir")
    
    # Run setup if first time or missing config
    if [[ -z "$download_dir" ]] || [[ ! -f "$YTDLP_BIN" ]] || [[ ! -d "$download_dir" ]]; then
        run_setup
        download_dir=$(get_config_value "DownloadDir")
    fi
    
    # Main loop
    while true; do
        cd "$download_dir"
        print_info "DOWNLOAD LOCATION: $download_dir"
        
        show_menu
        
        read -rp "SELECT OPTION: " choice
        
        case "$choice" in
            1)
                url=$(get_url)
                update_ytdlp
                download_video "$url" || true
                ;;
            2)
                url=$(get_url)
                update_ytdlp
                download_audio "$url" || true
                ;;
            s|S)
                run_setup
                download_dir=$(get_config_value "DownloadDir")
                ;;
            u|U)
                update_ytdlp
                ;;
            q|Q)
                print_info "GOODBYE!"
                exit 0
                ;;
            *)
                print_error "INVALID OPTION"
                ;;
        esac
        
        echo
        read -rp "PRESS ENTER TO CONTINUE..."
    done
}

# Handle command line arguments
case "${1:-}" in
    --setup|-s)
        run_setup
        ;;
    --update|-u)
        ensure_ytdlp
        update_ytdlp
        ;;
    --help|-h)
        echo "USAGE: $(basename "$0") [OPTIONS] [URL]"
        echo
        echo "OPTIONS:"
        echo "  --setup, -s     RUN SETUP WIZARD"
        echo "  --update, -u    UPDATE YT-DLP"
        echo "  --help, -h      SHOW THIS HELP"
        echo
        echo "IF URL IS PROVIDED, DOWNLOADS DIRECTLY USING VIDEO MODE."
        echo "OTHERWISE, SHOWS INTERACTIVE MENU."
        ;;
    http*)
        # Direct URL provided
        ensure_ytdlp
        download_dir=$(get_config_value "DownloadDir")
        [[ -z "$download_dir" ]] && run_setup && download_dir=$(get_config_value "DownloadDir")
        cd "$download_dir"
        download_video "$1" || true
        ;;
    *)
        main
        ;;
esac
