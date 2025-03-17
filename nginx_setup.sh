#!/bin/bash

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage information
function display_help() {
    echo -e "${BLUE}Nginx Configuration Script${NC}"
    echo "This script checks and configures Nginx with user directories, authentication, and CGI scripting."
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --help                 Display this help message"
    echo "  --check-only           Only check current configuration without making changes"
    echo "  --install-all          Install and configure all components"
    echo "  --configure-vhost      Configure virtual host"
    echo "  --setup-userdir        Set up user directories"
    echo "  --setup-auth           Set up basic authentication"
    echo "  --setup-pam-auth       Set up PAM authentication"
    echo "  --setup-cgi            Set up CGI scripting"
    echo ""
    echo "Example: $0 --install-all"
    echo "Example: $0 --setup-userdir --setup-auth"
    exit 0
}

# Function to check if running as root
function check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Function to check if Nginx is installed
function check_nginx() {
    echo -e "${BLUE}Checking if Nginx is installed...${NC}"
    if command -v nginx >/dev/null 2>&1; then
        echo -e "${GREEN}Nginx is installed.${NC}"
        return 0
    else
        echo -e "${RED}Nginx is not installed.${NC}"
        if [ "$CHECK_ONLY" = true ]; then
            return 1
        fi
        read -p "Do you want to install Nginx now? (y/n): " install_nginx
        if [[ "$install_nginx" =~ ^[Yy]$ ]]; then
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update
                apt-get install -y nginx
            elif command -v yum >/dev/null 2>&1; then
                yum install -y nginx
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y nginx
            else
                echo -e "${RED}Unable to detect package manager. Please install Nginx manually.${NC}"
                exit 1
            fi
            systemctl enable nginx
            systemctl start nginx
            echo -e "${GREEN}Nginx has been installed successfully.${NC}"
            return 0
        else
            echo -e "${YELLOW}Nginx installation skipped. Exiting.${NC}"
            exit 1
        fi
    fi
}

# Function to check and configure virtual host
function check_vhost() {
    echo -e "${BLUE}Checking if virtual host is configured...${NC}"
    
    # Check for existing virtual hosts
    vhost_count=$(find /etc/nginx/sites-enabled -type l | wc -l)
    
    if [ "$vhost_count" -gt 1 ] || [ -f /etc/nginx/sites-enabled/default ] && [ "$vhost_count" -eq 1 ]; then
        echo -e "${GREEN}Virtual hosts are configured.${NC}"
        return 0
    else
        echo -e "${YELLOW}No custom virtual hosts detected.${NC}"
        if [ "$CHECK_ONLY" = true ]; then
            return 1
        fi
        
        read -p "Do you want to configure a virtual host now? (y/n): " configure_vhost
        if [[ "$configure_vhost" =~ ^[Yy]$ ]]; then
            configure_virtual_host
            return 0
        else
            echo -e "${YELLOW}Virtual host configuration skipped.${NC}"
            return 1
        fi
    fi
}

