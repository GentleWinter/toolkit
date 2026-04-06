#!/usr/bin/env bash

set -euo pipefail

CURRENT_DIR="$(pwd)"

print_line() {
  printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '='
}

find_test_projects() {
  find "$CURRENT_DIR" -type f \( -name "*[Tt]est*.csproj" -o -name "*.Tests.csproj" \) | sort
}

find_nearest_global_json() {
  local start_dir="$1"
  local dir="$start_dir"

  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/global.json" ]]; then
      echo "$dir/global.json"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  return 1
}

extract_sdk_from_global_json() {
  local global_json="$1"

  if [[ ! -f "$global_json" ]]; then
    return 1
  fi

  grep -oP '"version"\s*:\s*"\K[0-9]+(\.[0-9]+){1,2}' "$global_json" | head -n1
}

extract_target_frameworks() {
  local csproj="$1"

  grep -oP '<TargetFramework>\K[^<]+' "$csproj" 2>/dev/null | head -n1 || true
  grep -oP '<TargetFrameworks>\K[^<]+' "$csproj" 2>/dev/null | head -n1 || true
}

extract_major_from_frameworks() {
  local frameworks_raw="$1"

  if [[ -z "$frameworks_raw" ]]; then
    return 1
  fi

  echo "$frameworks_raw" \
    | tr ';' '\n' \
    | grep -oE 'net[0-9]+(\.[0-9]+)?' \
    | sed -E 's/net([0-9]+).*/\1/' \
    | sort -n \
    | tail -n1
}

list_installed_sdks() {
  dotnet --list-sdks 2>/dev/null | awk '{print $1}'
}

has_sdk_major_installed() {
  local major="$1"

  list_installed_sdks | grep -qE "^${major}\."
}

resolve_required_sdk_major() {
  local csproj="$1"
  local project_dir
  project_dir="$(dirname "$csproj")"

  local global_json
  global_json="$(find_nearest_global_json "$project_dir" || true)"

  if [[ -n "${global_json:-}" ]]; then
    local sdk_version
    sdk_version="$(extract_sdk_from_global_json "$global_json" || true)"
    if [[ -n "${sdk_version:-}" ]]; then
      echo "$sdk_version" | cut -d. -f1
      return 0
    fi
  fi

  local frameworks_raw
  frameworks_raw="$(extract_target_frameworks "$csproj" | paste -sd';' - || true)"

  if [[ -n "${frameworks_raw:-}" ]]; then
    local major
    major="$(extract_major_from_frameworks "$frameworks_raw" || true)"
    if [[ -n "${major:-}" ]]; then
      echo "$major"
      return 0
    fi
  fi

  return 1
}

run_project_tests() {
  local csproj="$1"
  local output_file="$2"

  local project_dir
  project_dir="$(dirname "$csproj")"

  local required_major=""
  required_major="$(resolve_required_sdk_major "$csproj" || true)"

  echo ""
  print_line
  echo "Projeto: $csproj"
  echo "Diretório: $project_dir"

  if [[ -n "$required_major" ]]; then
    echo "Major do SDK inferida: $required_major"
  else
    echo "Não foi possível inferir a major do SDK pelo projeto."
  fi

  if ! command -v dotnet >/dev/null 2>&1; then
    echo "dotnet não encontrado no PATH."
    {
      echo "==============================="
      echo "Projeto: $csproj"
      echo "Erro: dotnet não encontrado no PATH"
      echo "==============================="
      echo ""
    } >> "$output_file"
    return 1
  fi

  if [[ -n "$required_major" ]] && ! has_sdk_major_installed "$required_major"; then
    echo "SDK .NET $required_major não encontrado na máquina."
    echo "SDKs instalados:"
    list_installed_sdks || true

    {
      echo "==============================="
      echo "Projeto: $csproj"
      echo "Erro: SDK .NET $required_major não encontrado"
      echo "SDKs instalados:"
      list_installed_sdks || true
      echo "==============================="
      echo ""
    } >> "$output_file"

    return 1
  fi

  {
    echo "==============================="
    echo "Projeto: $csproj"
    echo "Diretório: $project_dir"
    echo "SDK major inferida: ${required_major:-não identificada}"
    echo "dotnet usado: $(command -v dotnet)"
    echo "==============================="
  } >> "$output_file"

  if [[ -n "$(find_nearest_global_json "$project_dir" || true)" ]]; then
    (
      cd "$project_dir"
      dotnet test "$csproj" --logger "console;verbosity=minimal"
    ) >> "$output_file" 2>&1
  else
    (
      cd "$project_dir"
      dotnet test "$csproj" --logger "console;verbosity=minimal"
    ) >> "$output_file" 2>&1
  fi

  echo "" >> "$output_file"
  echo "OK: testes executados para $csproj"
}

main() {
  echo ""
  echo "Procurando projetos de teste dentro de:"
  echo "$CURRENT_DIR"
  echo ""

  mapfile -t TEST_PROJECTS < <(find_test_projects)

  if [[ ${#TEST_PROJECTS[@]} -eq 0 ]]; then
    echo "Nenhum projeto de teste encontrado neste diretório."
    exit 1
  fi

  echo "Projetos encontrados:"
  for i in "${!TEST_PROJECTS[@]}"; do
    echo "$((i+1))) ${TEST_PROJECTS[$i]}"
  done

  echo ""
  read -r -p "Digite os números separados por espaço ou 'all' para todos: " -a INDEXES

  SELECTED=()

  if [[ ${#INDEXES[@]} -eq 1 && "${INDEXES[0]}" == "all" ]]; then
    SELECTED=("${TEST_PROJECTS[@]}")
  else
    for idx in "${INDEXES[@]}"; do
      if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#TEST_PROJECTS[@]} )); then
        SELECTED+=("${TEST_PROJECTS[$((idx-1))]}")
      else
        echo "Índice inválido ignorado: $idx"
      fi
    done
  fi

  if [[ ${#SELECTED[@]} -eq 0 ]]; then
    echo "Nenhum projeto válido selecionado."
    exit 1
  fi

  echo ""
  read -r -p "Nome do arquivo de saída (default: test-results.txt): " OUTPUT_FILE
  OUTPUT_FILE="${OUTPUT_FILE:-test-results.txt}"

  : > "$OUTPUT_FILE"

  echo ""
  echo "Iniciando execução..."
  echo ""

  local failures=0

  for proj in "${SELECTED[@]}"; do
    if ! run_project_tests "$proj" "$OUTPUT_FILE"; then
      failures=$((failures + 1))
    fi
  done

  echo ""
  print_line
  echo "Execução finalizada."
  echo "Resultado salvo em: $OUTPUT_FILE"

  if [[ "$failures" -gt 0 ]]; then
    echo "Alguns projetos falharam ou não puderam ser executados: $failures"
    exit 1
  fi
}

main "$@"
