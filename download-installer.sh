#!/bin/bash

# Xilinx Installer Download Script
# This script downloads the Xilinx Vivado installer from a configurable source
# and places it in the vivado-installer directory for Docker build

set -e

# Configuration
VIVADO_VERSION="${VIVADO_VERSION:-2025.1}"
VIVADO_INSTALLER="FPGAs_AdaptiveSoCs_Unified_SDI_${VIVADO_VERSION}_0530_0145.tar"
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

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Download Xilinx Vivado installer for Docker build.

OPTIONS:
    -v, --version VERSION     Vivado version (default: ${VIVADO_VERSION})
    -u, --update UPDATE       Update file to download (optional)
    -i, --internal URL        Internal download URL for organizational use
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

    # Download with environment variables
    export INTERNAL_DOWNLOAD_URL="https://internal.example.com/xilinx"
    export VIVADO_VERSION="2024.2"
    $0

EOF
}

# Parse command line arguments
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
    else
        rm -f "$INSTALLER_DIR/$VIVADO_INSTALLER"
    fi
fi

# Download installer if it doesn't exist
if [ ! -f "$INSTALLER_DIR/$VIVADO_INSTALLER" ]; then
    if [ -n "$INTERNAL_DOWNLOAD_URL" ]; then
        print_status "Downloading from internal network: $INTERNAL_DOWNLOAD_URL"
        DOWNLOAD_URL="$INTERNAL_DOWNLOAD_URL/$VIVADO_INSTALLER"
    else
        print_status "Downloading from public Xilinx site"
        print_warning "Please download $VIVADO_INSTALLER manually from:"
        print_warning "$DEFAULT_DOWNLOAD_URL"
        print_warning "and place it in the $INSTALLER_DIR directory"
        print_warning ""
        print_warning "Or use --internal URL to specify an internal download source"
        exit 1
    fi
    
    print_status "Downloading: $DOWNLOAD_URL"
    if wget --progress=bar:force:noscroll -O "$INSTALLER_DIR/$VIVADO_INSTALLER" "$DOWNLOAD_URL"; then
        print_success "Installer downloaded successfully"
    else
        print_error "Failed to download installer"
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

# Verify downloads
print_status "Verifying downloads..."
if [ -f "$INSTALLER_DIR/$VIVADO_INSTALLER" ]; then
    INSTALLER_SIZE=$(du -h "$INSTALLER_DIR/$VIVADO_INSTALLER" | cut -f1)
    print_success "Installer: $VIVADO_INSTALLER ($INSTALLER_SIZE)"
else
    print_error "Installer not found: $VIVADO_INSTALLER"
    exit 1
fi

if [ -n "$VIVADO_UPDATE" ] && [ -f "$INSTALLER_DIR/$VIVADO_UPDATE" ]; then
    UPDATE_SIZE=$(du -h "$INSTALLER_DIR/$VIVADO_UPDATE" | cut -f1)
    print_success "Update: $VIVADO_UPDATE ($UPDATE_SIZE)"
fi

print_success "Download complete! Ready for Docker build."
print_status "Run: docker build -t vyges-vivado ."
