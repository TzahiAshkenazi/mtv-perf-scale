#!/bin/bash

install_latest_powershell_vmware() {
    echo "Checking OS and architecture..."

    case "$(uname -s)" in
        Linux*) os=linux ;;
        Darwin*) os=macos ;;
        *)
            echo "Unsupported OS"
            exit 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64) arch=x64 ;;
        aarch64) arch=arm64 ;;
        *)
            echo "Unsupported architecture"
            exit 1
            ;;
    esac

    echo "Detected platform: $os $arch"
    echo "Fetching latest PowerShell release..."

    latest_version=$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest | jq -r '.tag_name')
    if [ -z "$latest_version" ]; then
        echo "Could not determine latest PowerShell version."
        exit 1
    fi

    echo "Latest PowerShell version: $latest_version"

    pwsh_file="powershell-${latest_version/v/}-${os}-${arch}.tar.gz"
    download_url="https://github.com/PowerShell/PowerShell/releases/download/${latest_version}/${pwsh_file}"

    echo "Downloading PowerShell from: $download_url"
    wget -q --show-progress -O /tmp/pwsh.tar.gz "$download_url"

    echo "Extracting PowerShell to /usr/local/powershell ..."
    sudo rm -rf /usr/local/powershell
    sudo mkdir -p /usr/local/powershell
    sudo tar -xzf /tmp/pwsh.tar.gz -C /usr/local/powershell

    echo "Making PowerShell executable..."
    sudo chmod +x /usr/local/powershell/pwsh

    echo "Linking PowerShell to /usr/local/bin/pwsh"
    sudo ln -sf /usr/local/powershell/pwsh /usr/local/bin/pwsh

    echo "Installing VMware PowerCLI module..."
    pwsh -Command "Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -SkipPublisherCheck"

    echo "PowerShell + VMware PowerCLI installed successfully!"

    # Check if /usr/local/bin is in PATH; if not, add it to ~/.bashrc
    if ! echo "$PATH" | grep -q "/usr/local/bin"; then
        echo "Adding /usr/local/bin to PATH in ~/.bashrc"
        echo 'export PATH=/usr/local/bin:$PATH' >> ~/.bashrc
        echo "Please run 'source ~/.bashrc' or restart your terminal to update your PATH."
    else
        echo "/usr/local/bin is already in your PATH."
    fi
}

install_latest_powershell_vmware
