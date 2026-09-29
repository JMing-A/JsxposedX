#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PIGEON_DIR="$PROJECT_DIR/lib/pigeons"
DART_OUT_DIR="$PROJECT_DIR/lib/generated"
KOTLIN_SRC_ROOT="$PROJECT_DIR/android/app/src/main/kotlin"
BASE_PACKAGE="com.jsxposed.x"
WATCH_INTERVAL_SECONDS=1
RUN_ONCE=false

usage() {
  printf 'Usage: %s [--once]\n' "$(basename "$0")"
  printf '  --once  Generate all Pigeon bridges once and exit.\n'
}

while (($# > 0)); do
  case "$1" in
    --once|-Once)
      RUN_ONCE=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if ! command -v dart >/dev/null 2>&1; then
  printf 'Error: dart was not found in PATH. Install Flutter/Dart first.\n' >&2
  exit 1
fi

if [[ ! -d "$PIGEON_DIR" ]]; then
  printf 'Error: Pigeon source directory does not exist: %s\n' "$PIGEON_DIR" >&2
  exit 1
fi

preserved_case_name() {
  local directory="$1"
  local expected_name="$2"
  local entry

  if [[ -d "$directory" ]]; then
    while IFS= read -r -d '' entry; do
      if [[ "$(basename "$entry" | tr '[:upper:]' '[:lower:]')" == \
            "$(printf '%s' "$expected_name" | tr '[:upper:]' '[:lower:]')" ]]; then
        basename "$entry"
        return
      fi
    done < <(find "$directory" -maxdepth 1 -type f -print0)
  fi
  printf '%s\n' "$expected_name"
}

class_name_for_file() {
  local file_name="$1"
  local class_name=""
  local part
  local old_ifs="$IFS"

  IFS='_'
  read -r -a parts <<< "$file_name"
  IFS="$old_ifs"
  for part in "${parts[@]}"; do
    [[ -z "$part" ]] && continue
    class_name+="$(printf '%s%s' "${part:0:1}" "${part:1}" | \
      awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')"
  done
  printf '%s\n' "$class_name"
}

run_pigeon() {
  local input_file="$1"
  local relative_path="${input_file#"$PIGEON_DIR"/}"
  local relative_dir
  local file_name
  local dart_out
  local kotlin_package
  local kotlin_out_dir
  local class_name
  local kotlin_file_name
  local impl_file_name
  local kotlin_file
  local impl_file

  relative_dir="$(dirname "$relative_path")"
  file_name="$(basename "$input_file" .dart)"
  dart_out="$DART_OUT_DIR/$file_name.g.dart"

  if [[ "$relative_dir" == "." ]]; then
    kotlin_package="$BASE_PACKAGE"
  else
    kotlin_package="$BASE_PACKAGE.${relative_dir//\//.}"
  fi
  kotlin_out_dir="$KOTLIN_SRC_ROOT/${kotlin_package//.//}"
  class_name="$(class_name_for_file "$file_name")"
  kotlin_file_name="$(preserved_case_name "$kotlin_out_dir" "${class_name}Native.g.kt")"
  impl_file_name="$(preserved_case_name "$kotlin_out_dir" "${class_name}NativeImpl.kt")"
  kotlin_file="$kotlin_out_dir/$kotlin_file_name"
  impl_file="$kotlin_out_dir/$impl_file_name"

  printf '\n>>> [Generating] %s\n' "$file_name"
  mkdir -p "$DART_OUT_DIR" "$kotlin_out_dir"

  if [[ ! -f "$impl_file" ]]; then
    printf '%s\n' \
      "package $kotlin_package" \
      '' \
      'import android.content.Context' \
      '' \
      "class ${class_name}NativeImpl(val context: Context) : ${class_name}Native {" \
      "    // TODO: Implement the ${class_name}Native interface." \
      '}' > "$impl_file"
    printf '>>> Created Impl template: %s\n' "${impl_file#"$PROJECT_DIR"/}"
  fi

  (
    cd "$PROJECT_DIR"
    dart run pigeon \
      --input "${input_file#"$PROJECT_DIR"/}" \
      --dart_out "${dart_out#"$PROJECT_DIR"/}" \
      --kotlin_out "${kotlin_file#"$PROJECT_DIR"/}" \
      --kotlin_package "$kotlin_package"
  )
}

generate_all() {
  local input_file
  local failed=0
  while IFS= read -r input_file; do
    run_pigeon "$input_file" || failed=1
  done < <(find "$PIGEON_DIR" -type f -name '*.dart' -print | LC_ALL=C sort)
  return "$failed"
}

if ! generate_all; then
  printf '\nError: one or more Pigeon generators failed.\n' >&2
  exit 1
fi

if [[ "$RUN_ONCE" == true ]]; then
  printf '\n>>> [Once] Initial code generation complete.\n'
  exit 0
fi

marker_file="$(mktemp "${TMPDIR:-/tmp}/jsxposed-pigeon.XXXXXX")"
trap 'rm -f "$marker_file" "$marker_file.next"' EXIT INT TERM
touch "$marker_file"
printf '\n>>> [Watcher] Watching %s for changes...\n' "${PIGEON_DIR#"$PROJECT_DIR"/}"

while true; do
  sleep "$WATCH_INTERVAL_SECONDS"
  touch "$marker_file.next"
  changed=false
  while IFS= read -r input_file; do
    changed=true
    run_pigeon "$input_file" || printf '>>> Generation failed: %s\n' "$input_file" >&2
  done < <(find "$PIGEON_DIR" -type f -name '*.dart' -newer "$marker_file" -print)
  mv "$marker_file.next" "$marker_file"
  if [[ "$changed" == true ]]; then
    printf '>>> [Watcher] Waiting for changes...\n'
  fi
done
