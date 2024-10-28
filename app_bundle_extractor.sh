#!/bin/bash

# Define colors with tput
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
YELLOW=$(tput setaf 3)
NC=$(tput sgr0) # No Color

# Function to show loading animation
show_loading() {
  local PID=$!
  local delay=0.1
  local progress=0
  local max_progress=50  # Defines the width of the loading bar
  echo -n "["
  while ps -p $PID > /dev/null; do
    # Display progress
    if [ $progress -lt $max_progress ]; then
      progress=$((progress + 1))
      echo -n "="
    fi
    sleep $delay
  done
  while [ $progress -lt $max_progress ]; do
    echo -n "="
    progress=$((progress + 1))
  done
  echo "] ${GREEN}Done!${NC}"
}

# Step 1: Parse named arguments
for ARG in "$@"; do
  case $ARG in
    keystore=*)
      KEYSTORE_FOLDER="${ARG#*=}"
      shift
      ;;
    source=*)
      AAB_FILE="${ARG#*=}"
      shift
      ;;
    output=*)
      OUTPUT_DIR="${ARG#*=}"
      shift
      ;;
    *)
      echo "Invalid argument: $ARG"
      echo "${YELLOW}Usage:${NC} $0 keystore=/path/to/keystore_folder source=/path/to/your_app.aab output=/path/output"
      exit 1
      ;;
  esac
done

# Verify that all required arguments are provided
if [[ -z "$KEYSTORE_FOLDER" || -z "$AAB_FILE" || -z "$OUTPUT_DIR" ]]; then
  echo "${RED}Error:${NC} Missing required arguments."
  echo "${YELLOW}Usage:${NC} $0 keystore=/path/to/keystore_folder source=/path/to/your_app.aab output=/path/output"
  exit 1
fi

# Step 2: Locate .txt and .keystore files within the specified folder
KEYSTORE_INFO_FILE=$(find "$KEYSTORE_FOLDER" -type f -name "*.txt" -print -quit)
KEYSTORE_FILE=$(find "$KEYSTORE_FOLDER" -type f ! -name "*.txt" -print -quit)

# Check if files were found
if [[ -z "$KEYSTORE_INFO_FILE" ]]; then
  echo "${RED}Error:${NC} .txt file with keystore information not found in the specified folder: $KEYSTORE_FOLDER"
  exit 1
fi

if [[ -z "$KEYSTORE_FILE" ]]; then
  echo "${RED}Error:${NC} Keystore file not found in the specified folder: $KEYSTORE_FOLDER"
  exit 1
fi

if [[ ! -f "$AAB_FILE" ]]; then
  echo "${RED}Error:${NC} .aab file not found at the specified path: $AAB_FILE"
  exit 1
fi

# Step 3: Read alias and passwords from the provided .txt file
KEYSTORE_ALIAS=$(sed -n 's/^Key alias: //p' "$KEYSTORE_INFO_FILE")
KEYSTORE_PASSWORD=$(sed -n 's/^Key password: //p' "$KEYSTORE_INFO_FILE")
KEY_PASSWORD=$(sed -n 's/^Key password: //p' "$KEYSTORE_INFO_FILE")

# Verify the extracted values
if [[ -z "$KEYSTORE_ALIAS" || -z "$KEYSTORE_PASSWORD" || -z "$KEY_PASSWORD" ]]; then
  echo "${RED}Error:${NC} Missing values in $KEYSTORE_INFO_FILE. Ensure 'Key alias:', 'Keystore password:', and 'Key password:' are provided."
  exit 1
fi

# Step 4: List available devices and prompt user to select one
echo "${BLUE}Available devices for deployment:${NC}"
DEVICE_LIST=($(adb devices | grep -v "List" | awk '{print $1}'))

if [[ ${#DEVICE_LIST[@]} -eq 0 ]]; then
  echo "No devices found. Please connect a device or start an emulator."
  exit 1
fi

for i in "${!DEVICE_LIST[@]}"; do
  echo "${GREEN}$((i+1)).${NC} ${DEVICE_LIST[$i]}"
done

read -p "Enter the number of the device you wish to deploy to: " DEVICE_INDEX
DEVICE_INDEX=$((DEVICE_INDEX-1))

if [[ -z "${DEVICE_LIST[$DEVICE_INDEX]}" ]]; then
  echo "Invalid selection. Exiting."
  exit 1
fi

TARGET_DEVICE=${DEVICE_LIST[$DEVICE_INDEX]}
echo "Selected device: $TARGET_DEVICE"

# Step 5: Extract and sign the APK
mkdir -p "$OUTPUT_DIR"

echo "Extracting and signing APK from ${BLUE}$AAB_FILE${NC} using keystore ${BLUE}$KEYSTORE_FILE${NC}..."
(bundletool build-apks \
  --bundle="$AAB_FILE" \
  --output="$OUTPUT_DIR/output.apks" \
  --mode=universal \
  --ks="$KEYSTORE_FILE" \
  --ks-key-alias="$KEYSTORE_ALIAS" \
  --ks-pass="pass:$KEYSTORE_PASSWORD" \
  --key-pass="pass:$KEY_PASSWORD" > /dev/null 2>&1) &
show_loading
  
# Step 6: Unzip APK files with loading animation
echo "${YELLOW}Unzipping APK files...${NC}"
(unzip -o "$OUTPUT_DIR/output.apks" -d "$OUTPUT_DIR" > /dev/null) &
show_loading

echo "Installing APK on device ${YELLOW}$TARGET_DEVICE...${NC}" && \
(adb -s "$TARGET_DEVICE" install "$OUTPUT_DIR/universal.apk" > /dev/null 2>&1) &
show_loading
echo "${GREEN}APK installed successfully on $TARGET_DEVICE.${NC}" || echo "An ${RED}error${NC} occurred during extraction or installation."
