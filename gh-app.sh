#!/bin/bash

set -o pipefail

GH_APP_WRAPPER_VERSION="0.0.1"
GH_APP_WRAPPER_HOME="$HOME/.gh-app-wrapper"

# GH app wrapper tool latest release URL
GH_AUTH_WRAPPER_URL="https://raw.githubusercontent.com/adheus/gh-app-wrapper/main/gh-app.sh"


PROFILE_RC="$HOME/.zshrc"
if [[ $SHELL == "bash"* ]]; then
    PROFILE_RC="$HOME/.bashrc"
fi


# Downloads latest gh app wrapper script and store it 
setup() {
    echo ""
    echo "################################"
    echo "#      GH APP WRAPPER TOOL     #"
    echo "#         version $GH_APP_WRAPPER_VERSION        #"
    echo "################################"
    echo ""
    echo "Installing gh app wrapper tool..."
    GH_APP_WRAPPER_BIN="$GH_APP_WRAPPER_HOME/bin"
    if [[ ! -d "$GH_APP_WRAPPER_BIN" ]]; then
        mkdir -p "$GH_APP_WRAPPER_BIN"
    fi

    # Download a copy of the gh app wrapper script to the home path
    GH_APP_WRAPPER_FILEPATH="$GH_APP_WRAPPER_HOME/bin/gh-app"
    GH_APP_WRAPPER_FILEPATH_TEMP="$GH_APP_WRAPPER_HOME/bin/gh-app.update"

    # Remove any failed temporary file 
    if [[ -f "$GH_APP_WRAPPER_FILEPATH_TEMP" ]]; then
        rm "$GH_APP_WRAPPER_FILEPATH_TEMP"
    fi
    # Download script into temporary file 
    if curl "$GH_AUTH_WRAPPER_URL" -L -o "$GH_APP_WRAPPER_FILEPATH_TEMP"; then
        # If script already installed, remove it 
        if [[ -f "$GH_APP_WRAPPER_FILEPATH" ]]; then
            rm "$GH_APP_WRAPPER_FILEPATH"
        fi
        mv "$GH_APP_WRAPPER_FILEPATH_TEMP" "$GH_APP_WRAPPER_FILEPATH"
        chmod +x "$GH_APP_WRAPPER_FILEPATH"
    fi

    # Checks if gh-app wrapper home was already present in profilerc
    SCRIPT_IN_PATH="$(cat "$PROFILE_RC" | grep $GH_APP_WRAPPER_BIN)"
    echo "$SCRIPT_IN_PATH" 

    # If no .gh-app/bin is present on profile, set it 
    if [[ -z "$SCRIPT_IN_PATH" ]]; then
        {
            echo "";
            echo "# gh-app configuration";
            echo 'export PATH="$HOME/.gh-app-wrapper/bin:$PATH"';
        } >>"$PROFILE_RC"
    fi

    # Let's make script available in this session too
    export PATH="$HOME/.gh-app-wrapper/bin:$PATH"
    
    # Check for brew installation
    if ! command -v brew &> /dev/null
    then
        echo "ERROR: Homebrew could not be found. Please install it to continue."
        exit 1
    fi

    # Check if github cli is installed
    # If not, install it
    if ! command -v gh &> /dev/null
    then
        echo "GitHub CLI could not be found. Installing..."
        brew install gh

    fi

    # Check if jq is installed
    # If not, install it
    if ! command -v jq &> /dev/null
    then
        echo "jq could not be found. Installing..."
        brew install jq
    fi


    # Check if .gitconfig already exists, and backup it
    if [[ -f "$HOME/.gitconfig" ]]; then
        mv "$HOME/.gitconfig" "$HOME/.gitconfig.bak"
    fi

    # Add gh-app to resolve credentials
    git config --global credential.helper '!gh-app auth git-credential'

    echo ""
    echo "GH APP WRAPPER TOOL INSTALLED SUCCESSFULLY"
}


authenticate() {
    app_id=$GITHUB_APP_ID
    if [ -z "$app_id" ]; then
      echo "ERROR: GITHUB_APP_ID is not set"
      exit 1
    fi

    installation_id=$GITHUB_INSTALLATION_ID
    if [ -z "$installation_id" ]; then
      echo "ERROR: GITHUB_INSTALLATION_ID is not set"
      exit 1
    fi
    if [ -z "$GITHUB_PRIVATE_KEY_PATH" ]; then
      echo "ERROR: GITHUB_PRIVATE_KEY_PATH is not set"
      exit 1
    fi
    if [ ! -f "$GITHUB_PRIVATE_KEY_PATH" ]; then
      echo "ERROR: GITHUB_PRIVATE_KEY_PATH is not a file"
      exit 1
    fi
    pem=$( cat "$GITHUB_PRIVATE_KEY_PATH" ) # file path of the private key as second argument

    now=$(date +%s)
    iat=$((${now} - 60)) # Issues 60 seconds in the past
    exp=$((${now} + 600)) # Expires 10 minutes in the future

    b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

    header_json='{
        "typ":"JWT",
        "alg":"RS256"
    }'
    # Header encode
    header=$( echo -n "${header_json}" | b64enc )

    payload_json='{
        "iat":'"${iat}"',
        "exp":'"${exp}"',
        "iss":'"${app_id}"'
    }'
    # Payload encode
    payload=$( echo -n "${payload_json}" | b64enc )

    # Signature
    header_payload="${header}"."${payload}"
    signature=$(
        openssl dgst -sha256 -sign <(echo -n "${pem}") \
        <(echo -n "${header_payload}") | b64enc
    )

    # Create JWT
    JWT="${header_payload}"."${signature}"

    response=$(curl -s --request POST \
      --url "https://api.github.com/app/installations/$installation_id/access_tokens" \
      --header "Accept: application/vnd.github+json" \
      --header "Authorization: Bearer $JWT" \
      --header "X-GitHub-Api-Version: 2022-11-28")

    # Store token in a file
    token=$(echo $response | jq -r '.token')
    TOKEN_PATH="$HOME/.gh-app-wrapper/token.txt"
    echo $token > $TOKEN_PATH

    # Use the token to authenticate gh
    gh auth login --with-token < $TOKEN_PATH

    # Remove token file
    rm $TOKEN_PATH
}

# If we have arguments, authenticate and call gh with the arguments
if [ $# -gt 0 ]; then
    authenticate
    gh $@
else
    setup
fi
