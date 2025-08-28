# Vyges Xilinx Tools Docker Template

[![GitHub Template](https://img.shields.io/badge/GitHub-Template-blue?style=for-the-badge&logo=github)](https://github.com/vyges/xilinx-tools)
[![Docker](https://img.shields.io/badge/Docker-Required-blue?style=for-the-badge&logo=docker)](https://www.docker.com/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20LTS-orange?style=for-the-badge&logo=ubuntu)](https://ubuntu.com/)
[![Vivado](https://img.shields.io/badge/Xilinx-Vivado%202025.1-red?style=for-the-badge)](https://www.xilinx.com/products/design-tools/vivado.html)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue?style=for-the-badge)](LICENSE)

> **🚀 GitHub Template Repository** - Use this template to create your own customized Vivado Docker environment!

This is a **GitHub template repository** that provides a complete Docker configuration for building a Vyges development environment with Xilinx Vivado tools. **Fork this template** to create your own customized version.

## 🎯 **Template Usage**

### **Quick Start (Recommended)**
1. **Click "Use this template"** above, or visit: `https://github.com/vyges/xilinx-tools/generate`
2. **Clone your new repository**
3. **Customize patches** if needed (see Custom Patches section below)
4. **Build your Docker image**

### **Manual Fork Process**
```bash
# 1. Fork this repository to your GitHub account
# 2. Clone your forked repository
git clone https://github.com/YOUR_USERNAME/xilinx-tools.git
cd xilinx-tools

# 3. Customize patches if needed
# 4. Build your image
./build.sh
```

## 🔧 **Customization Guide**

### **Custom Patches**
Add your own patches to the `patches/` directory:
```bash
# Create custom patch files
patches/
├── vivado-2025.1-postinstall.patch
├── ubuntu-24.04-vivado-2025.1-postinstall.patch
└── your-custom-patch.patch  # Add your patches here
```

**Note**: Environment variables can be overridden via command line during build (see Configuration section below).

## 📋 **Template Features**

This template provides:
- ✅ **Complete Dockerfile** with Ubuntu 24.04 + Vivado 2025.1
- ✅ **Automated build script** (`build.sh`) with caching and monitoring
- ✅ **Download script** (`download-installer.sh`) for enterprise/internal networks
- ✅ **Patch system** for post-install fixes
- ✅ **Health monitoring** with built-in health checks
- ✅ **Comprehensive logging** and build recovery
- ✅ **Multi-organization support** for internal networks
- ✅ **Production-ready** configuration

## 🎯 **Overview**

This **GitHub template repository** provides a complete Docker configuration for building a Vyges development environment with Xilinx Vivado tools. The Docker image includes:

- **Ubuntu 24.04 LTS** base image
- **Xilinx Vivado 2025.1** (configurable version)
- **Development tools and dependencies** for IP development
- **Pre-configured environment** optimized for Vyges workflows
- **Built-in health monitoring** and container management
- **Automated build system** with caching and recovery

## 🚀 **Getting Started**

### **Prerequisites**

- Docker installed and running
- Access to Xilinx Vivado installer files
- `wget` command available (for download script)
- **Minimum 300GB free disk space** (see Disk Space Requirements below)
- **Server machine that does not sleep or suspend** (required for 3.5+ hour builds)

### **Docker Version Requirements**
- **Minimum**: Docker 20.10+ (for basic functionality)
- **Recommended**: Docker 24.0+ (for best performance and features)
- **Current**: ✅ Docker 28.3.3 with Buildx v0.26.1 - **Excellent!**

**Your Docker Version Benefits:**
- **Latest Features**: Docker 28.3.3 (2024) with all modern capabilities
- **Buildx Support**: Advanced multi-platform and parallel builds
- **Performance**: Optimized layer caching and resource management
- **Security**: Latest security patches and features
- **Ubuntu 24.04**: Full compatibility and optimization

### **Upgrading Docker on Ubuntu 24.04**

#### **Option 1: Install Latest Docker (Recommended)**
```bash
# Remove old Docker (if installed via apt)
sudo apt remove docker docker-engine docker.io containerd runc

# Remove Snap Docker (if you want to replace it)
sudo snap remove docker

# Install Docker from official repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify installation
docker --version
docker buildx version
```

#### **Option 2: Use Ubuntu Package Manager**
```bash
# Install from Ubuntu repositories (may be older but stable)
sudo apt update
sudo apt install docker.io docker-compose

# Verify installation
docker --version
```

#### **Option 3: Use Snap (if preferred)**
```bash
# Install Docker via Snap
sudo snap install docker

# Verify installation
docker --version
```

## Disk Space Requirements

### **Build Process Space Usage**
The Docker build process requires significant disk space due to multiple stages:

1. **Vivado Installer**: ~120GB (original tar file)
2. **Ubuntu Base Image**: ~2-3GB (downloaded during build)
3. **Package Installation**: ~5-10GB (apt packages and dependencies)
4. **Vivado Installation**: ~120GB (extracted and installed)
5. **Final Image**: ~120-150GB (compressed Docker image)

### **Total Space Requirements**
- **Minimum Free Space**: 300GB
- **Recommended Free Space**: 400GB
- **Peak Usage During Build**: ~250GB

### **Space Recovery After Build**
- **Vivado Installer**: Can be deleted after successful build
- **Docker Build Cache**: Can be cleaned with `docker system prune`
- **Final Image Size**: ~120-150GB (usable for running containers)

### **Space Optimization Tips**
- Use `--no-cache` flag for clean builds
- Clean Docker system regularly: `docker system prune -a`
- Consider building on a dedicated drive with sufficient space
- Monitor disk usage during build: `df -h`

### **Base Image Caching and Optimization**

#### **Pre-download Base Image**
```bash
# Download Ubuntu 24.04 base image before building
docker pull ubuntu:24.04

# Verify the image is cached locally
docker images ubuntu:24.04
```

#### **Build Cache Optimization**
```bash
# Build with explicit cache usage
docker build --cache-from ubuntu:24.04 -t vyges-vivado .

# Use buildx for advanced caching and parallel builds
docker buildx build --cache-from type=local,src=/tmp/.buildx-cache -t vyges-vivado .

# Buildx with parallel layer building (Docker 28.3.3 feature)
docker buildx build --cache-from type=local,src=/tmp/.buildx-cache \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  --platform linux/amd64 \
  -t vyges-vivado .
```

#### **Layer Caching Strategy**
The Dockerfile is optimized for layer caching:
- **Base Image**: `ubuntu:24.04` (cached separately)
- **Package Installation**: Single RUN command for all packages
- **Vivado Installation**: Separate layers for installer, installation, and cleanup
- **Patches**: Applied in separate layers

## Quick Start

### 1. Download Installer

**For Enterprise/Internal Networks:**
Use the provided script to download from your internal Xilinx installer repository:

```bash
# Download from internal network
./download-installer.sh -i "https://internal.example.com/xilinx"

# Download specific version
./download-installer.sh -v 2024.2 -i "https://internal.example.com/xilinx"

# Download with update
./download-installer.sh -u "FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145_update.tar" -i "https://internal.example.com/xilinx"
```

**For Public/Individual Use:**
Download the Xilinx Vivado installer manually from the [Xilinx website](https://www.xilinx.com/support/download.html) and place it in the `vivado-installer/` directory.

**⚠️ Download Time Considerations:**
- **File Size**: ~120GB
- **Download Time**: 2-6+ hours depending on network speed
- **Server Requirement**: Use a machine that **does not sleep** or suspend
- **Network Stability**: Ensure stable connection for large file downloads

### 2. Build Docker Image

**⚠️ Critical Requirements**: 
- Ensure you have at least **300GB free disk space** before building
- Use a **server machine that does not sleep or suspend**
- Build time: **3.5+ hours** for complete process

**Build Time Breakdown:**
- **Copying 120GB installer**: 30-60 minutes
- **Running Vivado installer**: 2-3 hours
- **Applying patches and finalizing**: 15-30 minutes
- **Total estimated time**: 3.5-4.5 hours

**Why Server Machine is Required:**
- **No sleep/suspend**: Prevents build interruption during long operations
- **Stable power**: Ensures continuous operation for 3.5+ hours
- **Network stability**: Maintains connection for large file operations
- **Resource availability**: Consistent CPU/memory allocation

#### **Option A: Automated Build Script (Recommended)**
```bash
# Make script executable (first time only)
chmod +x build.sh

# Standard build with caching
./build.sh

# Clean build (no cache)
./build.sh -c

# Force pull base image
./build.sh -p

# Custom image name
./build.sh -i my-vivado-image

# Show all options
./build.sh -h
```

#### **Option B: Manual Build Commands**
```bash
# Build with default settings
docker build -t vyges-vivado .

# Build with custom Vivado version
docker build --build-arg VIVADO_VERSION=2025.2 -t vyges-vivado .

# Build with custom Ubuntu mirror
docker build --build-arg UBUNTU_MIRROR=mirror.example.com/ubuntu -t vyges-vivado .

# Clean build (recommended for first-time builds)
docker build --no-cache -t vyges-vivado .

# Build with logs saved to file (recommended for long builds)
docker build --no-cache -t vyges-vivado . 2>&1 | tee build.log

# Build with logs saved to file (no terminal output)
docker build --no-cache -t vyges-vivado . > build.log 2>&1

# Build with timestamped log file
docker build --no-cache -t vyges-vivado . 2>&1 | tee "build-$(date +%Y%m%d-%H%M%S).log"
```

**Build Time**: Expect **3.5-4.5 hours** for complete builds depending on your system and network speed.

**⚠️ Logging Recommendation**: For long builds, always use log redirection to preserve build output in case of connection issues.

### **Build Time Optimization**
```bash
# 1. Pre-download base image (saves 2-3 minutes)
docker pull ubuntu:24.04

# 2. Build with caching enabled (default)
docker build -t vyges-vivado .

# 3. Build with explicit cache usage
docker build --cache-from ubuntu:24.04 -t vyges-vivado .

# 4. For clean builds (no cache)
docker build --no-cache -t vyges-vivado .
```

**Expected Time Savings:**
- **First Build**: 3.5-4.5 hours (full build)
- **Subsequent Builds**: 2-3 hours (cached layers)
- **Base Image Cached**: 2-3 minutes saved
- **Package Layer Cached**: 5-10 minutes saved
- **Installer Layer Cached**: 30-60 minutes saved (120GB file copy)

**Docker 28.3.3 + Buildx Benefits:**
- **Parallel Layer Building**: Multiple layers build simultaneously
- **Advanced Caching**: Better cache hit rates and management
- **Resource Optimization**: Improved memory and disk usage
- **Buildx Features**: Multi-platform builds and advanced caching
- **Modern BuildKit**: Latest build engine with optimizations

## Build Logging and Monitoring

### **Enhanced Build Commands for Docker 28.3.3**
With your new Docker version, you can use these advanced build commands:

#### **Standard Build (Recommended for most users)**
```bash
docker build -t vyges-vivado .
```

#### **Buildx with Advanced Caching**
```bash
# Create a buildx builder instance
docker buildx create --name vyges-builder --use

# Build with advanced caching
docker buildx build --cache-from type=local,src=/tmp/.buildx-cache \
  --cache-to type=local,dest=/tmp/.buildx-cache \
  -t vyges-vivado .
```

#### **Parallel Build with Resource Limits**
```bash
# Build with parallel layers and resource constraints
docker buildx build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  --platform linux/amd64 \
  --memory=8g \
  --memory-swap=8g \
  -t vyges-vivado .
```

### **Quick Reconnection Checklist**
After reconnecting to your remote machine, run these commands in order:

```bash
# 1. Check if build image exists
docker images | grep vyges-vivado

# 2. Check build logs
ls -lh build*.log

# 3. Verify image functionality
docker run --rm vyges-vivado echo "Build verification test"

# 4. Check Vivado installation
docker run --rm vyges-vivado /tools/Xilinx/2025.1/Vivado/bin/vivado -version
```

**✅ Success Indicators:**
- Image appears in `docker images` list
- Log file is large (>100MB) and contains completion message
- Container runs without errors
- Vivado binary responds with version information

**❌ Failure Indicators:**
- No image found
- Small or missing log file
- Container fails to start
- Vivado binary not found or fails

### **Logging Options**

#### **1. Tee to File (Recommended)**
```bash
# Shows output on terminal AND saves to file
docker build --no-cache -t vyges-vivado . 2>&1 | tee build.log
```
- **Pros**: See progress in real-time + save logs
- **Cons**: Slightly slower due to tee overhead
- **Use Case**: Most builds, especially long ones

#### **2. Redirect to File Only**
```bash
# Saves logs to file, no terminal output
docker build --no-cache -t vyges-vvado . > build.log 2>&1
```
- **Pros**: Fastest, clean logs
- **Cons**: No real-time progress visibility
- **Use Case**: Background builds, CI/CD

#### **3. Timestamped Logs**
```bash
# Creates unique log file for each build
docker build --no-cache -t vyges-vivado . 2>&1 | tee "build-$(date +%Y%m%d-%H%M%S).log"
```
- **Pros**: Multiple builds don't overwrite logs
- **Cons**: More log files to manage
- **Use Case**: Multiple builds, debugging

### **Monitoring Long Builds**

#### **Real-time Monitoring**
```bash
# Watch log file in real-time
tail -f build.log

# Monitor disk space during build
watch -n 30 'df -h'

# Check Docker build progress
docker system df
```

#### **Build Recovery**
```bash
# Resume interrupted build (if using --cache-from)
docker build --cache-from vyges-vivado -t vyges-vivado .

# Check Docker system disk usage
docker system df

# Check image build history
docker history vyges-vivado
```

### **Remote Build Verification**
After reconnecting to your remote machine, check build status:

#### **1. Check Docker Images**
```bash
# List all Docker images
docker images

# Look for your image
docker images | grep vyges-vivado

# Check image details
docker inspect vyges-vivado
```

#### **2. Check Build Logs**
```bash
# View the log file if it exists
ls -la build*.log

# Check log file size (should be substantial if build completed)
ls -lh build*.log

# View end of log file for completion message
tail -50 build.log

# Search for completion indicators
grep -i "successfully built\|build completed\|finished" build.log
```

#### **3. Check Docker Build History**
```bash
# Check if build process is still running
docker ps -a

# Check Docker system disk usage
docker system df

# Look for any running containers
docker ps

# Check Docker build cache and layers
docker history vyges-vivado
```

#### **4. Verify Vivado Installation**
```bash
# Test if the image can run
docker run --rm vyges-vivado echo "Image works!"

# Check Vivado installation
docker run --rm vyges-vivado ls -la /tools/Xilinx/

# Test Vivado binary
docker run --rm vyges-vivado /tools/Xilinx/2025.1/Vivado/bin/vivado -version
```

### **Log File Management**
- **Log Rotation**: Use timestamped logs for multiple builds
- **Storage**: Ensure sufficient space for logs (logs can be several GB)
- **Cleanup**: Archive old logs: `gzip build-*.log`

### **Proactive Build Monitoring**

#### **1. Background Build with Notifications**
```bash
# Start build in background with completion notification
nohup docker build --no-cache -t vyges-vivado . > build.log 2>&1 && \
  echo "Build completed successfully!" && \
  notify-send "Docker Build Complete" "Vyges Vivado image built successfully!" &

# Get the background process ID
echo $! > build.pid

# Monitor background process
tail -f build.log
```

#### **2. Build Completion Detection Script**
```bash
# Create a monitoring script
cat > monitor_build.sh << 'EOF'
#!/bin/bash
BUILD_LOG="build.log"
IMAGE_NAME="vyges-vivado"

echo "Monitoring build: $BUILD_LOG"
echo "Target image: $IMAGE_NAME"

while true; do
    # Check if build process is still running
    if ! pgrep -f "docker build.*$IMAGE_NAME" > /dev/null; then
        # Check if image was created
        if docker images | grep -q "$IMAGE_NAME"; then
            echo "✅ Build completed successfully!"
            echo "Image details:"
            docker images | grep "$IMAGE_NAME"
            break
        else
            echo "❌ Build failed or was interrupted"
            echo "Last 20 lines of log:"
            tail -20 "$BUILD_LOG"
            break
        fi
    fi
    
    echo "Build still running... $(date)"
    sleep 30
done
EOF

chmod +x monitor_build.sh
./monitor_build.sh
```

#### **3. Email Notifications (if available)**
```bash
# Send email notification when build completes
docker build --no-cache -t vyges-vivado . > build.log 2>&1 && \
  echo "Build completed at $(date)" | mail -s "Docker Build Success" your-email@example.com || \
  echo "Build failed at $(date)" | mail -s "Docker Build Failed" your-email@example.com
```

### 3. Run Container

```bash
# Interactive shell
docker run -it vyges-vivado

# Mount current directory
docker run -it -v $(pwd):/workspace vyges-vivado

# Run specific command
docker run -it vyges-vivado vivado -version
```

## Health Monitoring

The Docker image includes a built-in health check that monitors the Vivado installation:

```bash
# Check container health status
docker ps

# View detailed health check information
docker inspect --format='{{json .State.Health}}' <container_name>

# Run health check manually
docker exec <container_name> /tools/Xilinx/2025.1/Vivado/bin/vivado -version
```

**Health Check Details:**
- **Interval**: Every 30 seconds
- **Timeout**: 10 seconds per check
- **Start Period**: 60 seconds after container starts
- **Retries**: 3 consecutive failures before marking unhealthy
- **Check**: Verifies Vivado binary is accessible and executable

**Health Status:**
- 🟢 **healthy**: Vivado is working correctly
- 🔴 **unhealthy**: Vivado is not accessible or failing
- 🟡 **starting**: Container is in initial startup phase

## Configuration

### Environment Variables

- `VIVADO_VERSION`: Vivado version to install (default: 2025.1)
- `VIVADO_UPDATE`: Optional update file to install
- `INTERNAL_DOWNLOAD_URL`: Internal download URL for organizational use

### Build Arguments

- `UBUNTU_MIRROR`: Custom Ubuntu package mirror URL
- `VIVADO_VERSION`: Vivado version to install
- `VIVADO_UPDATE`: Update file to install

## Organizational Use

For organizations with internal Xilinx installers:

1. **Set internal download URL:**
   ```bash
   export INTERNAL_DOWNLOAD_URL="https://internal.example.com/xilinx"
   ```

2. **Download installer:**
   ```bash
   ./download-installer.sh -i "$INTERNAL_DOWNLOAD_URL"
   ```

3. **Build image:**
   ```bash
   docker build -t vyges-vivado .
   ```

## File Structure

```
xilinx-tools/
├── Dockerfile                 # Docker image definition
├── build.sh                   # Automated build script with caching
├── download-installer.sh      # Installer download script (enterprise use)
├── vivado-installer/         # Directory for installer files
├── patches/                  # Post-install patches
│   ├── vivado-2025.1-postinstall.patch  # Vivado version fixes
│   └── ubuntu-24.04-vivado-2025.1-postinstall.patch  # Ubuntu-specific fixes (optional)
├── entrypoint.sh            # Container entrypoint
├── logs/                     # Build log files (created automatically)
├── exports/                  # Exported Docker images (created after build)
└── README.md               # This file
```

## Patch System

The Docker image applies patches to fix known issues:

### **Vivado Version Patches** (Required)
- **File**: `vivado-${VIVADO_VERSION}-postinstall.patch`
- **Purpose**: Fixes specific to Vivado version (e.g., X11 workarounds, device enablement)
- **Status**: Required - build will fail if missing

### **Ubuntu Version Patches** (Optional)
- **File**: `ubuntu-${UBUNTU_VERSION}-vivado-${VIVADO_VERSION}-postinstall.patch`
- **Purpose**: OS-specific fixes for particular Ubuntu releases
- **Status**: Optional - build continues if missing

### **Current Patches**
- **X11 Workaround**: Disables problematic X11 locale support code
- **U280 Device**: Enables beta device support for Alveo U280
- **Ubuntu 24.04.3**: No specific patches needed (newer release)

## Troubleshooting

### Installer Not Found
- Ensure you've run `download-installer.sh` first (for enterprise use)
- Check that installer files are in `vivado-installer/` directory
- Verify file names match expected patterns
- For public use, download manually from [Xilinx website](https://www.xilinx.com/support/download.html)

### Download Failures
- Check network connectivity
- Verify internal URLs are accessible
- Ensure proper authentication for internal networks

### Build Failures
- Check Docker has sufficient disk space
  - Ensure at least 300GB free space available
  - Monitor with `df -h` during build
  - Clean Docker cache: `docker system prune -a`
- Verify all required files are present
- Check Docker logs for specific error messages
- **Disk Space Errors**: Common causes include:
  - Insufficient space for Vivado installer extraction
  - Docker build cache consuming too much space
  - System running out of inodes or disk space

### Build Interruptions
- **Connection Issues**: SSH disconnections, network timeouts
  - Always use log redirection: `docker build ... 2>&1 | tee build.log`
  - Check log file for last completed step
  - Resume build from last successful layer if possible
- **System Crashes/Reboots**
  - Docker build cache may be preserved
  - Check `docker images` for partial builds
  - Consider using `--cache-from` for resuming builds
- **Manual Interruption** (Ctrl+C)
  - Build cache is preserved
  - Resume with: `docker build --cache-from vyges-vivado -t vyges-vivado .`

### Health Check Issues
- Container shows as "unhealthy"
  - Verify Vivado installation completed successfully
  - Check that `/tools/Xilinx/${VIVADO_VERSION}/Vivado/bin/vivado` exists
  - Ensure proper file permissions on Vivado binary
  - Review health check logs: `docker inspect <container_name>`
- Health check timing out
  - Vivado may be taking longer to start on slower systems
  - Consider increasing timeout values in Dockerfile if needed

## Security Notes
- The image runs as root (required for Vivado installation)
- Consider security implications for production use
- Internal download URLs should use HTTPS when possible
- Review and validate all downloaded files

## 📚 Additional Resources
- **Inspiration**: This project was inspired by the work of [ESnet SmartNIC team](https://github.com/esnet/xilinx-tools-docker) and their xilinx-tools-docker repository
- **ESnet License**: [ESnet SmartNIC License](https://github.com/esnet/xilinx-tools-docker/blob/main/LICENSE.md) - Copyright (c) 2022, The Regents of the University of California, through Lawrence Berkeley National Laboratory
- [Xilinx Vivado Documentation](https://www.xilinx.com/support/documentation-navigation/design-tools/vivado.html)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Vivado Installation Guide](https://www.xilinx.com/support/documentation-navigation/design-tools/vivado/installation.html)
- [Xilinx Vivado Installation, Licensing](https://docs.amd.com/v/u/en-US/dh0013-vivado-installation-and-licensing-hub)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Docker build logs
3. Verify file permissions and availability
4. Check network connectivity for downloads

**Maintained by**: [Vyges Team](https://github.com/vyges)  
**Last Updated**: August 2025  
**Vivado Version**: 2025.1

## 🐳 **Docker Management Help**

### **Docker Cache Management**
```bash
# Check current Docker disk usage
docker system df

# Clean up build cache (most aggressive)
docker builder prune -a

# Clean up everything (images, containers, networks, build cache)
docker system prune -a

# Clean up only build cache
docker builder prune

# Clean up only dangling images
docker image prune

# Clean up only stopped containers
docker container prune
```

**⚠️ Warning**: `docker system prune -a` will remove ALL unused images, containers, networks, and build cache. Use with caution!

### **Handling Large Build Caches**
If you see a large Build Cache (like your 236.8GB), here's how to handle it:

```bash
# 1. First, check what's in the build cache
docker system df

# 2. Clean ONLY the build cache (safest option)
docker builder prune

# 3. If you want to be more aggressive with build cache
docker builder prune -a

# 4. For complete cleanup (removes everything unused)
docker system prune -a
```

**Build Cache vs Images:**
- **Build Cache**: Temporary layers from failed or interrupted builds
- **Images**: Successfully built Docker images
- **Dangling Images**: Images with `<none>` tags (can be safely removed)