# Function to configure a virtual host
function configure_virtual_host() {
    read -p "Enter the domain name for the virtual host (e.g., example.com): " domain_name
    
    if [ -z "$domain_name" ]; then
        echo -e "${RED}No domain name provided. Skipping virtual host configuration.${NC}"
        return 1
    fi
    
    # Create directory structure
    mkdir -p /var/www/$domain_name/html
    chown -R www-data:www-data /var/www/$domain_name
    chmod -R 755 /var/www/$domain_name
    
    # Create a sample index.html
    cat > /var/www/$domain_name/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to $domain_name</title>
</head>
<body>
    <h1>Success! $domain_name is working!</h1>
</body>
</html>
EOF
    
    # Create the virtual host configuration file
    cat > /etc/nginx/sites-available/$domain_name << EOF
server {
    listen 80;
    listen [::]:80;
    
    root /var/www/$domain_name/html;
    index index.html index.htm index.nginx-debian.html;
    
    server_name $domain_name www.$domain_name;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    
    # Enable the virtual host
    if [ -d /etc/nginx/sites-enabled ]; then
        ln -s /etc/nginx/sites-available/$domain_name /etc/nginx/sites-enabled/
    fi
    
    # Test nginx configuration
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl reload nginx
        echo -e "${GREEN}Virtual host for $domain_name has been configured successfully.${NC}"
        return 0
    else
        echo -e "${RED}Nginx configuration test failed. Please check the syntax.${NC}"
        return 1
    fi
}

# Function to check and configure user directories
function setup_userdir() {
    echo -e "${BLUE}Setting up user directories...${NC}"
    
    if [ "$CHECK_ONLY" = true ]; then
        if grep -q "^\s*userdir_module" /etc/nginx/nginx.conf; then
            echo -e "${GREEN}User directories are configured.${NC}"
            return 0
        else
            echo -e "${YELLOW}User directories are not configured.${NC}"
            return 1
        fi
    fi
    
    # Create a configuration file for user directories
    cat > /etc/nginx/conf.d/userdir.conf << EOF
# User directories configuration
server {
    location ~ ^/~(.+?)(/.*)?$ {
        alias /home/\$1/public_html\$2;
        autoindex on;
        index index.html index.htm;
    }
}
EOF
    
    # Create example user directory
    read -p "Enter a username to set up a public_html directory (leave empty to skip): " username
    if [ ! -z "$username" ]; then
        if id "$username" >/dev/null 2>&1; then
            mkdir -p /home/$username/public_html
            cat > /home/$username/public_html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to ~$username</title>
</head>
<body>
    <h1>Welcome to ~$username's personal page!</h1>
</body>
</html>
EOF
            chown -R $username:$username /home/$username/public_html
            chmod -R 755 /home/$username/public_html
            echo -e "${GREEN}User directory for $username has been set up. Access it at http://your-domain/~$username/${NC}"
        else
            echo -e "${YELLOW}User $username does not exist. Skipping user directory setup.${NC}"
        fi
    fi
    
    # Test and reload nginx
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl reload nginx
        echo -e "${GREEN}User directories have been configured successfully.${NC}"
        return 0
    else
        echo -e "${RED}Nginx configuration test failed. Please check the syntax.${NC}"
        return 1
    fi
}

# Function to set up basic authentication
function setup_auth() {
    echo -e "${BLUE}Setting up basic authentication...${NC}"
    
    # Check if htpasswd utility is installed
    if ! command -v htpasswd >/dev/null 2>&1; then
        echo -e "${YELLOW}The htpasswd utility is not installed.${NC}"
        if [ "$CHECK_ONLY" = true ]; then
            return 1
        fi
        
        read -p "Do you want to install apache2-utils package to get htpasswd? (y/n): " install_htpasswd
        if [[ "$install_htpasswd" =~ ^[Yy]$ ]]; then
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update
                apt-get install -y apache2-utils
            elif command -v yum >/dev/null 2>&1; then
                yum install -y httpd-tools
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y httpd-tools
            else
                echo -e "${RED}Unable to detect package manager. Please install apache2-utils or equivalent manually.${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}Authentication setup skipped due to missing dependencies.${NC}"
            return 1
        fi
    fi
    
    # Create directory for auth files if it doesn't exist
    mkdir -p /etc/nginx/auth
    
    # Create a new user for authentication
    read -p "Enter username for authentication: " auth_user
    if [ -z "$auth_user" ]; then
        echo -e "${RED}No username provided. Skipping authentication setup.${NC}"
        return 1
    fi
    
    htpasswd -c /etc/nginx/auth/.htpasswd "$auth_user"
    
    # Ask which location to protect
    read -p "Enter the location to protect with authentication (e.g., /admin/ or / for whole site): " auth_location
    if [ -z "$auth_location" ]; then
        auth_location="/"
    fi
    
    # Ask which virtual host to modify
    if [ -d /etc/nginx/sites-enabled ] && [ "$(ls -A /etc/nginx/sites-enabled)" ]; then
        echo "Available virtual hosts:"
        ls -1 /etc/nginx/sites-enabled
        read -p "Enter the virtual host to modify: " vhost_name
        
        if [ -z "$vhost_name" ] || [ ! -f "/etc/nginx/sites-enabled/$vhost_name" ]; then
            echo -e "${RED}Invalid virtual host. Skipping authentication setup.${NC}"
            return 1
        fi
        
        # Add authentication configuration to the virtual host
        if grep -q "location $auth_location {" /etc/nginx/sites-enabled/$vhost_name; then
            # If the location block already exists, add auth directives to it
            sed -i "/location $auth_location {/a \        auth_basic \"Restricted Area\";\n        auth_basic_user_file /etc/nginx/auth/.htpasswd;" /etc/nginx/sites-enabled/$vhost_name
        else
            # If it doesn't exist, add a new location block
            sed -i "/server_name/a \    location $auth_location {\n        auth_basic \"Restricted Area\";\n        auth_basic_user_file /etc/nginx/auth/.htpasswd;\n        try_files \$uri \$uri/ =404;\n    }" /etc/nginx/sites-enabled/$vhost_name
        fi
        
        # Test and reload nginx
        nginx -t
        if [ $? -eq 0 ]; then
            systemctl reload nginx
            echo -e "${GREEN}Basic authentication has been set up for location $auth_location on $vhost_name.${NC}"
            return 0
        else
            echo -e "${RED}Nginx configuration test failed. Please check the syntax.${NC}"
            return 1
        fi
    else
        echo -e "${RED}No virtual hosts found. Please configure a virtual host first.${NC}"
        return 1
    fi
}

# Function to set up PAM authentication
function setup_pam_auth() {
    echo -e "${BLUE}Setting up PAM authentication...${NC}"
    
    # Check if required packages are installed
    if ! dpkg -l | grep libnginx-mod-http-auth-pam >/dev/null 2>&1; then
        echo -e "${YELLOW}The nginx PAM module is not installed.${NC}"
        if [ "$CHECK_ONLY" = true ]; then
            return 1
        fi
        
        read -p "Do you want to install the Nginx PAM module? (y/n): " install_pam
        if [[ "$install_pam" =~ ^[Yy]$ ]]; then
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update
                apt-get install -y libnginx-mod-http-auth-pam
            else
                echo -e "${RED}This script currently supports PAM authentication setup only on Debian/Ubuntu systems.${NC}"
                echo -e "${RED}For other distributions, please install the nginx PAM module manually.${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}PAM authentication setup skipped due to missing dependencies.${NC}"
            return 1
        fi
    fi
    
    # Create a PAM service file for Nginx
    cat > /etc/pam.d/nginx << EOF
#%PAM-1.0
auth        required    pam_unix.so shadow nodelay
account     required    pam_unix.so
EOF
    
    # Ask which location to protect
    read -p "Enter the location to protect with PAM authentication (e.g., /admin/ or / for whole site): " pam_location
    if [ -z "$pam_location" ]; then
        pam_location="/"
    fi
    
    # Ask which virtual host to modify
    if [ -d /etc/nginx/sites-enabled ] && [ "$(ls -A /etc/nginx/sites-enabled)" ]; then
        echo "Available virtual hosts:"
        ls -1 /etc/nginx/sites-enabled
        read -p "Enter the virtual host to modify: " vhost_name
        
        if [ -z "$vhost_name" ] || [ ! -f "/etc/nginx/sites-enabled/$vhost_name" ]; then
            echo -e "${RED}Invalid virtual host. Skipping PAM authentication setup.${NC}"
            return 1
        fi
        
        # Add the auth_pam module to nginx.conf if it's not already there
        if ! grep -q "load_module modules/ngx_http_auth_pam_module.so" /etc/nginx/nginx.conf; then
            sed -i '1iload_module modules/ngx_http_auth_pam_module.so;' /etc/nginx/nginx.conf
        fi
        
        # Add PAM authentication configuration to the virtual host
        if grep -q "location $pam_location {" /etc/nginx/sites-enabled/$vhost_name; then
            # If the location block already exists, add auth directives to it
            sed -i "/location $pam_location {/a \        auth_pam \"nginx\";\n        auth_pam_service_name \"nginx\";" /etc/nginx/sites-enabled/$vhost_name
        else
            # If it doesn't exist, add a new location block
            sed -i "/server_name/a \    location $pam_location {\n        auth_pam \"nginx\";\n        auth_pam_service_name \"nginx\";\n        try_files \$uri \$uri/ =404;\n    }" /etc/nginx/sites-enabled/$vhost_name
        fi
        
        # Test and reload nginx
        nginx -t
        if [ $? -eq 0 ]; then
            systemctl reload nginx
            echo -e "${GREEN}PAM authentication has been set up for location $pam_location on $vhost_name.${NC}"
            echo -e "${YELLOW}Note: Users must have local accounts on this system to authenticate.${NC}"
            return 0
        else
            echo -e "${RED}Nginx configuration test failed. Please check the syntax.${NC}"
            return 1
        fi
    else
        echo -e "${RED}No virtual hosts found. Please configure a virtual host first.${NC}"
        return 1
    fi
}

# Function to set up CGI scripting
function setup_cgi() {
    echo -e "${BLUE}Setting up CGI scripting...${NC}"
    
    # Check if required packages are installed
    if ! command -v fcgiwrap >/dev/null 2>&1; then
        echo -e "${YELLOW}The fcgiwrap package is not installed.${NC}"
        if [ "$CHECK_ONLY" = true ]; then
            return 1
        fi
        
        read -p "Do you want to install fcgiwrap? (y/n): " install_fcgiwrap
        if [[ "$install_fcgiwrap" =~ ^[Yy]$ ]]; then
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update
                apt-get install -y fcgiwrap
            elif command -v yum >/dev/null 2>&1; then
                yum install -y fcgiwrap
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y fcgiwrap
            else
                echo -e "${RED}Unable to detect package manager. Please install fcgiwrap manually.${NC}"
                return 1
            fi
            systemctl enable fcgiwrap
            systemctl start fcgiwrap
        else
            echo -e "${YELLOW}CGI setup skipped due to missing dependencies.${NC}"
            return 1
        fi
    fi
    
    # Ask which virtual host to modify
    if [ -d /etc/nginx/sites-enabled ] && [ "$(ls -A /etc/nginx/sites-enabled)" ]; then
        echo "Available virtual hosts:"
        ls -1 /etc/nginx/sites-enabled
        read -p "Enter the virtual host to modify: " vhost_name
        
        if [ -z "$vhost_name" ] || [ ! -f "/etc/nginx/sites-enabled/$vhost_name" ]; then
            echo -e "${RED}Invalid virtual host. Skipping CGI setup.${NC}"
            return 1
        fi
        
        # Create a directory for CGI scripts
        domain_name=$(grep -oP "server_name \K[^;]+" /etc/nginx/sites-enabled/$vhost_name | awk '{print $1}')
        cgi_dir="/var/www/$domain_name/cgi-bin"
        mkdir -p $cgi_dir
        
        # Create a sample CGI script
        cat > $cgi_dir/test.cgi << 'EOF'
#!/bin/bash
echo "Content-type: text/html"
echo ""
echo "<html><head><title>CGI Test</title></head><body>"
echo "<h1>CGI Script is working!</h1>"
echo "<p>Server time: $(date)</p>"
echo "<p>Server name: $SERVER_NAME</p>"
echo "<p>Your IP: $REMOTE_ADDR</p>"
echo "</body></html>"
EOF
        
        chmod +x $cgi_dir/test.cgi
        chown -R www-data:www-data $cgi_dir
        
        # Add CGI configuration to the virtual host
        if ! grep -q "location /cgi-bin/" /etc/nginx/sites-enabled/$vhost_name; then
            sed -i "/server_name/a \    location /cgi-bin/ {\n        gzip off;\n        root /var/www/$domain_name;\n        fastcgi_pass unix:/var/run/fcgiwrap.socket;\n        include fastcgi_params;\n        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;\n    }" /etc/nginx/sites-enabled/$vhost_name
        fi
        
        # Test and reload nginx
        nginx -t
        if [ $? -eq 0 ]; then
            systemctl reload nginx
            echo -e "${GREEN}CGI scripting has been set up for $domain_name.${NC}"
            echo -e "${GREEN}You can test it by accessing http://$domain_name/cgi-bin/test.cgi${NC}"
            return 0
        else
            echo -e "${RED}Nginx configuration test failed. Please check the syntax.${NC}"
            return 1
        fi
    else
        echo -e "${RED}No virtual hosts found. Please configure a virtual host first.${NC}"
        return 1
    fi
}

# Function to install all components
function install_all() {
    echo -e "${BLUE}Starting full installation...${NC}"
    
    check_nginx
    if [ $? -eq 0 ]; then
        check_vhost
        setup_userdir
        setup_auth
        setup_pam_auth
        setup_cgi
        
        echo -e "${GREEN}All components have been installed and configured successfully.${NC}"
    else
        echo -e "${RED}Nginx installation failed. Aborting.${NC}"
        exit 1
    fi
}

# Main script execution
check_root

# Default values for flags
CHECK_ONLY=false
INSTALL_ALL=false
CONFIG_VHOST=false
SETUP_USERDIR=false
SETUP_AUTH=false
SETUP_PAM_AUTH=false
SETUP_CGI=false

# Parse command line arguments
if [ $# -eq 0 ]; then
    display_help
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help)
            display_help
            ;;
        --check-only)
            CHECK_ONLY=true
            ;;
        --install-all)
            INSTALL_ALL=true
            ;;
        --configure-vhost)
            CONFIG_VHOST=true
            ;;
        --setup-userdir)
            SETUP_USERDIR=true
            ;;
        --setup-auth)
            SETUP_AUTH=true
            ;;
        --setup-pam-auth)
            SETUP_PAM_AUTH=true
            ;;
        --setup-cgi)
            SETUP_CGI=true
            ;;
        *)
            echo -e "${RED}Unknown parameter: $1${NC}"
            echo "Use --help to see available options."
            exit 1
            ;;
    esac
    shift
done

# Execute based on the provided flags
if [ "$INSTALL_ALL" = true ]; then
    install_all
else
    check_nginx
    
    if [ "$CONFIG_VHOST" = true ]; then
        check_vhost
    fi
    
    if [ "$SETUP_USERDIR" = true ]; then
        setup_userdir
    fi
    
    if [ "$SETUP_AUTH" = true ]; then
        setup_auth
    fi
    
    if [ "$SETUP_PAM_AUTH" = true ]; then
        setup_pam_auth
    fi
    
    if [ "$SETUP_CGI" = true ]; then
        setup_cgi
    fi
    
    if [ "$CHECK_ONLY" = true ]; then
        echo -e "${BLUE}Check completed. No changes were made.${NC}"
    fi
fi

echo -e "${GREEN}Script execution completed.${NC}"
exit 0