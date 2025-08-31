#!/bin/bash

# Vyges Vivado Docker Build Script
# This script automates the Docker build process with caching and optimization

set -e

# Configuration
IMAGE_NAME="vyges-vivado"
BASE_IMAGE="ubuntu:24.04"
BUILDER_NAME="vyges-builder"
CACHE_DIR="$HOME/.container-cache"
LOG_FILE="logs/build-$(date +%Y%m%d-%H%M%S).log"

# Container runtime (docker or podman)
CONTAINER_RUNTIME="podman"

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
    echo "Container Runtime: $CONTAINER_RUNTIME"
    echo "Runtime Version: $($CONTAINER_RUNTIME --version)"
    if [ "$CONTAINER_RUNTIME" = "docker" ]; then
        echo "Buildx Version: $(docker buildx version 2>/dev/null | head -1 || echo 'Not available')"
    fi
    echo "========================================"
}

# Function to get system limits and configuration
get_system_limits() {
    echo "=== SYSTEM LIMITS & CONFIGURATION ==="
    echo "User Limits (ulimit -a):"
    ulimit -a | sed 's/^/  /'
    echo ""
    echo "File System Limits:"
    echo "  Max open files: $(cat /proc/sys/fs/file-max)"
    echo "  Current open files: $(cat /proc/sys/fs/file-nr | awk '{print $1}')"
    echo "  Max inodes: $(df -i / | tail -1 | awk '{print $2}')"
    echo "  Used inodes: $(df -i / | tail -1 | awk '{print $3}')"
    echo "  Inode usage: $(df -i / | tail -1 | awk '{print $5}')"
    echo ""
    echo "Memory Management:"
    echo "  Swappiness: $(cat /proc/sys/vm/swappiness)"
    echo "  Dirty ratio: $(cat /proc/sys/vm/dirty_ratio)"
    echo "  Dirty background ratio: $(cat /proc/sys/vm/dirty_background_ratio)"
    echo ""
    echo "Shared Memory:"
    echo "  SHMMAX: $(cat /proc/sys/kernel/shmmax)"
    echo "  SHMMNI: $(cat /proc/sys/kernel/shmmni)"
    echo "  SHMALL: $(cat /proc/sys/kernel/shmall)"
    echo ""
    echo "Temporary Directory:"
    echo "  /tmp size: $(df -h /tmp | tail -1 | awk '{print $2 " total, " $3 " used, " $4 " available"}')"
    echo "  /tmp inodes: $(df -i /tmp | tail -1 | awk '{print $2 " total, " $3 " used, " $4 " available"}')"
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
    
    echo "=== CONTAINER RUNTIME BUILD TIME ESTIMATION ==="
    echo "Based on your system specifications:"
    echo "- CPU Cores: $cpu_cores"
    echo "- RAM: ${ram_gb}GB"
    echo "- Available Storage: ${storage_gb}GB"
    echo ""
    
    # Container runtime build time estimation (more realistic)
    echo "=== CONTAINER RUNTIME BUILD BREAKDOWN ==="
    
    # Base Container runtime build times for Vivado (in minutes)
    local base_vivado_time=45      # Vivado installation
    local base_docker_time=120     # Container runtime layer processing
    local base_cache_time=30       # Cache operations
    local base_finalize_time=45    # Image finalization
    
    local total_base_minutes=$((base_vivado_time + base_docker_time + base_cache_time + base_finalize_time))
    
    echo "- Base Vivado installation: ${base_vivado_time} minutes"
    echo "- Container runtime layer processing: ${base_docker_time} minutes"
    echo "- Cache operations: ${base_cache_time} minutes"
    echo "- Image finalization: ${base_finalize_time} minutes"
    echo "- Total base time: ${total_base_minutes} minutes"
    echo ""
    
    # System-specific adjustments
    echo "=== SYSTEM OPTIMIZATIONS ==="
    
    # CPU adjustments (Container runtime builds are I/O bound, but CPU helps with parallel operations)
    local cpu_factor=1.0
    if [ "$cpu_cores" -ge 64 ]; then
        cpu_factor=0.85
        echo "- Very high CPU count (${cpu_cores} cores): ~15% faster (parallel operations)"
    elif [ "$cpu_cores" -ge 32 ]; then
        cpu_factor=0.90
        echo "- High CPU count (${cpu_cores} cores): ~10% faster (parallel operations)"
    elif [ "$cpu_cores" -ge 16 ]; then
        cpu_factor=0.95
        echo "- Good CPU count (${cpu_cores} cores): ~5% faster (parallel operations)"
    elif [ "$cpu_cores" -ge 8 ]; then
        cpu_factor=1.0
        echo "- Adequate CPU count (${cpu_cores} cores): normal build speed"
    else
        cpu_factor=1.15
        echo "- Low CPU count (${cpu_cores} cores): ~15% slower (limited parallelism)"
    fi
    
    # RAM adjustments (prevents swapping during large operations)
    local ram_factor=1.0
    if [ "$ram_gb" -ge 128 ]; then
        ram_factor=0.90
        echo "- Very high RAM (${ram_gb}GB): ~10% faster (no memory pressure)"
    elif [ "$ram_gb" -ge 64 ]; then
        ram_factor=0.95
        echo "- High RAM (${ram_gb}GB): ~5% faster (no memory pressure)"
    elif [ "$ram_gb" -ge 32 ]; then
        ram_factor=1.0
        echo "- Good RAM (${ram_gb}GB): normal build speed"
    elif [ "$ram_gb" -ge 16 ]; then
        ram_factor=1.10
        echo "- Adequate RAM (${ram_gb}GB): ~10% slower (potential memory pressure)"
    else
        ram_factor=1.25
        echo "- Low RAM (${ram_gb}GB): ~25% slower (likely swapping, consider increasing)"
    fi
    
    # Storage adjustments (I/O performance is critical for Container runtime builds)
    local storage_factor=1.0
    if [ "$storage_gb" -ge 1000 ]; then
        storage_factor=0.90
        echo "- Very high storage (${storage_gb}GB): ~10% faster (excellent I/O performance)"
    elif [ "$storage_gb" -ge 500 ]; then
        storage_factor=0.95
        echo "- High storage (${storage_gb}GB): ~5% faster (good I/O performance)"
    elif [ "$storage_gb" -ge 200 ]; then
        storage_factor=1.0
        echo "- Adequate storage (${storage_gb}GB): normal build speed"
    elif [ "$storage_gb" -ge 100 ]; then
        storage_factor=1.15
        echo "- Low storage (${storage_gb}GB): ~15% slower (I/O bottlenecks likely)"
    else
        storage_factor=1.30
        echo "- Very low storage (${storage_gb}GB): ~30% slower (severe I/O bottlenecks)"
    fi
    
    # Container runtime-specific factors
    local runtime_factor=1.0
    if command -v "$CONTAINER_RUNTIME" > /dev/null 2>&1; then
        local runtime_version=$($CONTAINER_RUNTIME --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [ ! -z "$runtime_version" ]; then
            if [ "$CONTAINER_RUNTIME" = "podman" ]; then
                runtime_factor=0.90
                echo "- Podman (${runtime_version}): ~10% faster (better resource management)"
            elif [ "$CONTAINER_RUNTIME" = "docker" ]; then
                local major_version=$(echo "$runtime_version" | cut -d. -f1)
                if [ "$major_version" -ge 25 ]; then
                    runtime_factor=0.95
                    echo "- Modern Docker (${runtime_version}): ~5% faster (improved build performance)"
                elif [ "$major_version" -ge 20 ]; then
                    runtime_factor=1.0
                    echo "- Recent Docker (${runtime_version}): normal build speed"
                else
                    runtime_factor=1.10
                    echo "- Older Docker (${runtime_version}): ~10% slower (consider upgrading)"
                fi
            fi
        fi
    fi
    
    # Calculate final estimated time
    local estimated_minutes=$(echo "$total_base_minutes * $cpu_factor * $ram_factor * $storage_factor * $runtime_factor" | bc -l)
    local estimated_hours=$(echo "scale=1; $estimated_minutes / 60" | bc -l)
    local estimated_hours_rounded=$(echo "scale=0; $estimated_minutes / 60 + 0.5" | bc -l)
    
    echo ""
    echo "=== FINAL ESTIMATION ==="
    echo "ESTIMATED BUILD TIME: ${estimated_hours} hours (${estimated_minutes%.*} minutes)"
    echo ""
    
    # Provide time ranges for user planning
    local min_time=$(echo "$estimated_minutes * 0.8" | bc -l)
    local max_time=$(echo "$estimated_minutes * 1.3" | bc -l)
    local min_hours=$(echo "scale=1; $min_time / 60" | bc -l)
    local max_hours=$(echo "scale=1; $max_time / 60" | bc -l)
    
    echo "EXPECTED RANGE: ${min_hours}-${max_hours} hours"
    echo "  - Best case: ${min_hours} hours (everything optimal)"
    echo "  - Worst case: ${max_hours} hours (if issues occur)"
    echo ""
    
    # Additional considerations
    echo "=== IMPORTANT NOTES ==="
    echo "- First build: Use the full estimated time"
    echo "- Subsequent builds: 30-60% faster (cached layers)"
    echo "- Clean builds (--clean): Use full estimated time"
    echo "- Network issues: Add 10-20% to estimates"
    echo "- Monitor progress: Use './build.sh --monitor' in another terminal"
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

# Function to show real-time resource monitoring
show_resource_monitoring() {
    echo "Real-time Resource Monitoring"
    echo "============================"
    echo "Press Ctrl+C to stop monitoring"
    echo ""
    
    while true; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local memory=$(free -h | grep '^Mem:' | awk '{print $3 "/" $2 " (" $3/$2*100 "%)"}')
        local disk=$(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $3/$2*100 "%)"}')
        local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null || echo '0B')
        local container_images=$($CONTAINER_RUNTIME images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | wc -l)
        local container_containers=$($CONTAINER_RUNTIME ps -a --format "table {{.Names}}\t{{.Status}}" | wc -l)
        
        clear
        echo "Real-time Resource Monitoring - $timestamp"
        echo "=========================================="
        echo "Memory Usage: $memory"
        echo "Disk Usage:   $disk"
        echo "Cache Size:   $cache_size"
        echo "Container Images: $((container_images - 1))"
        echo "Container Containers: $((container_containers - 1))"
        echo ""
        echo "Press Ctrl+C to stop monitoring"
        
        sleep 5
    done
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

# Function to monitor resources during build
monitor_resources() {
    local log_file="$1"
    local interval=30  # Check every 30 seconds
    
    while true; do
        if [ ! -f "/tmp/build_current_step" ]; then
            break  # Build finished
        fi
        
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local memory=$(free -h | grep '^Mem:' | awk '{print $3 "/" $2 " (" $3/$2*100 "%)"}')
        local disk=$(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $3/$2*100 "%)"}')
        local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null || echo '0B')
        
        echo "[$timestamp] RESOURCE_MONITOR: Memory: $memory, Disk: $disk, Cache: $cache_size" >> "$log_file"
        
        sleep $interval
    done
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build Vyges Vivado container image with optimization and caching.

OPTIONS:
    -c, --clean          Clean build (no cache)
    -p, --pull           Force pull base image
    -b, --builder NAME   Custom builder name (default: vyges-builder)
    -i, --image NAME     Custom image name (default: vyges-vivado)
    -l, --log FILE       Custom log file (default: build-YYYYMMDD-HHMMSS.log)
    -s, --no-save        Skip automatic image export
    --skip-verify        Skip SHA512 verification of Vivado installer
    -h, --help           Show this help message
    --progress           Show current build progress (use in another terminal)
    --monitor            Show real-time resource monitoring

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

    # Monitor resources in real-time (in another terminal)
    $0 --monitor

    # View build logs
    tail -f logs/build-*.log
EOF
}

# Parse command line arguments
CLEAN_BUILD=false
FORCE_PULL=false
SKIP_SAVE=false
SKIP_VERIFY=false
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
        --skip-verify)
            SKIP_VERIFY=true
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
        --monitor)
            show_resource_monitoring
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function to optimize system limits
optimize_system_limits() {
    log_build_step "Optimizing System Limits"
    
    # Check and fix open files limit
    local current_limit=$(ulimit -n)
    local recommended_limit=65536
    
    if [ "$current_limit" -lt "$recommended_limit" ]; then
        log_with_timestamp "Current open files limit: $current_limit (too low)"
        log_with_timestamp "Setting open files limit to: $recommended_limit"
        
        if ulimit -n "$recommended_limit" 2>/dev/null; then
            log_with_timestamp "Successfully set open files limit to: $(ulimit -n)"
            print_success "Open files limit optimized"
        else
            print_warning "Could not set open files limit. Build may fail with large files."
            print_warning "Consider running: ulimit -n $recommended_limit"
        fi
    else
        log_with_timestamp "Open files limit is adequate: $current_limit"
    fi
    
    # Check and warn about other critical limits
    local file_size_limit=$(ulimit -f)
    if [ "$file_size_limit" != "unlimited" ] && [ "$file_size_limit" -lt 100000000 ]; then
        print_warning "File size limit may be too low: $file_size_limit blocks"
        print_warning "Consider setting: ulimit -f unlimited"
    fi
    
    log_build_step_complete "Optimizing System Limits"
}

