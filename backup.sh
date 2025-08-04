#!/bin/bash

REPO_NAME="terraform-azurerm-rvs-resource-group"
COSTCENTER="rvs"
MODULE_NAME="resource-group"
OUTPUT_FILE="${REPO_NAME}.yml"

mkdir -p biblioteca/$COSTCENTER

# =========================
# COLETAR INPUTS E OUTPUTS
# =========================

inputs=()
outputs=()

while IFS= read -r line; do
    var_name=$(echo "$line" | sed -n 's/variable[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ ! -z "$var_name" ]]; then
        inputs+=("$var_name")
    fi
done < <(grep -rEh '^variable[[:space:]]+"[^"]+"' . --include="*.tf")

while IFS= read -r line; do
    output_name=$(echo "$line" | sed -n 's/output[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ ! -z "$output_name" ]]; then
        outputs+=("$output_name")
    fi
done < <(grep -rEh '^output[[:space:]]+"[^"]+"' . --include="*.tf")

# =========================
# MOCK API - DEPENDS_ON
# =========================

# Simula chamada API pegando JSON fake
response=$(cat fake_catalog_response.json)

# Extrair nomes dos recursos do catálogo
resource_names=($(echo "$response" | jq -r '.[].metadata.name'))

# Função de normalização para fuzzy match
normalize() {
    local costcenter=$1
    local name=$2

    echo "$name" | \
    sed 's/terraform//g' | \
    sed 's/azurerm//g' | \
    sed "s/$costcenter//g" | \
    sed 's/_name$//g' | \
    sed 's/_id$//g' | \
    tr '[:upper:]' '[:lower:]' | \
    tr '_-' ' ' | \
    xargs
}

depends_on=()

extract_core() {
    echo "$1" | sed 's/^azurerm_//' | sed 's/_name$//' | sed 's/_id$//' | sed 's/_object_id$//' | tr '_' '-' | xargs
}

for var in "${inputs[@]}"; do
    var_core=$(extract_core "$var")

    for resource in "${resource_names[@]}"; do
        resource_no_prefix=$(echo "$resource" | sed 's/terraform-//' | sed 's/azurerm-//' | sed "s/$COSTCENTER-//" | xargs)

        # Ignora se for o próprio repo
        if [[ "$resource" == "$REPO_NAME" ]]; then
            continue
        fi

        # Verifica se o var_core é um prefixo do resource (match mais exato)
        if [[ "$resource_no_prefix" == $var_core* ]]; then
            if [[ ! " ${depends_on[@]} " =~ " $resource " ]]; then
                depends_on+=("$resource")
            fi
        fi
    done
done

# =========================
# FORMATAR YAML
# =========================

inputs_yaml=""
for input in "${inputs[@]}"; do
    inputs_yaml+="      - $input"$'\n'
done

outputs_yaml=""
for output in "${outputs[@]}"; do
    outputs_yaml+="      - $output"$'\n'
done

depends_on_yaml=""
for dep in "${depends_on[@]}"; do
    depends_on_yaml+="      - resource: $dep"$'\n'
done

# =========================
# MONTAR TEMPLATE resource.yml
# =========================

cat resource.yml | sed -e "s|\${MODULE_NAME}|$REPO_NAME|g" \
                       -e "s|\${MODULE_DESCRIPTION}|Módulo no-code para criação de \"$REPO_NAME\"|g" \
                       > temp_resource.yml

awk -v inputs="$inputs_yaml" -v outputs="$outputs_yaml" -v depends="$depends_on_yaml" '
{
    if ($0 ~ /\${INPUTS_PLACEHOLDER}/) {
        print inputs
    } else if ($0 ~ /\${OUTPUTS_PLACEHOLDER}/) {
        print outputs
    } else if ($0 ~ /\${DEPENDS_ON_PLACEHOLDER}/) {
        print depends
    } else {
        print $0
    }
}' temp_resource.yml > "biblioteca/$COSTCENTER/$OUTPUT_FILE"

rm temp_resource.yml

# =========================
# DEBUG OUTPUTS
# =========================

echo "Inputs: ${inputs[*]}"
echo "Outputs: ${outputs[*]}"
echo "DependsOn: ${depends_on[*]}"

echo -e "\nYAML Gerado em biblioteca/$COSTCENTER/$OUTPUT_FILE:"
cat "biblioteca/$COSTCENTER/$OUTPUT_FILE"
