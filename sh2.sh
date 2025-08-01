#!/bin/bash

# Recebe o nome do módulo como argumento
MODULE_NAME="$1"

if [[ -z "$MODULE_NAME" ]]; then
  echo "Uso: $0 <MODULE_NAME>"
  exit 1
fi

TERRAFORM_DIR="."
TEMPLATE_FILE="resource.yml"
OUTPUT_FILE="${MODULE_NAME}.yml"

# Coletar inputs/outputs
inputs=()
outputs=()

while IFS= read -r line; do
    var_name=$(echo "$line" | sed -n 's/variable[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ ! -z "$var_name" ]]; then
        inputs+=("$var_name")
    fi
done < <(grep -rEh '^variable[[:space:]]+"[^"]+"' "$TERRAFORM_DIR" --include="*.tf")

while IFS= read -r line; do
    output_name=$(echo "$line" | sed -n 's/output[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ ! -z "$output_name" ]]; then
        outputs+=("$output_name")
    fi
done < <(grep -rEh '^output[[:space:]]+"[^"]+"' "$TERRAFORM_DIR" --include="*.tf")

# Formatar inputs/outputs em YAML
inputs_yaml=""
for input in "${inputs[@]}"; do
    inputs_yaml+="      - $input"$'\n'
done

outputs_yaml=""
for output in "${outputs[@]}"; do
    outputs_yaml+="      - $output"$'\n'
done

# Substituir placeholders e gerar arquivo final
description="Módulo no-code para criação de \"$MODULE_NAME\""

cat "$TEMPLATE_FILE" \
    | sed "s|\${MODULE_NAME}|$MODULE_NAME|g" \
    | sed "s|\${MODULE_DESCRIPTION}|$description|g" \
    | sed "/\${INPUTS_PLACEHOLDER}/ {
        s/\${INPUTS_PLACEHOLDER}//g
        r /dev/stdin
    }" <<< "$inputs_yaml" \
    | sed "/\${OUTPUTS_PLACEHOLDER}/ {
        s/\${OUTPUTS_PLACEHOLDER}//g
        r /dev/stdin
    }" <<< "$outputs_yaml" > "$OUTPUT_FILE"

echo "Arquivo $OUTPUT_FILE gerado com sucesso!"