# Function to check prerequisites
check_prerequisites() {
    log_build_step "Checking Prerequisites"
    
    # Check if container runtime is available and working
    if ! command -v "$CONTAINER_RUNTIME" > /dev/null 2>&1; then
        print_error "$CONTAINER_RUNTIME command not found. Please install $CONTAINER_RUNTIME and try again."
        exit 1
    fi
    
    log_with_timestamp "Container runtime command found at: $(which $CONTAINER_RUNTIME)"
    
    # Check if container runtime is accessible
    log_with_timestamp "Testing $CONTAINER_RUNTIME connection..."
    if ! $CONTAINER_RUNTIME info > /dev/null 2>&1; then
        if [ "$CONTAINER_RUNTIME" = "docker" ]; then
            print_error "Cannot connect to Docker daemon. Please check:"
            print_error "1. Docker service is running: sudo systemctl status docker"
            print_error "2. User has Docker permissions: sudo usermod -aG docker $USER"
            print_error "3. Docker socket permissions: ls -la /var/run/docker.sock"
        else
            print_error "Cannot connect to Podman. Please check:"
            print_error "1. Podman is properly installed"
            print_error "2. User has necessary permissions"
        fi
        exit 1
    fi
    
    # Check container runtime version
    RUNTIME_VERSION=$($CONTAINER_RUNTIME --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    log_with_timestamp "$CONTAINER_RUNTIME version: $RUNTIME_VERSION"
    
    # Check if buildx is available (Docker only)
    if [ "$CONTAINER_RUNTIME" = "docker" ]; then
        if ! docker buildx version > /dev/null 2>&1; then
            log_with_timestamp "Buildx not available. Using standard docker build."
            USE_BUILDX=false
        else
            log_with_timestamp "Buildx available: $(docker buildx version | head -1)"
            USE_BUILDX=true
        fi
    else
        log_with_timestamp "Using Podman build (no buildx needed)"
        USE_BUILDX=false
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
        $CONTAINER_RUNTIME pull "$BASE_IMAGE"
        log_with_timestamp "Base image pulled successfully"
        log_build_step_complete "Checking Base Image"
        return
    fi
    
    if $CONTAINER_RUNTIME images "$BASE_IMAGE" | grep -q "$BASE_IMAGE"; then
        log_with_timestamp "Base image already exists locally"
        log_with_timestamp "Image details:"
        $CONTAINER_RUNTIME images "$BASE_IMAGE" | tee -a "$LOG_FILE"
    else
        log_with_timestamp "Base image not found. Pulling..."
        $CONTAINER_RUNTIME pull "$BASE_IMAGE"
        log_with_timestamp "Base image pulled successfully"
    fi
    
    log_build_step_complete "Checking Base Image"
}

# Function to setup buildx builder (Docker only)
setup_builder() {
    log_build_step "Setting Up Container Builder"
    
    if [ "$CONTAINER_RUNTIME" = "podman" ]; then
        log_with_timestamp "Using Podman (no buildx setup needed)"
        log_build_step_complete "Setting Up Container Builder"
        return
    fi
    
    if [ "$USE_BUILDX" = false ]; then
        log_with_timestamp "Skipping buildx setup (not available)"
        log_build_step_complete "Setting Up Container Builder"
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
    
    # Add cache debugging info
    log_with_timestamp "Cache directory details:"
    log_with_timestamp "- Path: $CACHE_DIR"
    log_with_timestamp "- Owner: $(ls -ld "$CACHE_DIR" | awk '{print $3 ":" $4}')"
    log_with_timestamp "- Permissions: $(ls -ld "$CACHE_DIR" | awk '{print $1}')"
    log_with_timestamp "- Size: $(du -sh "$CACHE_DIR" 2>/dev/null || echo '0B')"
    
    # Check cache directory permissions
    if [ ! -w "$CACHE_DIR" ]; then
        print_warning "Cache directory is not writable by current user"
        log_with_timestamp "Attempting to fix permissions..."
        chmod 755 "$CACHE_DIR"
    fi
    
    # Validate cache directory
    if ! validate_cache "$CACHE_DIR" "$LOG_FILE"; then
        print_error "Cache validation failed. Exiting."
        exit 1
    fi
    
    log_build_step_complete "Setting Up Buildx Builder"
}

# Function to build image
build_image() {
    log_build_step "Building Docker Image"
    log_with_timestamp "Building image: $IMAGE_NAME"
    log_with_timestamp "Log file: $LOG_FILE"
    
    # Add cache status before build
    log_with_timestamp "Cache status before build:"
    log_with_timestamp "- Cache directory: $CACHE_DIR"
    log_with_timestamp "- Cache size: $(du -sh "$CACHE_DIR" 2>/dev/null || echo '0B')"
    log_with_timestamp "- Cache contents: $(ls -la "$CACHE_DIR" | wc -l) items"
    
    # Build command based on options
    if [ "$CLEAN_BUILD" = true ]; then
        log_with_timestamp "Clean build (no cache)"
        if [ "$CONTAINER_RUNTIME" = "podman" ]; then
            $CONTAINER_RUNTIME build --no-cache \
                --format docker \
                -t "$IMAGE_NAME" . 2>&1 | tee -a "$LOG_FILE"
        elif [ "$USE_BUILDX" = true ]; then
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
        if [ "$CONTAINER_RUNTIME" = "podman" ]; then
            # Podman build with cache
            log_with_timestamp "Starting Podman build with cache..."
            $CONTAINER_RUNTIME build \
                --format docker \
                -t "$IMAGE_NAME" . 2>&1 | tee -a "$LOG_FILE"
        elif [ "$USE_BUILDX" = true ]; then
            # Docker buildx with cache
            log_with_timestamp "Starting buildx build with cache..."
            log_with_timestamp "Cache from: type=local,src=$CACHE_DIR"
            log_with_timestamp "Cache to: type=local,dest=$CACHE_DIR"
            
            docker buildx build \
                --cache-from type=local,src="$CACHE_DIR" \
                --cache-to type=local,dest="$CACHE_DIR" \
                --platform linux/amd64 \
                --load \
                --progress=plain \
                -t "$IMAGE_NAME" . 2>&1 | tee -a "$LOG_FILE"
        else
            docker build \
                -t "$IMAGE_NAME" . 2>&1 | tee -a "$LOG_FILE"
        fi
    fi
    
    # Add cache status after build
    log_with_timestamp "Cache status after build:"
    log_with_timestamp "- Cache directory: $CACHE_DIR"
    log_with_timestamp "- Cache size: $(du -sh "$CACHE_DIR" 2>/dev/null || echo '0B')"
    log_with_timestamp "- Cache contents: $(ls -la "$CACHE_DIR" | wc -l) items"
    
    # Check build result
    if [ $? -eq 0 ]; then
        log_with_timestamp "Build completed successfully!"
        
        # Show image details
        log_with_timestamp "Image details:"
        $CONTAINER_RUNTIME images "$IMAGE_NAME" | tee -a "$LOG_FILE"
        
        # Show image size
        IMAGE_SIZE=$($CONTAINER_RUNTIME images "$IMAGE_NAME" --format "table {{.Size}}" | tail -1)
        log_with_timestamp "Image size: $IMAGE_SIZE"
        
        # Test image
        log_with_timestamp "Testing image..."
        if $CONTAINER_RUNTIME run --rm "$IMAGE_NAME" echo "Image test successful" > /dev/null 2>&1; then
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
    
    # Stop resource monitoring if running
    if [ ! -z "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null || true
    fi
    
    log_with_timestamp "Cleanup completed"
}

# Function to validate cache directory
validate_cache() {
    local cache_dir="$1"
    local log_file="$2"
    
    log_with_timestamp "Validating cache directory: $cache_dir"
    
    if [ ! -d "$cache_dir" ]; then
        print_error "Cache directory does not exist: $cache_dir"
        return 1
    fi
    
    if [ ! -w "$cache_dir" ]; then
        print_error "Cache directory is not writable: $cache_dir"
        return 1
    fi
    
    local cache_size=$(du -sh "$cache_dir" 2>/dev/null || echo '0B')
    log_with_timestamp "Cache validation passed: $cache_dir ($cache_size)"
    
    return 0
}

# Function to verify Vivado installer integrity
verify_vivado_installer() {
    log_build_step "Verifying Vivado Installer Integrity"
    
    local installer_dir="vivado-installer"
    local tar_file="${installer_dir}/FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145.tar"
    local digests_file="${installer_dir}/FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145.tar.digests"
    
    # Check if files exist
    if [ ! -f "$tar_file" ]; then
        print_error "Vivado installer tar file not found: $tar_file"
        return 1
    fi
    
    if [ ! -f "$digests_file" ]; then
        print_warning "Digests file not found: $digests_file"
        print_warning "Skipping SHA512 verification. Installer integrity not verified."
        log_build_step_complete "Verifying Vivado Installer Integrity"
        return 0
    fi
    
    log_with_timestamp "Verifying installer integrity using SHA512..."
    log_with_timestamp "Tar file: $tar_file"
    log_with_timestamp "Digests file: $digests_file"
    
    # Get file size for progress indication
    local file_size=$(du -h "$tar_file" | cut -f1)
    log_with_timestamp "File size: $file_size"
    
    # Calculate SHA512 hash
    log_with_timestamp "Calculating SHA512 hash (this may take several minutes for large files)..."
    local calculated_hash=$(sha512sum "$tar_file" | cut -d' ' -f1)
    log_with_timestamp "Calculated SHA512: $calculated_hash"
    
    # Extract all SHA512 hashes from the digests file
    # The file contains multiple hashes, we need to find the one that matches
    local temp_file=$(mktemp)
    
    # Extract all SHA512 hashes (128 hex characters) from the file
    # Handle cases where hashes are split across lines
    grep -oE '[a-f0-9]{128}' "$digests_file" > "$temp_file"
    
    local match_found=false
    local expected_hash=""
    
    while IFS= read -r hash; do
        if [ "$calculated_hash" = "$hash" ]; then
            expected_hash="$hash"
            match_found=true
            break
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    if [ "$match_found" = true ]; then
        log_with_timestamp "Expected SHA512: $expected_hash"
        print_success "SHA512 verification PASSED - Installer integrity confirmed"
        log_with_timestamp "SHA512 verification successful"
    else
        print_error "SHA512 verification FAILED - Installer may be corrupted"
        print_error "Calculated: $calculated_hash"
        print_error "No matching hash found in digests file"
        
        # Show available hashes for debugging
        log_with_timestamp "Available hashes in digests file:"
        grep -oE '[a-f0-9]{128}' "$digests_file" | while read -r hash; do
            log_with_timestamp "  $hash"
        done
        
        log_with_timestamp "SHA512 verification failed - installer may be corrupted"
        return 1
    fi
    
    log_build_step_complete "Verifying Vivado Installer Integrity"
    return 0
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
    if $CONTAINER_RUNTIME save "$IMAGE_NAME" -o "$export_filename"; then
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
    
    # Log system limits and configuration
    get_system_limits | tee -a "$LOG_FILE"
    
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
    
    # Start resource monitoring in background
    monitor_resources "$LOG_FILE" &
    MONITOR_PID=$!
    
    # Execute build steps
    optimize_system_limits
    check_prerequisites
    if [ "$SKIP_VERIFY" = false ]; then
        verify_vivado_installer
    else
        log_with_timestamp "Skipping SHA512 verification (--skip-verify flag used)"
    fi
    check_base_image
    setup_builder
    build_image
    
    # Stop monitoring
    if [ ! -z "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null || true
    fi
    
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
    print_status "You can now run: $CONTAINER_RUNTIME run -it $IMAGE_NAME"
    print_status "Build log saved to: $LOG_FILE"
}

# Run main function
main "$@"
