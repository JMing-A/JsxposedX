#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANDROID_DIR="$REPO_ROOT/android"
GRADLEW="$ANDROID_DIR/gradlew"
WORKSPACE_XML="$REPO_ROOT/.idea/workspace.xml"
PUBSPEC_PATH="$REPO_ROOT/pubspec.yaml"
LOCAL_PROPERTIES_PATH="$ANDROID_DIR/local.properties"
GRADLE_LOG_PATH="$REPO_ROOT/build/logs/install-debug.log"

DEVICE_ID=""
GRADLE_TASK=":app:installDebug"
APPLICATION_ID="com.jsxposed.x"
ACTIVITY_NAME=".MainActivity"
FLUTTER_EXECUTABLE="flutter"
GRADLE_JAVA_HOME=""
POST_INSTALL_DELAY_SECONDS=8
FORCE_STOP_BEFORE_LAUNCH=true
SKIP_INSTALL=false
SKIP_LAUNCH=false
SKIP_ATTACH=false
GRADLE_ARGS=(
  "-Pandroid.injected.invoked.from.ide=true"
  "--console=plain"
  "--no-daemon"
)
ATTACH_ARGS=()

usage() {
  cat <<'EOF'
Usage: run_install_debug.sh [options]

Options:
  -s, --device-id ID              Target adb device serial.
      --gradle-task TASK          Gradle install task (default: :app:installDebug).
      --gradle-arg ARG            Append a Gradle argument; may be repeated.
      --application-id ID         Android application id (default: com.jsxposed.x).
      --activity-name NAME        Launch activity or full component.
      --flutter-executable PATH   Flutter command or executable path.
      --java-home PATH            JDK for Gradle (macOS default: JDK 17).
      --attach-arg ARG            Append a flutter attach argument; may be repeated.
      --post-install-delay SEC    Delay after install (default: 8).
      --no-force-stop             Do not force-stop before launch.
      --skip-install              Skip the Gradle install step.
      --skip-launch               Skip force-stop and app launch.
      --skip-attach               Skip flutter attach.
  -h, --help                      Show this help.
EOF
}

require_value() {
  if (($# < 2)) || [[ -z "$2" ]]; then
    printf 'Error: %s requires a value.\n' "$1" >&2
    exit 2
  fi
}

while (($# > 0)); do
  case "$1" in
    -s|--device-id)
      require_value "$@"
      DEVICE_ID="$2"
      shift 2
      ;;
    --gradle-task)
      require_value "$@"
      GRADLE_TASK="$2"
      shift 2
      ;;
    --gradle-arg)
      require_value "$@"
      GRADLE_ARGS+=("$2")
      shift 2
      ;;
    --application-id)
      require_value "$@"
      APPLICATION_ID="$2"
      shift 2
      ;;
    --activity-name)
      require_value "$@"
      ACTIVITY_NAME="$2"
      shift 2
      ;;
    --flutter-executable)
      require_value "$@"
      FLUTTER_EXECUTABLE="$2"
      shift 2
      ;;
    --java-home)
      require_value "$@"
      GRADLE_JAVA_HOME="$2"
      shift 2
      ;;
    --attach-arg)
      require_value "$@"
      ATTACH_ARGS+=("$2")
      shift 2
      ;;
    --post-install-delay)
      require_value "$@"
      POST_INSTALL_DELAY_SECONDS="$2"
      shift 2
      ;;
    --no-force-stop)
      FORCE_STOP_BEFORE_LAUNCH=false
      shift
      ;;
    --skip-install)
      SKIP_INSTALL=true
      shift
      ;;
    --skip-launch)
      SKIP_LAUNCH=true
      shift
      ;;
    --skip-attach)
      SKIP_ATTACH=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$POST_INSTALL_DELAY_SECONDS" =~ ^[0-9]+$ ]]; then
  printf 'Error: --post-install-delay must be a non-negative integer.\n' >&2
  exit 2
fi

assert_tool_available() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1 && [[ ! -x "$command_name" ]]; then
    printf 'Error: required command not found: %s\n' "$command_name" >&2
    exit 1
  fi
}

