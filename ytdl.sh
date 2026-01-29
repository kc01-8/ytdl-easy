#!/bin/bash
#===============================================================================
# YouTube Downloader - Linux Edition
# Converted from PowerShell with auto-setup, updates, and audio+frame mode
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
# Colors and Printing (ALL go to stderr so they don't interfere with data)
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
            install_packages "${missing[@]}"
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
        print_warning "Optional (for better thumbnails): ${optional_missing[*]}"
    fi
    
    print_success "All required dependencies satisfied"
}

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
            sudo apt-get update
            sudo apt-get install -y "${pkgs[@]}"
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
    
    # First attempt: without cookies (uses mobile clients)
    print_info "Attempting download..."
    if attempt_download "$mode" "$url" "" "$output_template"; then
        return 0
    fi
    
    # Check if cookies are available for retry
    local cookies_file=""
    if cookies_file=$(find_cookies 2>/dev/null); then
        echo
        print_warning "First attempt failed. Retrying with cookies..."
        print_warning "Using cookies: $cookies_file"
        
        if attempt_download "$mode" "$url" "$cookies_file" "$output_template"; then
            return 0
        fi
    fi
    
    # Both attempts failed
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
    
    local -a args=()
    
    # Add cookies or try mobile clients
    if [[ -n "$cookies_file" ]]; then
        args+=('--cookies' "$cookies_file")
    else
        # Try mobile clients first (often less restricted for public videos)
        args+=('--extractor-args' 'youtube:player_client=android,ios,web')
    fi
    
    # Retry options
    args+=(
        '--retries' '10'
        '--fragment-retries' '999'
        '--file-access-retries' '10'
        '--extractor-retries' '5'
    )
    
    if [[ "$mode" == "video" ]]; then
        # Video-specific args
        args+=(
            '-f' 'bestvideo*+bestaudio/best'
            '-S' 'res,ext:mp4:m4a'
            '--recode' 'mp4'
            '--embed-thumbnail'
            '--embed-chapters'
            '--embed-subs'
            '--sub-langs' 'en'
            '--write-auto-subs'
            '--abort-on-unavailable-fragment'
        )
    else
        # Audio-specific args
        args+=(
            '-f' 'bestaudio*/best'
            '-S' 'ext:m4a:mp3:ogg'
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

download_audio_with_frame() {
    local url="$1"
    
    print_header "AUDIO + SINGLE FRAME VIDEO"
    print_info "This mode saves space by using one frame for the entire video"
    echo
    
    # Create temp directory
    local temp_dir
    temp_dir=$(mktemp -d -t ytdl_XXXXXX)
    
    # Setup cleanup trap
    trap "rm -rf '$temp_dir'" RETURN
    
    print_info "Working directory: $temp_dir"
    
    #---------------------------------------------------------------------------
    # Step 1: Get video metadata
    #---------------------------------------------------------------------------
    print_info "Fetching video information..."
    
    local video_info=""
    local cookies_file=""
    
    # Try without cookies first
    video_info=$("$YTDLP_BIN" --extractor-args 'youtube:player_client=android,ios,web' -j "$url" 2>/dev/null) || {
        # Retry with cookies
        if cookies_file=$(find_cookies 2>/dev/null); then
            print_warning "Retrying with cookies..."
            video_info=$("$YTDLP_BIN" --cookies "$cookies_file" -j "$url" 2>/dev/null) || {
                print_error "Failed to fetch video info"
                return 1
            }
        else
            print_error "Failed to fetch video info"
            return 1
        fi
    }
    
    local video_title duration uploader upload_date description
    video_title=$(echo "$video_info" | jq -r '.title // "video"')
    duration=$(echo "$video_info" | jq -r '.duration // 0')
    uploader=$(echo "$video_info" | jq -r '.uploader // ""')
    upload_date=$(echo "$video_info" | jq -r '.upload_date // ""')
    description=$(echo "$video_info" | jq -r '.description // ""' | head -c 2000)
    
    local safe_title
    safe_title=$(sanitize_filename "$video_title")
    
    echo "  Title:    $video_title"
    echo "  Duration: ${duration}s"
    echo "  Uploader: $uploader"
    echo
    
    #---------------------------------------------------------------------------
    # Step 2: Download audio (with fallback)
    #---------------------------------------------------------------------------
    print_info "Downloading audio track..."
    
    if ! download_with_fallback "audio" "$url" "$temp_dir/audio.%(ext)s"; then
        print_error "Failed to download audio"
        return 1
    fi
    
    local audio_file
    audio_file=$(find "$temp_dir" -name 'audio.*' -type f | head -1)
    
    if [[ -z "$audio_file" || ! -f "$audio_file" ]]; then
        print_error "Failed to download audio - no file found"
        return 1
    fi
    print_success "Audio downloaded: $(basename "$audio_file")"
    
    #---------------------------------------------------------------------------
    # Step 3: Download thumbnail
    #---------------------------------------------------------------------------
    print_info "Downloading thumbnail..."
    
    "$YTDLP_BIN" \
        --extractor-args 'youtube:player_client=android,ios,web' \
        --write-thumbnail \
        --skip-download \
        --convert-thumbnails jpg \
        -o "$temp_dir/thumbnail" \
        "$url" 2>/dev/null || true
    
    local thumb_file
    thumb_file=$(find "$temp_dir" -name 'thumbnail*.jpg' -type f 2>/dev/null | head -1)
    
    # Also check for webp that wasn't converted
    if [[ -z "$thumb_file" || ! -f "$thumb_file" ]]; then
        thumb_file=$(find "$temp_dir" -name 'thumbnail*.webp' -type f 2>/dev/null | head -1)
        if [[ -n "$thumb_file" && -f "$thumb_file" ]]; then
            local jpg_thumb="$temp_dir/thumbnail.jpg"
            ffmpeg -y -i "$thumb_file" "$jpg_thumb" 2>/dev/null && thumb_file="$jpg_thumb"
        fi
    fi
    
    # Fallback: create a black frame
    if [[ -z "$thumb_file" || ! -f "$thumb_file" ]]; then
        print_warning "No thumbnail found, creating placeholder..."
        thumb_file="$temp_dir/thumbnail.jpg"
        ffmpeg -y -f lavfi -i color=c=black:s=1920x1080:d=1 \
            -vframes 1 -q:v 2 "$thumb_file" 2>/dev/null
    else
        print_success "Thumbnail downloaded"
    fi
    
    #---------------------------------------------------------------------------
    # Step 4: Download subtitles
    #---------------------------------------------------------------------------
    print_info "Downloading subtitles..."
    
    "$YTDLP_BIN" \
        --extractor-args 'youtube:player_client=android,ios,web' \
        --write-subs \
        --write-auto-subs \
        --sub-langs en \
        --sub-format 'srt/vtt/best' \
        --convert-subs srt \
        --skip-download \
        -o "$temp_dir/subs" \
        "$url" 2>/dev/null || true
    
    local subs_file
    subs_file=$(find "$temp_dir" -name 'subs*.srt' -type f 2>/dev/null | head -1)
    
    if [[ -n "$subs_file" && -f "$subs_file" ]]; then
        print_success "Subtitles downloaded"
    else
        print_warning "No subtitles available"
        subs_file=""
    fi
    
    #---------------------------------------------------------------------------
    # Step 5: Extract chapters
    #---------------------------------------------------------------------------
    print_info "Processing chapters..."
    
    local chapters_file=""
    local has_chapters
    has_chapters=$(echo "$video_info" | jq 'has("chapters") and (.chapters | length > 0)')
    
    if [[ "$has_chapters" == "true" ]]; then
        chapters_file="$temp_dir/chapters.ffmeta"
        {
            echo ";FFMETADATA1"
            echo "title=$video_title"
            [[ -n "$uploader" ]] && echo "artist=$uploader"
            echo ""
            echo "$video_info" | jq -r '
                .chapters[] | 
                "[CHAPTER]\nTIMEBASE=1/1000\nSTART=\((.start_time * 1000) | floor)\nEND=\((.end_time * 1000) | floor)\ntitle=\(.title // "Chapter")\n"
            '
        } > "$chapters_file"
        print_success "Chapters extracted: $(echo "$video_info" | jq '.chapters | length') chapters"
    else
        print_warning "No chapters available"
    fi
    
    #---------------------------------------------------------------------------
    # Step 6: Create single-frame video with ffmpeg
    #---------------------------------------------------------------------------
    print_info "Creating optimized video file..."
    
    local download_dir
    download_dir=$(get_config_value "DownloadDir")
    local output_file="$download_dir/${safe_title}_audio.mp4"
    
    # Ensure unique filename
    local counter=1
    while [[ -f "$output_file" ]]; do
        output_file="$download_dir/${safe_title}_audio_${counter}.mp4"
        ((counter++))
    done
    
    # Build ffmpeg command dynamically
    local -a ffmpeg_inputs=()
    local -a ffmpeg_maps=()
    local -a ffmpeg_codecs=()
    local input_idx=0
    
    # Input 0: thumbnail as video source (looped)
    ffmpeg_inputs+=(-loop 1 -framerate 1 -i "$thumb_file")
    ffmpeg_maps+=(-map "${input_idx}:v")
    ((input_idx++))
    
    # Input 1: audio
    ffmpeg_inputs+=(-i "$audio_file")
    ffmpeg_maps+=(-map "${input_idx}:a")
    ((input_idx++))
    
    # Input 2: chapters metadata (optional)
    local metadata_input=""
    if [[ -n "$chapters_file" && -f "$chapters_file" ]]; then
        ffmpeg_inputs+=(-i "$chapters_file")
        metadata_input="-map_metadata $input_idx"
        ((input_idx++))
    fi
    
    # Input 3: subtitles (optional)
    if [[ -n "$subs_file" && -f "$subs_file" ]]; then
        ffmpeg_inputs+=(-i "$subs_file")
        ffmpeg_maps+=(-map "${input_idx}:s?")
        ffmpeg_codecs+=(-c:s mov_text)
        ((input_idx++))
    fi
    
    # Video codec: ultra-compressed static image
    ffmpeg_codecs+=(
        -c:v libx264
        -tune stillimage
        -crf 51
        -preset ultrafast
        -pix_fmt yuv420p
    )
    
    # Audio codec: high quality AAC
    ffmpeg_codecs+=(
        -c:a aac
        -b:a 192k
    )
    
    # Metadata
    local -a metadata_args=(
        -metadata "title=$video_title"
    )
    [[ -n "$uploader" ]] && metadata_args+=(-metadata "artist=$uploader")
    [[ -n "$upload_date" ]] && metadata_args+=(-metadata "date=$upload_date")
    [[ -n "$description" ]] && metadata_args+=(-metadata "comment=${description:0:500}")
    
    # Run ffmpeg
    print_info "Encoding with ffmpeg (this may take a moment)..."
    
    # shellcheck disable=SC2086
    ffmpeg -y \
        "${ffmpeg_inputs[@]}" \
        "${ffmpeg_maps[@]}" \
        $metadata_input \
        "${ffmpeg_codecs[@]}" \
        "${metadata_args[@]}" \
        -shortest \
        -movflags +faststart \
        -loglevel warning \
        -stats \
        "$output_file"
    
    #---------------------------------------------------------------------------
    # Step 7: Embed thumbnail as cover art
    #---------------------------------------------------------------------------
    if [[ -f "$thumb_file" ]]; then
        print_info "Embedding thumbnail as cover art..."
        
        local temp_output="$temp_dir/final.mp4"
        
        if ffmpeg -y \
            -i "$output_file" \
            -i "$thumb_file" \
            -map 0 -map 1 \
            -c copy \
            -disposition:v:0 default \
            -disposition:v:1 attached_pic \
            -loglevel warning \
            "$temp_output" 2>/dev/null; then
            mv "$temp_output" "$output_file"
            print_success "Cover art embedded"
        else
            print_warning "Could not embed cover art (file still valid)"
        fi
    fi
    
    #---------------------------------------------------------------------------
    # Done!
    #---------------------------------------------------------------------------
    echo
    print_success "Download complete!"
    echo
    echo "  Output: $output_file"
    echo "  Size:   $(du -h "$output_file" | cut -f1)"
    echo
    
    # Show space savings estimate
    local audio_size video_estimate
    audio_size=$(stat -c%s "$audio_file" 2>/dev/null || stat -f%z "$audio_file" 2>/dev/null || echo "0")
    video_estimate=$((audio_size * 3))  # Rough estimate: video usually 3x audio
    local final_size
    final_size=$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null || echo "0")
    
    if [[ $video_estimate -gt 0 && $final_size -gt 0 ]]; then
        local savings=$(( (video_estimate - final_size) * 100 / video_estimate ))
        [[ $savings -gt 0 ]] && print_info "Estimated space savings: ~${savings}% vs full video"
    fi
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
    echo -e "${CYAN}│${NC}  ${GREEN}2)${NC} ${BOLD}AUDIO+${NC}   ${WHITE}(AUDIO + SINGLE FRAME)${NC}     ${CYAN}│${NC}"
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
                download_video "$url"
                ;;
            2)
                url=$(get_url)
                update_ytdlp
                download_audio_with_frame "$url"
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
        download_video "$1"
        ;;
    *)
        main
        ;;
esac
