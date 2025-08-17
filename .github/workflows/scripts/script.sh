#!/usr/bin/env bash
set -euo pipefail

# ========= Defaults com override por ENV =========
REPO_NAME="${REPO_NAME:-$(basename "${GITHUB_REPOSITORY:-$PWD}" | sed 's#.*/##')}"
COSTCENTER="${COSTCENTER:-$(awk -F'-' '{print $3}' <<<"$REPO_NAME")}"
MODULE_NAME="${MODULE_NAME:-$(cut -d'-' -f4- <<<"$REPO_NAME")}"
OUTPUT_FILE="${OUTPUT_FILE:-${REPO_NAME}.yml}"

TEMPLATE_FILE="${TEMPLATE_FILE:-resource.yml}"
MODULE_DIR="${MODULE_DIR:-.}"

# Este arquivo DEVE ser gravado previamente pelo step de workflow
CATALOG_FILE="${CATALOG_FILE:-catalog_response.json}"

# Debug do matching (1 = ligado)
DEBUG_MATCH="${DEBUG_MATCH:-0}"

# ========= Prechecks =========
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Erro: '$1' não encontrado no PATH"; exit 1; }; }
need jq; need awk; need sed; need grep

[[ -f "$TEMPLATE_FILE" ]] || { echo "Erro: template '$TEMPLATE_FILE' ausente"; exit 1; }
[[ -d "$MODULE_DIR"    ]] || { echo "Erro: MODULE_DIR '$MODULE_DIR' não existe"; exit 1; }
[[ -f "$CATALOG_FILE"  ]] || { echo "Erro: CATALOG_FILE '$CATALOG_FILE' ausente. Grave-o no step anterior do workflow."; exit 1; }

# valida JSON do catálogo
jq -e '.[].metadata.name' "$CATALOG_FILE" >/dev/null || { echo "Erro: '$CATALOG_FILE' não contém .[].metadata.name"; exit 1; }

mkdir -p "biblioteca/$COSTCENTER"

# ========= Coleta (Terraform) =========
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

# ordena e dedup
dedup_sort(){ (( $# )) && printf "%s\n" "$@" | LC_ALL=C sort -u || true; }
mapfile -t inputs  < <(dedup_sort "${inputs[@]:-}")
mapfile -t outputs < <(dedup_sort "${outputs[@]:-}")

# ========= Normalização e matching =========
normalize(){
  local s="$1"
  s="${s,,}"
  s="$(sed -E 's/(^|-)terraform-?//; s/(^|-)azurerm-?//; s/(^|-)'"$COSTCENTER"'-?//g' <<<"$s")"
  s="$(sed -E 's/(_|-)object_id$//; s/(_|-)name$//; s/(_|-)id$//' <<<"$s")"
  s="$(sed -E 's/[ _]+/-/g' <<<"$s")"
  s="$(sed -E 's/-+/-/g; s/^-|-$//g' <<<"$s")"
  echo "$s"
}
var_core(){ local v="$1"; v="$(sed -E 's/^azurerm_//' <<<"$v")"; normalize "$v"; }

ends_with(){
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

response="$(cat "$CATALOG_FILE")"
mapfile -t resource_names < <(jq -r '.[].metadata.name' <<<"$response" | LC_ALL=C sort -u)

declare -a depends_on=()
declare -A seen_dep=()

# === Identidades "self" para evitar autodependência ===
repo_norm="$(normalize "$REPO_NAME")"
self_full="terraform-azurerm-${COSTCENTER}-${MODULE_NAME}"
self_full_norm="$(normalize "$self_full")"

for var in "${inputs[@]:-}"; do
  core="$(var_core "$var")"
  [[ -z "$core" ]] && continue

  for resource in "${resource_names[@]:-}"; do
    res_norm="$(normalize "$resource")"

    # Skip se o recurso for o próprio módulo (em várias formas)
    if [[ "$resource" == "$REPO_NAME" ]] \
       || [[ "$resource" == "$self_full" ]] \
       || [[ "$res_norm" == "$repo_norm" ]] \
       || [[ "$res_norm" == "$self_full_norm" ]]; then
      (( DEBUG_MATCH )) && echo "[SKIP SELF] resource='${resource}' repo='${REPO_NAME}' self='${self_full}' res_norm='${res_norm}' repo_norm='${repo_norm}' self_norm='${self_full_norm}'"
      continue
    fi

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

# ========= YAML =========
inputs_yaml="";  for x in "${inputs[@]:-}";     do inputs_yaml+="      - ${x}"$'\n'; done
outputs_yaml=""; for x in "${outputs[@]:-}";    do outputs_yaml+="      - ${x}"$'\n'; done
[[ -z "$outputs_yaml" ]] && outputs_yaml="      []"$'\n'
depends_on_yaml=""; for d in "${depends_on[@]:-}"; do depends_on_yaml+="      - resource: ${d}"$'\n'; done

tmpfile="$(mktemp)"
sed -e "s|\${MODULE_NAME}|${MODULE_NAME}|g" \
    -e "s|\${REPO_NAME}|${REPO_NAME}|g" \
    -e "s|\${MODULE_DESCRIPTION}|Módulo no-code para criação de \"${REPO_NAME}\"|g" \
    "$TEMPLATE_FILE" > "$tmpfile"

outpath="biblioteca/$COSTCENTER/$OUTPUT_FILE"
awk -v inputs="$inputs_yaml" -v outputs="$outputs_yaml" -v depends="$depends_on_yaml" '
{
  if ($0 ~ /\${INPUTS_PLACEHOLDER}/)        { printf "%s", inputs }
  else if ($0 ~ /\${OUTPUTS_PLACEHOLDER}/)  { printf "%s", outputs }
  else if ($0 ~ /\${DEPENDS_ON_PLACEHOLDER}/){ printf "%s", depends }
  else { print $0 }
}' "$tmpfile" > "$outpath"
rm -f "$tmpfile"

# remove "dependsOn:" se não houver dependências
if [[ -z "$depends_on_yaml" ]]; then
  sed -i -E '/^[[:space:]]*dependsOn:[[:space:]]*$/d' "$outpath"
  awk 'NF{p=1} p' "$outpath" > "${outpath}.tmp" && mv "${outpath}.tmp" "$outpath"
fi

# ========= Exporta para GITHUB_ENV (se existir) =========
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "inputs=$(IFS=' '; echo "${inputs[*]:-}")"          >> "$GITHUB_ENV"
  echo "outputs=$(IFS=' '; echo "${outputs[*]:-}")"        >> "$GITHUB_ENV"
  echo "depends_on=$(IFS=' '; echo "${depends_on[*]:-}")"  >> "$GITHUB_ENV"
  echo "COSTCENTER=$COSTCENTER"    >> "$GITHUB_ENV"
  echo "MODULE_NAME=$MODULE_NAME"  >> "$GITHUB_ENV"
  echo "OUTPUT_FILE=$OUTPUT_FILE"  >> "$GITHUB_ENV"
fi

# ========= Log final =========
echo "Inputs   (${#inputs[@]}):  ${inputs[*]:-}"
echo "Outputs  (${#outputs[@]}): ${outputs[*]:-}"
echo "Depends  (${#depends_on[@]}): ${depends_on[*]:-}"
echo -e "\nYAML Gerado em $outpath:"
cat "$outpath"
