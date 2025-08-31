#!/bin/bash

# Xilinx Installer Download Script
# This script downloads the Xilinx Vivado installer from a configurable source
# and places it in the vivado-installer directory for Docker build

set -e

# Configuration
VIVADO_VERSION="${VIVADO_VERSION:-2025.1}"
VIVADO_INSTALLER="FPGAs_AdaptiveSoCs_Unified_SDI_${VIVADO_VERSION}_0530_0145.tar"
VIVADO_DIGESTS="FPGAs_AdaptiveSoCs_Unified_SDI_${VIVADO_VERSION}_0530_0145.tar.digests"
VIVADO_UPDATE="${VIVADO_UPDATE:-}"

# Default download sources (can be overridden by environment variables)
DEFAULT_DOWNLOAD_URL="https://www.xilinx.com/support/download.html"
INTERNAL_DOWNLOAD_URL="${INTERNAL_DOWNLOAD_URL:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

# Function to calculate and verify SHA512
calculate_and_verify_sha512() {
    local installer_file="$1"
    local digests_file="$2"
    
    print_status "Calculating SHA512 hash of installer..."
    print_status "File: $installer_file"
    
    # Get file size for progress indication
    local file_size=$(du -h "$installer_file" | cut -f1)
    print_status "File size: $file_size"
    
    # Calculate SHA512 hash
    print_status "Calculating SHA512 hash (this may take several minutes for large files)..."
    local calculated_hash=$(sha512sum "$installer_file" | cut -d' ' -f1)
    print_success "SHA512 calculated: $calculated_hash"
    
    # Verify against digests file if requested
    if [ "$VERIFY_SHA512" = true ]; then
        print_status "Verifying SHA512 against digests file..."
        
        if [ ! -f "$digests_file" ]; then
            print_warning "Digests file not found: $digests_file"
            print_warning "Cannot verify SHA512. Installer integrity not verified."
            return 0
        fi
        
        print_status "Digests file: $digests_file"
        print_status "Searching for calculated hash in digests file..."
        
        if grep -q "$calculated_hash" "$digests_file"; then
            print_success "SHA512 verification PASSED - Installer integrity confirmed"
        else
            print_error "SHA512 verification FAILED - Installer may be corrupted"
            print_error "Calculated: $calculated_hash"
            print_error "No matching hash found in digests file"
            
            # Show available hashes for debugging
            print_status "Available hashes in digests file:"
            grep -oE '[a-f0-9]{128}' "$digests_file" | while read -r hash; do
                print_status "  $hash"
            done
            
            return 1
        fi
    elif [ "$SKIP_VERIFY" = true ]; then
        print_status "SHA512 verification skipped (--no-verify flag used)"
    else
        print_status "SHA512 calculated but not verified (use --verify flag to verify against digests file)"
    fi
    
    return 0
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Download Xilinx Vivado installer for Docker build.

OPTIONS:
    -v, --version VERSION     Vivado version (default: ${VIVADO_VERSION})
    -u, --update UPDATE       Update file to download (optional)
    -i, --internal URL        Internal download URL for organizational use
    --verify                  Verify SHA512 against digests file after download
    --no-verify              Skip SHA512 verification (faster download)
    -h, --help               Show this help message

ENVIRONMENT VARIABLES:
    VIVADO_VERSION           Vivado version to download
    VIVADO_UPDATE           Update file to download
    INTERNAL_DOWNLOAD_URL   Internal download URL for organizational use

EXAMPLES:
    # Download from public Xilinx site
    $0

    # Download specific version
    $0 -v 2024.2

    # Download from internal network
    $0 -i "https://internal.example.com/xilinx"

    # Download with SHA512 verification
    $0 --verify

    # Download without verification (faster)
    $0 --no-verify

    # Download with environment variables
    export INTERNAL_DOWNLOAD_URL="https://internal.example.com/xilinx"
    export VIVADO_VERSION="2024.2"
    $0

EOF
}

# Parse command line arguments
VERIFY_SHA512=false
SKIP_VERIFY=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            VIVADO_VERSION="$2"
            shift 2
            ;;
        -u|--update)
            VIVADO_UPDATE="$2"
            shift 2
            ;;
        -i|--internal)
            INTERNAL_DOWNLOAD_URL="$2"
            shift 2
            ;;
        --verify)
            VERIFY_SHA512=true
            shift
            ;;
        --no-verify)
            SKIP_VERIFY=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Create vivado-installer directory
INSTALLER_DIR="vivado-installer"
mkdir -p "$INSTALLER_DIR"

print_status "Setting up Vivado ${VIVADO_VERSION} installer download..."

