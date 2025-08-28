#!/bin/bash

# Vyges Vivado Docker Build Script
# This script automates the Docker build process with caching and optimization

set -e

# Configuration
IMAGE_NAME="vyges-vivado"
BASE_IMAGE="ubuntu:24.04"
BUILDER_NAME="vyges-builder"
CACHE_DIR="/tmp/.buildx-cache"
LOG_FILE="logs/build-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to get machine information
get_machine_info() {
    echo "=== MACHINE INFORMATION ==="
    echo "Build Start Time: $(date)"
    echo "Hostname: $(hostname)"
    echo "OS: $(lsb_release -d | cut -f2) ($(lsb_release -c | cut -f2))"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "CPU Model: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
    echo "CPU Cores: $(nproc) ($(grep -c '^processor' /proc/cpuinfo) logical)"
    echo "CPU Speed: $(grep 'cpu MHz' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs) MHz"
    echo "Total RAM: $(free -h | grep '^Mem:' | awk '{print $2}')"
    echo "Available RAM: $(free -h | grep '^Mem:' | awk '{print $7}')"
    echo "Storage: $(df -h / | tail -1 | awk '{print $2 " total, " $3 " used, " $4 " available"}')"
    echo "Docker Version: $(docker --version)"
    echo "Buildx Version: $(docker buildx version 2>/dev/null | head -1 || echo 'Not available')"
    echo "========================================"
}

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to log with timestamp
log_with_timestamp() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Function to log build step
log_build_step() {
    local step="$1"
    local start_time=$(date +%s)
    log_with_timestamp "=== BUILD STEP: $step ==="
    echo "$step" > /tmp/build_current_step
    echo "$start_time" > /tmp/build_step_start
}

# Function to log build step completion
log_build_step_complete() {
    local step="$1"
    local end_time=$(date +%s)
    local start_time=$(cat /tmp/build_step_start 2>/dev/null || echo $end_time)
    local duration=$((end_time - start_time))
    local duration_str=$(printf "%02d:%02d:%02d" $((duration/3600)) $(((duration%3600)/60)) $((duration%60)))
    log_with_timestamp "=== COMPLETED: $step (Duration: $duration_str) ==="
    echo "" > /tmp/build_current_step
}

# Function to estimate build time
estimate_build_time() {
    local cpu_cores=$(nproc)
    local ram_gb=$(free -g | grep '^Mem:' | awk '{print $2}')
    local storage_gb=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
    
    echo "=== BUILD TIME ESTIMATION ==="
    echo "Based on your system specifications:"
    echo "- CPU Cores: $cpu_cores"
    echo "- RAM: ${ram_gb}GB"
    echo "- Available Storage: ${storage_gb}GB"
    echo ""
    
    # Base estimates (in minutes)
    local base_time=180  # 3 hours base
    
    # Adjustments based on specs
    if [ "$cpu_cores" -ge 32 ]; then
        local cpu_factor=0.7
        echo "- High CPU count detected: ~30% faster build"
    elif [ "$cpu_cores" -ge 16 ]; then
        local cpu_factor=0.8
        echo "- Good CPU count: ~20% faster build"
    elif [ "$cpu_cores" -ge 8 ]; then
        local cpu_factor=0.9
        echo "- Moderate CPU count: ~10% faster build"
    else
        local cpu_factor=1.2
        echo "- Low CPU count: ~20% slower build"
    fi
    
    if [ "$ram_gb" -ge 64 ]; then
        local ram_factor=0.8
        echo "- High RAM: ~20% faster build"
    elif [ "$ram_gb" -ge 32 ]; then
        local ram_factor=0.9
        echo "- Good RAM: ~10% faster build"
    elif [ "$ram_gb" -ge 16 ]; then
        local ram_factor=1.0
        echo "- Adequate RAM: normal build speed"
    else
        local ram_factor=1.3
        echo "- Low RAM: ~30% slower build (consider increasing swap)"
    fi
    
    if [ "$storage_gb" -ge 500 ]; then
        local storage_factor=0.9
        echo "- High storage: ~10% faster build"
    elif [ "$storage_gb" -ge 200 ]; then
        local storage_factor=1.0
        echo "- Adequate storage: normal build speed"
    else
        local storage_factor=1.2
        echo "- Low storage: ~20% slower build"
    fi
    
    # Calculate estimated time
    local estimated_minutes=$(echo "$base_time * $cpu_factor * $ram_factor * $storage_factor" | bc -l)
    local estimated_hours=$(echo "scale=1; $estimated_minutes / 60" | bc -l)
    
    echo ""
    echo "ESTIMATED BUILD TIME: ${estimated_hours} hours (${estimated_minutes%.*} minutes)"
    echo "========================================"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build Vyges Vivado Docker image with optimization and caching.

OPTIONS:
    -c, --clean          Clean build (no cache)
    -p, --pull           Force pull base image
    -b, --builder NAME   Custom builder name (default: vyges-builder)
    -i, --image NAME     Custom image name (default: vyges-vivado)
    -l, --log FILE       Custom log file (default: build-YYYYMMDD-HHMMSS.log)
    -s, --no-save        Skip automatic image export
    -h, --help           Show this help message
    --progress           Show current build progress (use in another terminal)

EXAMPLES:
    # Standard build with caching
    $0

    # Clean build (no cache)
    $0 -c

    # Force pull base image
    $0 -p

    # Custom image name
    $0 -i my-vivado-image

    # Custom builder and image
    $0 -b my-builder -i my-image

    # Monitor build progress (in another terminal)
    $0 --progress

    # View build logs
    tail -f logs/build-*.log
EOF
}