sync_flutter_version() {
  if [[ ! -f "$PUBSPEC_PATH" ]]; then
    printf 'Error: pubspec.yaml not found: %s\n' "$PUBSPEC_PATH" >&2
    exit 1
  fi

  local version_value
  local version_name
  local version_code
  local temp_file
  version_value="$(awk '
    /^[[:space:]]*version[[:space:]]*:/ {
      sub(/^[[:space:]]*version[[:space:]]*:[[:space:]]*/, "")
      sub(/[[:space:]]*#.*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  ' "$PUBSPEC_PATH")"

  if [[ ! "$version_value" =~ ^([^+[:space:]]+)\+([0-9]+)$ ]]; then
    printf 'Error: unsupported or missing pubspec version: %s\n' "$version_value" >&2
    exit 1
  fi
  version_name="${BASH_REMATCH[1]}"
  version_code="${BASH_REMATCH[2]}"

  mkdir -p "$(dirname "$LOCAL_PROPERTIES_PATH")"
  [[ -f "$LOCAL_PROPERTIES_PATH" ]] || touch "$LOCAL_PROPERTIES_PATH"
  temp_file="$(mktemp "${TMPDIR:-/tmp}/jsxposed-local-properties.XXXXXX")"
  trap 'rm -f "${temp_file:-}"' RETURN
  awk -v version_name="$version_name" -v version_code="$version_code" '
    BEGIN { found_name = 0; found_code = 0 }
    /^flutter\.versionName=/ {
      print "flutter.versionName=" version_name
      found_name = 1
      next
    }
    /^flutter\.versionCode=/ {
      print "flutter.versionCode=" version_code
      found_code = 1
      next
    }
    { print }
    END {
      if (!found_name) print "flutter.versionName=" version_name
      if (!found_code) print "flutter.versionCode=" version_code
    }
  ' "$LOCAL_PROPERTIES_PATH" > "$temp_file"
  chmod --reference="$LOCAL_PROPERTIES_PATH" "$temp_file" 2>/dev/null || chmod 644 "$temp_file"
  mv "$temp_file" "$LOCAL_PROPERTIES_PATH"
  trap - RETURN
  printf 'Synced Flutter version: versionName=%s, versionCode=%s\n' \
    "$version_name" "$version_code"
}

connected_device_ids() {
  assert_tool_available adb
  adb devices | awk 'NR > 1 && $2 == "device" { print $1 }'
}

android_studio_selected_device_id() {
  [[ -f "$WORKSPACE_XML" ]] || return 0
  sed -n 's/.*serial=\([^]&<"]*\).*/\1/p' "$WORKSPACE_XML" | head -n 1
}

is_connected_device() {
  local preferred="$1"
  local connected
  [[ -n "$preferred" ]] || return 1
  while IFS= read -r connected; do
    [[ "$connected" == "$preferred" ]] && return 0
  done < <(connected_device_ids)
  return 1
}

resolve_device_id() {
  local preferred
  local devices=()

  if [[ -n "$DEVICE_ID" ]]; then
    printf '%s\n' "$DEVICE_ID"
    return
  fi

  preferred="${ANDROID_SERIAL:-}"
  if [[ -n "$preferred" ]]; then
    printf '%s\n' "$preferred"
    return
  fi

  preferred="$(android_studio_selected_device_id)"
  if is_connected_device "$preferred"; then
    printf '%s\n' "$preferred"
    return
  fi

  while IFS= read -r preferred; do
    [[ -n "$preferred" ]] && devices+=("$preferred")
  done < <(connected_device_ids)

  if ((${#devices[@]} == 1)); then
    printf '%s\n' "${devices[0]}"
  elif ((${#devices[@]} > 1)); then
    printf 'Error: multiple adb devices detected; pass --device-id.\n' >&2
    exit 1
  else
    printf 'Error: no adb device detected.\n' >&2
    exit 1
  fi
}

resolve_gradle_java_home() {
  if [[ -n "$GRADLE_JAVA_HOME" ]]; then
    printf '%s\n' "$GRADLE_JAVA_HOME"
    return
  fi

  if [[ "$(uname -s)" == "Darwin" && -x /usr/libexec/java_home ]]; then
    /usr/libexec/java_home -v 17 2>/dev/null && return
  fi

  if [[ -n "${JAVA_HOME:-}" ]]; then
    printf '%s\n' "$JAVA_HOME"
    return
  fi

  return 1
}

run_checked() {
  local description="$1"
  local working_directory="$2"
  local exit_code=0
  shift 2
  printf '\n==> %s\n' "$description"
  printf '    '
  printf '%q ' "$@"
  printf '\n'
  (cd "$working_directory" && "$@") || exit_code=$?
  if ((exit_code != 0)); then
    printf 'Error: %s failed with exit code %d.\n' \
      "$description" "$exit_code" >&2
    return "$exit_code"
  fi
}

run_gradle_checked() {
  local description="$1"
  shift
  mkdir -p "$(dirname "$GRADLE_LOG_PATH")"
  printf '\n==> %s\n' "$description"
  printf '    '
  printf '%q ' "$@"
  printf '\n'
  printf '    Gradle output: %s\n' "$GRADLE_LOG_PATH"

  set +e
  (cd "$ANDROID_DIR" && "$@") 2>&1 | tee "$GRADLE_LOG_PATH"
  local gradle_status="${PIPESTATUS[0]}"
  set -e
  if ((gradle_status != 0)); then
    printf 'Error: %s failed with exit code %s.\n' \
      "$description" "$gradle_status" >&2
    printf 'See Gradle log: %s\n' "$GRADLE_LOG_PATH" >&2
    return "$gradle_status"
  fi
}

if [[ ! -f "$GRADLEW" ]]; then
  printf 'Error: Gradle wrapper not found: %s\n' "$GRADLEW" >&2
  exit 1
fi

if [[ -x "$GRADLEW" ]]; then
  GRADLE_COMMAND=("$GRADLEW")
else
  GRADLE_COMMAND=(/usr/bin/env bash "$GRADLEW")
fi

sync_flutter_version

RESOLVED_JAVA_HOME="$(resolve_gradle_java_home || true)"
if [[ -n "$RESOLVED_JAVA_HOME" ]]; then
  if [[ ! -x "$RESOLVED_JAVA_HOME/bin/java" ]]; then
    printf 'Error: Java executable not found under JAVA_HOME: %s\n' \
      "$RESOLVED_JAVA_HOME" >&2
    exit 1
  fi
  printf 'Using Gradle JDK: %s\n' "$RESOLVED_JAVA_HOME"
fi

if [[ "$ACTIVITY_NAME" == */* ]]; then
  LAUNCH_COMPONENT="$ACTIVITY_NAME"
else
  LAUNCH_COMPONENT="$APPLICATION_ID/$ACTIVITY_NAME"
fi

RESOLVED_DEVICE_ID=""
if [[ "$SKIP_INSTALL" != true || "$SKIP_LAUNCH" != true || "$SKIP_ATTACH" != true ]]; then
  RESOLVED_DEVICE_ID="$(resolve_device_id)"
  printf 'Using device: %s\n' "$RESOLVED_DEVICE_ID"
fi

if [[ "$SKIP_INSTALL" != true ]]; then
  run_gradle_checked \
    "Installing app with Gradle task $GRADLE_TASK" \
    env "ANDROID_SERIAL=$RESOLVED_DEVICE_ID" \
      ${RESOLVED_JAVA_HOME:+"JAVA_HOME=$RESOLVED_JAVA_HOME"} \
      "${GRADLE_COMMAND[@]}" "$GRADLE_TASK" "${GRADLE_ARGS[@]}"

  if ((POST_INSTALL_DELAY_SECONDS > 0)); then
    printf '\n==> Waiting %s second(s) for package replacement and LSPosed rescan\n' \
      "$POST_INSTALL_DELAY_SECONDS"
    sleep "$POST_INSTALL_DELAY_SECONDS"
  fi
fi

if [[ "$SKIP_LAUNCH" != true ]]; then
  assert_tool_available adb
  ADB_ARGS=(-s "$RESOLVED_DEVICE_ID")
  if [[ "$FORCE_STOP_BEFORE_LAUNCH" == true && -n "$APPLICATION_ID" ]]; then
    run_checked \
      "Force-stopping $APPLICATION_ID before launch" \
      "$REPO_ROOT" \
      adb "${ADB_ARGS[@]}" shell am force-stop "$APPLICATION_ID"
  fi
  run_checked \
    "Launching $LAUNCH_COMPONENT" \
    "$REPO_ROOT" \
    adb "${ADB_ARGS[@]}" shell am start \
      -a android.intent.action.MAIN \
      -c android.intent.category.LAUNCHER \
      -n "$LAUNCH_COMPONENT"
fi

if [[ "$SKIP_ATTACH" != true ]]; then
  assert_tool_available "$FLUTTER_EXECUTABLE"
  run_checked \
    "Attaching Flutter debugger" \
    "$REPO_ROOT" \
    "$FLUTTER_EXECUTABLE" attach -d "$RESOLVED_DEVICE_ID" "${ATTACH_ARGS[@]}"
fi

printf '\n==> Finished.\n'
if [[ "$SKIP_ATTACH" == true ]]; then
  printf "Tip: use Android Studio's Flutter Attach for hot reload controls.\n"
fi
