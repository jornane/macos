#!/bin/bash
echo "Build Script for eduVPN (and derivatives)"

echo "Which target do you want to build?"
echo "1. eduVPN"
echo "2. Let's Connect!"
read -p "1-2?" choice
case "$choice" in
  1 ) TARGET="eduVPN"; PRODUCT="eduVPN.app";;
  2 ) TARGET="LetsConnect"; PRODUCT="Let's Connect!.app";;
  * ) echo "Invalid response."; exit 0;;
esac

echo ""
echo "Which signing identity do you want to use?"
echo "1. SURFnet B.V. (ZYJ4TZX4UU)"
echo "2. Egeniq (E85CT7ZDJC)"
echo "3. Other "
read -p "1-3?" choice

# Enter custom Team ID and Team Name
if [ "$choice" == 3 ]
then
  echo "Your Team ID and Team Name must match exactly with the signing identity in your keychain."

  read -p "Enter Team ID: " CUSTOMTEAMID
  read -p "Enter Team Name: " CUSTOMTEAMNAME

  # Simple Team ID Validation. Apple Team ID always consists of 10 characters
  if  ! [ "${#CUSTOMTEAMID}" == 10 ]
  then
    echo "Error: Team ID is not valid"
    exit 1
  fi
fi

case "$choice" in
  1 ) TEAMID="ZYJ4TZX4UU"; SIGNINGIDENTITY="Developer ID Application: SURFnet B.V. ($TEAMID)";;
  2 ) TEAMID="E85CT7ZDJC"; SIGNINGIDENTITY="Developer ID Application: Egeniq ($TEAMID)";;
  3 ) TEAMID="$CUSTOMTEAMID"; SIGNINGIDENTITY="Developer ID Application: $CUSTOMTEAMNAME ($TEAMID)";;
  * ) echo "Invalid response."; exit 1;;
esac

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo ""
echo "You are currently on branch $BRANCH."

if [[ $BRANCH != "release/"* ]]
then
  echo ""
  echo "You must always build from a release branch. Switch to the correct branch or ask the developer to create it for you."
  exit
fi

VERSION=$(git rev-parse --abbrev-ref HEAD | cut -d "/" -f 2)

echo ""
read -p "Continue building $PRODUCT version $VERSION (using $SIGNINGIDENTITY) (y/n)?" choice
case "$choice" in
  y|Y ) ;;
  n|N ) exit 0;;
  * ) echo "Invalid response."; exit 1;;
esac

FILENAME="$TARGET-$VERSION"

echo ""
echo "$(tput setaf 2)Bootstrapping dependencies using carthage$(tput sgr 0)"

# Check if Carthage is installed
if ! [ -x "$(command -v carthage)" ]; then
  echo 'Carthage is not installed. Installing Carthage' >&2

  # Check if Homebrew is installed
  if ! [ -x "$(command -v brew)" ]; then
    echo 'Error: Homebrew is not installed. Install Homebrew manually please from https://brew.sh' >&2
    exit 1
  fi

  brew install carthage
fi

# This is a workaround for getting Carthage to work with Xcode 10
tee ${PWD}/Carthage/64bit.xcconfig <<-'EOF'
ARCHS = $(ARCHS_STANDARD_64_BIT)
EOF

XCODE_XCCONFIG_FILE="${PWD}/Carthage/64bit.xcconfig" carthage bootstrap --cache-builds --platform macOS

echo ""
echo "$(tput setaf 2)Building and archiving$(tput sgr 0)"
xcodebuild archive -project eduVPN.xcodeproj -scheme $TARGET -archivePath $FILENAME.xcarchive DEVELOPMENT_TEAM=$TEAMID

echo ""
echo "$(tput setaf 2)Exporting$(tput sgr 0)"
/usr/libexec/PlistBuddy -c "Set :teamID \"$TEAMID\"" ExportOptions.plist
xcodebuild -exportArchive -archivePath $FILENAME.xcarchive -exportPath $FILENAME -exportOptionsPlist ExportOptions.plist

echo ""
echo "$(tput setaf 2)Re-signing up and down scripts$(tput sgr 0)"

DOWN=$(find $FILENAME -name "*.down.*.sh" -print)
codesign -f -s "$SIGNINGIDENTITY" "$DOWN"
UP=$(find $FILENAME -name "*.up.*.sh" -print)
codesign -f -s "$SIGNINGIDENTITY" "$UP"
LEASEWATCH=$(find $FILENAME -name "leasewatch.sh" -print)
codesign -f -s "$SIGNINGIDENTITY" "$LEASEWATCH"

echo ""
echo "Which distribution format do you want to use?"
echo "1. None (recommended for local usage)"
echo "2. create-dmg (recommended for 3rd party distribution)"
echo "3. DropDMG (recomended for eduVPN distribution) "
read -p "1-3?" choice

if [ "$choice" == 1 ]
then
  echo ""
  echo "Done!"
fi

if [ "$choice" == 2 ]
then
  # Check if create-dmg is installed
  if ! [ -x "$(command -v create-dmg)" ]; then
    # Check if HomeBrew is installed
    if ! [ -x "$(command -v brew)" ]; then
      echo 'Error: Homebrew is not installed. Install Homebrew manually please from https://brew.sh' >&2
      exit 1
    fi

    brew install create-dmg
  fi

  INSTALLERFILENAME="$FILENAME.dmg"

  echo ""
  echo "$(tput setaf 2)Creating a disk image$(tput sgr 0)"

  create-dmg \
  --volname "$TARGET" \
  --window-pos 490 350 \
  --window-size 490 350 \
  --icon-size 100 \
  --icon "$PRODUCT" 100 155 \
  --hide-extension "$PRODUCT" \
  --app-drop-link 370 155 \
   $INSTALLERFILENAME \
  $FILENAME"/$PRODUCT"
  codesign -f -s "$SIGNINGIDENTITY" $INSTALLERFILENAME

  echo ""
  echo "Done!"
fi

if [ "$choice" == 3 ]
then
  echo ""
  echo "$(tput setaf 2)Creating a disk image$(tput sgr 0)"
  # The configuration eduVPN can be used for all products
  echo "Using: dropdmg --config-name \"eduVPN\" --signing-identity=\"$SIGNINGIDENTITY\" \"$FILENAME/$PRODUCT\""
  dropdmg --config-name "eduVPN" --signing-identity="$SIGNINGIDENTITY" "$FILENAME/$PRODUCT"

  echo ""
  echo "$(tput setaf 2)Creating app cast XML$(tput sgr 0)"
  DISTRIBUTIONPATH="../eduvpn-macos-distrib"
  # Assumptions are being made about the location of this script
  # Also, this often fails due to extended attribute
  echo "Using: $DISTRIBUTIONPATH/generate_appcast $DISTRIBUTIONPATH/dsa_priv.pem $DISTRIBUTIONPATH/updates/"
  $DISTRIBUTIONPATH/generate_appcast $DISTRIBUTIONPATH/dsa_priv.pem $DISTRIBUTIONPATH/updates/

  echo ""
  echo "Done! You can now upload the files in the updates folders to your file server. Also remember to merge the release branch into master and tag it."
fi