# Parse command line arguments
CLEAN_BUILD=false
FORCE_PULL=false
SKIP_SAVE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -p|--pull)
            FORCE_PULL=true
            shift
            ;;
        -b|--builder)
            BUILDER_NAME="$2"
            shift 2
            ;;
        -i|--image)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -s|--no-save)
            SKIP_SAVE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        --progress)
            show_build_progress
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log_build_step "Checking Prerequisites"
    
    # Check if Docker is available and working
    if ! command -v docker > /dev/null 2>&1; then
        print_error "Docker command not found. Please install Docker and try again."
        exit 1
    fi
    
    log_with_timestamp "Docker command found at: $(which docker)"
    
    # Check if Docker daemon is accessible
    log_with_timestamp "Testing Docker daemon connection..."
    if ! docker info > /dev/null 2>&1; then
        print_error "Cannot connect to Docker daemon. Please check:"
        print_error "1. Docker service is running: sudo systemctl status docker"
        print_error "2. User has Docker permissions: sudo usermod -aG docker $USER"
        print_error "3. Docker socket permissions: ls -la /var/run/docker.sock"
        exit 1
    fi
    
    # Check Docker version
    DOCKER_VERSION=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    log_with_timestamp "Docker version: $DOCKER_VERSION"
    
    # Check if buildx is available
    if ! docker buildx version > /dev/null 2>&1; then
        log_with_timestamp "Buildx not available. Using standard docker build."
        USE_BUILDX=false
    else
        log_with_timestamp "Buildx available: $(docker buildx version | head -1)"
        USE_BUILDX=true
    fi
    
    # Check if vivado-installer directory exists
    if [ ! -d "vivado-installer" ]; then
        print_error "vivado-installer directory not found. Please run download-installer.sh first."
        exit 1
    fi
    
    # Check if installer files exist
    if [ ! -f "vivado-installer/FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145.tar" ]; then
        log_with_timestamp "Vivado installer not found. Build may fail if installer is missing."
    fi
    
    log_build_step_complete "Checking Prerequisites"
}

# Function to check and pull base image
check_base_image() {
    log_build_step "Checking Base Image"
    log_with_timestamp "Checking base image: $BASE_IMAGE"
    
    if [ "$FORCE_PULL" = true ]; then
        log_with_timestamp "Force pulling base image..."
        docker pull "$BASE_IMAGE"
        log_with_timestamp "Base image pulled successfully"
        log_build_step_complete "Checking Base Image"
        return
    fi
    
    if docker images "$BASE_IMAGE" | grep -q "$BASE_IMAGE"; then
        log_with_timestamp "Base image already exists locally"
        log_with_timestamp "Image details:"
        docker images "$BASE_IMAGE" | tee -a "$LOG_FILE"
    else
        log_with_timestamp "Base image not found. Pulling..."
        docker pull "$BASE_IMAGE"
        log_with_timestamp "Base image pulled successfully"
    fi
    
    log_build_step_complete "Checking Base Image"
}

