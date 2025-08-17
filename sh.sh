#!/usr/bin/env bash
set -euo pipefail

# ========== CONFIG ==========
REPO_NAME="terraform-azurerm-rvs-resource-group"
COSTCENTER="rvs"
MODULE_NAME="resource-group"
OUTPUT_FILE="${REPO_NAME}.yml"

TEMPLATE_FILE="resource.yml"
CATALOG_FILE="fake_catalog_response.json"
MODULE_DIR="."   # ajuste se seu módulo TF estiver em outro caminho

# (Opcional) Filtrar outputs para evitar ruído:
OUTPUT_PREFIX_FILTER="^(resource_group_name|resource_group_location)$"

# Ligue para ver debug de matching (1 = ligado)
DEBUG_MATCH="${DEBUG_MATCH:-0}"

# ========== PRECHECKS ==========
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Erro: '$1' não encontrado no PATH"; exit 1; }; }
need jq; need awk; need sed; need grep

[[ -f "$TEMPLATE_FILE" ]] || { echo "Erro: template '$TEMPLATE_FILE' ausente"; exit 1; }
[[ -f "$CATALOG_FILE"  ]] || { echo "Erro: catálogo '$CATALOG_FILE' ausente"; exit 1; }
[[ -d "$MODULE_DIR"    ]] || { echo "Erro: MODULE_DIR '$MODULE_DIR' não existe"; exit 1; }

mkdir -p "biblioteca/$COSTCENTER"

# ========== COLETA ==========
declare -a inputs=() outputs=()