# Check if installer already exists
if [ -f "$INSTALLER_DIR/$VIVADO_INSTALLER" ]; then
    print_warning "Installer already exists: $INSTALLER_DIR/$VIVADO_INSTALLER"
    read -p "Do you want to re-download? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Using existing installer"
        SKIP_INSTALLER_DOWNLOAD=true
    else
        rm -f "$INSTALLER_DIR/$VIVADO_INSTALLER"
        rm -f "$INSTALLER_DIR/$VIVADO_DIGESTS"
        SKIP_INSTALLER_DOWNLOAD=false
    fi
else
    SKIP_INSTALLER_DOWNLOAD=false
fi

# Download installer and digests if needed
if [ "$SKIP_INSTALLER_DOWNLOAD" = false ]; then
    if [ -n "$INTERNAL_DOWNLOAD_URL" ]; then
        print_status "Downloading from internal network: $INTERNAL_DOWNLOAD_URL"
        
        # Download installer
        DOWNLOAD_URL="$INTERNAL_DOWNLOAD_URL/$VIVADO_INSTALLER"
        print_status "Downloading installer: $DOWNLOAD_URL"
        if wget --progress=bar:force:noscroll -O "$INSTALLER_DIR/$VIVADO_INSTALLER" "$DOWNLOAD_URL"; then
            print_success "Installer downloaded successfully"
        else
            print_error "Failed to download installer"
            exit 1
        fi
        
        # Download digests file
        DIGESTS_URL="$INTERNAL_DOWNLOAD_URL/$VIVADO_DIGESTS"
        print_status "Downloading digests file: $DIGESTS_URL"
        if wget --progress=bar:force:noscroll -O "$INSTALLER_DIR/$VIVADO_DIGESTS" "$DIGESTS_URL"; then
            print_success "Digests file downloaded successfully"
        else
            print_warning "Failed to download digests file - verification will be skipped"
        fi
    else
        print_status "Downloading from public Xilinx site"
        print_warning "Please download the following files manually from:"
        print_warning "$DEFAULT_DOWNLOAD_URL"
        print_warning "1. $VIVADO_INSTALLER"
        print_warning "2. $VIVADO_DIGESTS"
        print_warning "and place them in the $INSTALLER_DIR directory"
        print_warning ""
        print_warning "Or use --internal URL to specify an internal download source"
        exit 1
    fi
fi

# Download update if specified
if [ -n "$VIVADO_UPDATE" ]; then
    if [ -f "$INSTALLER_DIR/$VIVADO_UPDATE" ]; then
        print_warning "Update already exists: $INSTALLER_DIR/$VIVADO_UPDATE"
        read -p "Do you want to re-download? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Using existing update"
        else
            rm -f "$INSTALLER_DIR/$VIVADO_UPDATE"
        fi
    fi
    
    if [ ! -f "$INSTALLER_DIR/$VIVADO_UPDATE" ]; then
        if [ -n "$INTERNAL_DOWNLOAD_URL" ]; then
            print_status "Downloading update from internal network"
            DOWNLOAD_URL="$INTERNAL_DOWNLOAD_URL/$VIVADO_UPDATE"
        else
            print_error "Cannot download update without internal URL"
            exit 1
        fi
        
        print_status "Downloading update: $DOWNLOAD_URL"
        if wget --progress=bar:force:noscroll -O "$INSTALLER_DIR/$VIVADO_UPDATE" "$DOWNLOAD_URL"; then
            print_success "Update downloaded successfully"
        else
            print_error "Failed to download update"
            exit 1
        fi
    fi
fi

# Verify downloads and calculate SHA512
print_status "Verifying downloads..."
if [ -f "$INSTALLER_DIR/$VIVADO_INSTALLER" ]; then
    INSTALLER_SIZE=$(du -h "$INSTALLER_DIR/$VIVADO_INSTALLER" | cut -f1)
    print_success "Installer: $VIVADO_INSTALLER ($INSTALLER_SIZE)"
    
    # Calculate and verify SHA512
    if ! calculate_and_verify_sha512 "$INSTALLER_DIR/$VIVADO_INSTALLER" "$INSTALLER_DIR/$VIVADO_DIGESTS"; then
        print_error "SHA512 verification failed. Installer may be corrupted."
        exit 1
    fi
else
    print_error "Installer not found: $VIVADO_INSTALLER"
    exit 1
fi

if [ -n "$VIVADO_UPDATE" ] && [ -f "$INSTALLER_DIR/$VIVADO_UPDATE" ]; then
    UPDATE_SIZE=$(du -h "$INSTALLER_DIR/$VIVADO_UPDATE" | cut -f1)
    print_success "Update: $VIVADO_UPDATE ($UPDATE_SIZE)"
fi

print_success "Download complete! Ready for Docker build."
print_status "Run: ./build.sh"