# Function to setup buildx builder
setup_builder() {
    log_build_step "Setting Up Buildx Builder"
    
    if [ "$USE_BUILDX" = false ]; then
        log_with_timestamp "Skipping buildx setup (not available)"
        log_build_step_complete "Setting Up Buildx Builder"
        return
    fi
    
    log_with_timestamp "Setting up buildx builder: $BUILDER_NAME"
    
    # Check if builder already exists
    if docker buildx ls | grep -q "$BUILDER_NAME"; then
        log_with_timestamp "Builder already exists. Using existing builder..."
        docker buildx use "$BUILDER_NAME"
    else
        log_with_timestamp "Creating new builder: $BUILDER_NAME"
        docker buildx create --name "$BUILDER_NAME" --use
    fi
    
    # Verify builder is active
    ACTIVE_BUILDER=$(docker buildx ls | grep '*' | awk '{print $1}')
    log_with_timestamp "Active builder: $ACTIVE_BUILDER"
    
    # Create cache directory
    log_with_timestamp "Setting up cache directory: $CACHE_DIR"
    mkdir -p "$CACHE_DIR"
    
    log_build_step_complete "Setting Up Buildx Builder"
}

# Function to build image
build_image() {
    log_build_step "Building Docker Image"
    log_with_timestamp "Building image: $IMAGE_NAME"
    log_with_timestamp "Log file: $LOG_FILE"
    
    # Build command based on options
    if [ "$CLEAN_BUILD" = true ]; then
        log_with_timestamp "Clean build (no cache)"
        if [ "$USE_BUILDX" = true ]; then
            docker buildx build --no-cache \
                --platform linux/amd64 \
                --load \
                -t "$IMAGE_NAME" . 2>&1 | tee -a "$LOG_FILE"
        else
            docker build --no-cache \
                -t "$IMAGE_NAME" . 2>&1 | tee -a "$LOG_FILE"
        fi
    else
        log_with_timestamp "Build with caching"
        if [ "$USE_BUILDX" = true ]; then
            docker buildx build \
                --cache-from type=local,src="$CACHE_DIR" \
                --cache-to type=local,dest="$CACHE_DIR" \
                --platform linux/amd64 \
                --load \
                -t "$IMAGE_NAME" . 2>&1 | tee -a "$LOG_FILE"
        else
            docker build \
                -t "$IMAGE_NAME" . 2>&1 | tee -a "$LOG_FILE"
        fi
    fi
    
    # Check build result
    if [ $? -eq 0 ]; then
        log_with_timestamp "Build completed successfully!"
        
        # Show image details
        log_with_timestamp "Image details:"
        docker images "$IMAGE_NAME" | tee -a "$LOG_FILE"
        
        # Show image size
        IMAGE_SIZE=$(docker images "$IMAGE_NAME" --format "table {{.Size}}" | tail -1)
        log_with_timestamp "Image size: $IMAGE_SIZE"
        
        # Test image
        log_with_timestamp "Testing image..."
        if docker run --rm "$IMAGE_NAME" echo "Image test successful" > /dev/null 2>&1; then
            log_with_timestamp "Image test passed"
        else
            log_with_timestamp "Image test failed"
        fi
        
        log_build_step_complete "Building Docker Image"
    else
        print_error "Build failed. Check log file: $LOG_FILE"
        exit 1
    fi
}

# Function to cleanup
cleanup() {
    log_with_timestamp "Cleaning up temporary files..."
    
    # Remove temporary files
    if [ -f "build.pid" ]; then
        rm -f "build.pid"
    fi
    
    if [ -f "/tmp/build_current_step" ]; then
        rm -f "/tmp/build_current_step"
    fi
    
    if [ -f "/tmp/build_step_start" ]; then
        rm -f "/tmp/build_step_start"
    fi
    
    log_with_timestamp "Cleanup completed"
}

# Function to show build progress (can be called from another terminal)
show_build_progress() {
    if [ -f "/tmp/build_current_step" ]; then
        local current_step=$(cat /tmp/build_current_step)
        if [ ! -z "$current_step" ]; then
            local start_time=$(cat /tmp/build_step_start 2>/dev/null || echo $(date +%s))
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            local elapsed_str=$(printf "%02d:%02d:%02d" $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60)))
            
            echo "Current Build Step: $current_step"
            echo "Elapsed Time: $elapsed_str"
            echo "Log File: $LOG_FILE"
        else
            echo "No active build step found"
        fi
    else
        echo "No build in progress"
    fi
}