# variables (ignora linhas comentadas # e //)
while IFS= read -r line; do
  name=$(sed -n 's/.*variable[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$line")
  [[ -n "${name:-}" ]] && inputs+=("$name")
done < <(
  grep -rEh '^[[:space:]]*variable[[:space:]]+"[^"]+"' "$MODULE_DIR" --include="*.tf" \
  | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*//'
)

# outputs (ignora comentários)
while IFS= read -r line; do
  name=$(sed -n 's/.*output[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$line")
  [[ -n "${name:-}" ]] && outputs+=("$name")
done < <(
  grep -rEh '^[[:space:]]*output[[:space:]]+"[^"]+"' "$MODULE_DIR" --include="*.tf" \
  | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*//'
)

# filtro opcional de outputs
if [[ -n "$OUTPUT_PREFIX_FILTER" ]]; then
  mapfile -t outputs < <(printf "%s\n" "${outputs[@]:-}" | grep -E "$OUTPUT_PREFIX_FILTER" || true)
fi

dedup_sort(){ (( $# )) && printf "%s\n" "$@" | LC_ALL=C sort -u || true; }
mapfile -t inputs  < <(dedup_sort "${inputs[@]:-}")
mapfile -t outputs < <(dedup_sort "${outputs[@]:-}")

# ========== NORMALIZAÇÃO ==========
# Ordem importa para não “sumir” com sufixos antes de removê-los.
normalize(){
  local s="$1"
  s="${s,,}"                                   # lower
  # remove prefixos antes de trocar underscore por hífen
  s="$(sed -E 's/(^|-)terraform-?//; s/(^|-)azurerm-?//; s/(^|-)'"$COSTCENTER"'-?//g' <<<"$s")"
  # remove sufixos *específicos* que aparecem no fim do identificador
  s="$(sed -E 's/(_|-)object_id$//; s/(_|-)name$//; s/(_|-)id$//' <<<"$s")"
  # unifica separadores depois
  s="$(sed -E 's/[ _]+/-/g' <<<"$s")"
  # limpa redundâncias
  s="$(sed -E 's/-+/-/g; s/^-|-$//g' <<<"$s")"
  echo "$s"
}

var_core(){
  local v="$1"
  v="$(sed -E 's/^azurerm_//' <<<"$v")"  # tira o prefixo de provider nas vars
  normalize "$v"
}

ends_with(){ # 0 = hay termina com needle (tokens '-')
  local hay="$1" needle="$2"
  [[ -z "$needle" || -z "$hay" ]] && return 1
  local hparts nparts
  IFS='-' read -r -a hparts <<< "$hay"
  IFS='-' read -r -a nparts <<< "$needle"
  local hlen=${#hparts[@]} nlen=${#nparts[@]}
  (( nlen<=hlen )) || return 1
  local start=$(( hlen - nlen ))
  local tail="${hparts[*]:start:nlen}"
  [[ "${tail// /-}" == "$needle" ]]
}

# ========== DEPENDÊNCIAS ==========
response="$(cat "$CATALOG_FILE")"
mapfile -t resource_names < <(jq -r '.[].metadata.name' <<<"$response" | LC_ALL=C sort -u)

declare -a depends_on=()
declare -A seen_dep=()

for var in "${inputs[@]:-}"; do
  core="$(var_core "$var")"
  [[ -z "$core" ]] && continue

  for resource in "${resource_names[@]:-}"; do
    [[ "$resource" == "$REPO_NAME" ]] && continue
    res_norm="$(normalize "$resource")"  # ex.: terraform-azurerm-tdr-key-vault-access-policy -> tdr-key-vault-access-policy

    if ends_with "$res_norm" "$core"; then
      if [[ -z "${seen_dep[$resource]:-}" ]]; then
        depends_on+=("$resource")
        seen_dep[$resource]=1
        (( DEBUG_MATCH )) && echo "[MATCH] var='${var}' core='${core}'  <=  resource='${resource}' norm='${res_norm}'"
      fi
    else
      (( DEBUG_MATCH )) && echo "[MISS ] var='${var}' core='${core}'  !<= resource='${resource}' norm='${res_norm}'"
    fi
  done
done

mapfile -t depends_on < <(dedup_sort "${depends_on[@]:-}")

# ========== YAML (listas) ==========
inputs_yaml=""
for input in "${inputs[@]:-}";  do inputs_yaml+="      - ${input}"$'\n';  done

outputs_yaml=""
for output in "${outputs[@]:-}"; do outputs_yaml+="      - ${output}"$'\n'; done
[[ -z "$outputs_yaml" ]] && outputs_yaml="      []"$'\n'

depends_on_yaml=""
for dep in "${depends_on[@]:-}"; do depends_on_yaml+="      - resource: ${dep}"$'\n'; done

# ========== TEMPLATE ==========
tmpfile="$(mktemp)"
sed -e "s|\${MODULE_NAME}|${MODULE_NAME}|g" \
    -e "s|\${REPO_NAME}|${REPO_NAME}|g" \
    -e "s|\${MODULE_DESCRIPTION}|Módulo no-code para criação de \"${REPO_NAME}\"|g" \
    "$TEMPLATE_FILE" > "$tmpfile"

outpath="biblioteca/$COSTCENTER/$OUTPUT_FILE"

awk -v inputs="$inputs_yaml" -v outputs="$outputs_yaml" -v depends="$depends_on_yaml" '
{
  if ($0 ~ /\${INPUTS_PLACEHOLDER}/)       { printf "%s", inputs }
  else if ($0 ~ /\${OUTPUTS_PLACEHOLDER}/) { printf "%s", outputs }
  else if ($0 ~ /\${DEPENDS_ON_PLACEHOLDER}/){ printf "%s", depends }
  else { print $0 }
}' "$tmpfile" > "$outpath"

rm -f "$tmpfile"

# remove 'dependsOn:' se não houver conteúdo
if [[ -z "$depends_on_yaml" ]]; then
  sed -i -E '/^[[:space:]]*dependsOn:[[:space:]]*$/d' "$outpath"
  awk 'NF{p=1} p' "$outpath" > "${outpath}.tmp" && mv "${outpath}.tmp" "$outpath"
fi

# ========== DEBUG ==========
echo "Inputs   (${#inputs[@]}):  ${inputs[*]:-}"
echo "Outputs  (${#outputs[@]}): ${outputs[*]:-}"
echo "Depends  (${#depends_on[@]}): ${depends_on[*]:-}"

echo -e "\nYAML Gerado em $outpath:"
cat "$outpath"
