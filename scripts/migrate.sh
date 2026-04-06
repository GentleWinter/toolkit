#!/usr/bin/env bash

set -euo pipefail

echo "====================================="
echo "        EF Core Migration Tool"
echo "====================================="

print_line() {
  printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '='
}

find_projects() {
  local pattern="$1"
  find . -type f -name "$pattern" | sort
}

select_project() {
  local label="$1"
  shift
  local projects=("$@")

  if [[ ${#projects[@]} -eq 0 ]]; then
    echo "❌ Nenhum projeto $label encontrado." >&2
    exit 1
  fi

  if [[ ${#projects[@]} -eq 1 ]]; then
    echo "✔ $label encontrado automaticamente:" >&2
    echo "  ${projects[0]}" >&2
    echo "" >&2
    printf '%s\n' "${projects[0]}"
    return
  fi

  echo "Selecione o projeto $label:" >&2
  for i in "${!projects[@]}"; do
    echo "$((i+1))) ${projects[$i]}" >&2
  done

  echo "" >&2
  read -r -p "Escolha um número: " index >&2

  if [[ ! "$index" =~ ^[0-9]+$ ]] || (( index < 1 || index > ${#projects[@]} )); then
    echo "❌ Seleção inválida." >&2
    exit 1
  fi

  printf '%s\n' "${projects[$((index-1))]}"
}

check_dotnet() {
  if ! command -v dotnet >/dev/null 2>&1; then
    echo "❌ dotnet não encontrado no PATH."
    exit 1
  fi
}

find_nearest_global_json() {
  local dir="$1"

  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/global.json" ]]; then
      echo "$dir/global.json"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  return 1
}

mapfile -t API_PROJECTS < <(find_projects "*.Api.csproj")
mapfile -t INFRA_PROJECTS < <(find_projects "*.Infra.csproj")

API_PROJECT="$(select_project "API" "${API_PROJECTS[@]}")"
INFRA_PROJECT="$(select_project "Infra" "${INFRA_PROJECTS[@]}")"

echo ""
echo "API Project:   $API_PROJECT"
echo "Infra Project: $INFRA_PROJECT"

check_dotnet

PROJECT_DIR="$(dirname "$API_PROJECT")"
GLOBAL_JSON="$(find_nearest_global_json "$PROJECT_DIR" || true)"

if [[ -n "${GLOBAL_JSON:-}" ]]; then
  echo "📌 global.json encontrado em: $GLOBAL_JSON"
fi

echo ""
echo "Digite o nome da Migration (PascalCase)"
echo "Exemplo: AddExpensesTable"
echo ""

read -r -p "Nome da Migration: " MIGRATION_NAME

if [[ -z "$MIGRATION_NAME" ]]; then
  echo "❌ Nome da migration não pode ser vazio."
  exit 1
fi

echo ""
print_line
echo "📦 Criando migration: $MIGRATION_NAME"
print_line

dotnet ef migrations add "$MIGRATION_NAME" \
  --project "$INFRA_PROJECT" \
  --startup-project "$API_PROJECT"

echo ""
print_line
echo "🚀 Atualizando banco..."
print_line

dotnet ef database update \
  --project "$INFRA_PROJECT" \
  --startup-project "$API_PROJECT"

echo ""
print_line
echo "✅ Migration aplicada com sucesso!"
print_line