# Function to save Docker image
save_docker_image() {
    log_build_step "Saving Docker Image"
    
    # Create exports directory if it doesn't exist
    local exports_dir="exports"
    mkdir -p "$exports_dir"
    
    # Generate export filename with timestamp
    local export_filename="${exports_dir}/${IMAGE_NAME}-$(date +%Y%m%d-%H%M%S).tar"
    
    log_with_timestamp "Saving image '$IMAGE_NAME' to: $export_filename"
    
    # Save the image
    if docker save "$IMAGE_NAME" -o "$export_filename"; then
        # Get file size
        local file_size=$(du -h "$export_filename" | cut -f1)
        local file_size_bytes=$(stat -c%s "$export_filename")
        
        log_with_timestamp "Image saved successfully!"
        log_with_timestamp "Export file: $export_filename"
        log_with_timestamp "File size: $file_size ($file_size_bytes bytes)"
        
        # Create checksum for verification
        local checksum_file="${export_filename}.sha256"
        sha256sum "$export_filename" > "$checksum_file"
        log_with_timestamp "Checksum saved to: $checksum_file"
        
        # Show export summary
        echo ""
        echo "========================================"
        echo "DOCKER IMAGE EXPORTED SUCCESSFULLY"
        echo "========================================"
        echo "Image: $IMAGE_NAME"
        echo "Export file: $export_filename"
        echo "File size: $file_size"
        echo "Checksum: $checksum_file"
        echo ""
        echo "To load this image on another machine:"
        echo "  docker load -i $export_filename"
        echo ""
        echo "To verify integrity:"
        echo "  sha256sum -c $checksum_file"
        echo "========================================"
        
    else
        log_with_timestamp "ERROR: Failed to save Docker image"
        print_error "Image export failed. Check disk space and permissions."
        return 1
    fi
    
    log_build_step_complete "Saving Docker Image"
}

# Main execution
main() {
    # Create logs directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Initialize log file
    touch "$LOG_FILE"
    
    # Log build start
    log_with_timestamp "========================================"
    log_with_timestamp "VYGES VIVADO DOCKER BUILD STARTED"
    log_with_timestamp "========================================"
    
    # Log machine information
    get_machine_info | tee -a "$LOG_FILE"
    
    # Estimate build time
    estimate_build_time | tee -a "$LOG_FILE"
    
    # Log build configuration
    log_with_timestamp "Build Configuration:"
    log_with_timestamp "- Image name: $IMAGE_NAME"
    log_with_timestamp "- Base image: $BASE_IMAGE"
    log_with_timestamp "- Builder name: $BUILDER_NAME"
    log_with_timestamp "- Clean build: $CLEAN_BUILD"
    log_with_timestamp "- Force pull: $FORCE_PULL"
    log_with_timestamp "- Log file: $LOG_FILE"
    log_with_timestamp "========================================"
    
    # Set up error handling
    trap cleanup EXIT
    
    # Execute build steps
    check_prerequisites
    check_base_image
    setup_builder
    build_image
    
    # Log build completion
    local end_time=$(date +%s)
    local start_time=$(date +%s -d "$(head -1 "$LOG_FILE" | grep -oE '\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]' | sed 's/\[//;s/\]//')")
    local total_duration=$((end_time - start_time))
    local total_duration_str=$(printf "%02d:%02d:%02d" $((total_duration/3600)) $(((total_duration%3600)/60)) $((total_duration%60)))
    
    log_with_timestamp "========================================"
    log_with_timestamp "BUILD PROCESS COMPLETED SUCCESSFULLY!"
    log_with_timestamp "Total Build Time: $total_duration_str"
    log_with_timestamp "========================================"
    
    # Save Docker image (unless skipped)
    if [ "$SKIP_SAVE" = false ]; then
        save_docker_image
    else
        log_with_timestamp "Skipping automatic image export (--no-save flag used)"
    fi
    
    print_success "Build process completed successfully!"
    print_status "You can now run: docker run -it $IMAGE_NAME"
    print_status "Build log saved to: $LOG_FILE"
}

# Run main function
main "$@"
