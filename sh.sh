#!/bin/bash

TERRAFORM_DIR="."

inputs=()
outputs=()

# Buscar variáveis
while IFS= read -r line; do
    var_name=$(echo "$line" | sed -n 's/variable[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ ! -z "$var_name" ]]; then
        inputs+=("$var_name")
    fi
done < <(grep -rEh '^variable[[:space:]]+"[^"]+"' "$TERRAFORM_DIR" --include="*.tf")

# Buscar outputs
while IFS= read -r line; do
    output_name=$(echo "$line" | sed -n 's/output[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ ! -z "$output_name" ]]; then
        outputs+=("$output_name")
    fi
done < <(grep -rEh '^output[[:space:]]+"[^"]+"' "$TERRAFORM_DIR" --include="*.tf")

# Imprimir em formato YAML para o Catalog do Backstage
echo "definition:"
echo "  input:"
for input in "${inputs[@]}"; do
    echo "    - $input"
done
echo "  output:"
for output in "${outputs[@]}"; do
    echo "    - $output"
done
