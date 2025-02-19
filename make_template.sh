#!/bin/bash
# Create a new script with a template matching this script's template.

base="$(dirname "$(realpath "$0")")" # where this script is
. "$base"/config/utils.sh
. "$base"/config/config.sh
set -eo pipefail
set +u

# Parse arguments
parse_args "new_file [--sbatch]" "$@"
if ! $sbatch; then
  read -r -p "$(bd "Enter a usage string") [default: \"\"]: " usage_string
  : ${usage_string:=""}
fi

echo "$(bd "Enter a description") [two blank lines to end]: "  >&2
description="$(awk -v 'RS=\n\n' '1;{exit}')"

if ! $sbatch; then
  # Split the usage string and prompt the developer to explain each variable
  if [[ "$usage_string" != "" ]]; then
    explanations="Arguments:"
    read -r -a args <<< "${usage_string}"
    for arg in "${args[@]}"; do
      read -r -p "$(bd "Describe $arg"): " arg_explanation
      explanations="$explanations\n$(bullet "$arg: $arg_explanation")"
    done
  fi

  arg_parsing_block="# ===================
`                   `# Parse the arguments
`                   `# ===================
`                   `
`                   `parse_args \"$usage_string\" \"\$@\"
"

fi

# Describe the exit codes:
exit_codes="Exit codes:"
i=0
while (( i >= 0 )); do
  read -r -p "$(bd "Meaning of exit code $i") [leave empty to stop]: " exit_code_meaning
  if [[ -n "$exit_code_meaning" ]]; then
    exit_codes="$exit_codes\n$(bullet "$i: $exit_code_meaning")"
    i=$(( i + 1 ))
  else
    i=-1 # break
  fi
done

# Default script path command (good outside sbatch)
script_path_command='realpath -m "$0"'
sbatch_block=""

# Slurm options
set +u # allow unset
if $sbatch; then
  script_path_command="scontrol show job \"\$SLURM_JOB_ID\" | awk -F= '/Command=/{print \$2}'"
  
  while [[ -z "$slurm_job_name" ]]; do
    read -r -p "$(bd "Job name") [REQUIRED]: " slurm_job_name
  done
  sbatch_block="#
`              `#SBATCH -J $slurm_job_name"
  read -r -p "$(bd "Output file format") (use %A_%a in the filename for job arrays, %j otherwise): " output_file_format
  if [[ -z "$output_file_format" ]]; then
    warn "Not setting output file format."
  else
    sbatch_block="$sbatch_block
`                `#SBATCH --output=$output_file_format"
  fi
fi

# Compute the relative path to the project base
# (defined as the folder containing this file.)
# https://superuser.com/questions/140590/how-to-calculate-a-relative-path-from-two-absolute-paths-in-linux-shell
base_rel_path=$(python3 -c "import os.path; print(os.path.relpath('$base', '$(dirname $new_file)'))")

touch "$new_file"
set +u
cat > "$new_file" <<-EOT
#!/bin/bash
$(comment "$description")
# 
$(comment "$explanations")
$(comment "$exit_codes")
$sbatch_block

# Get the source base folder
SCRIPT_PATH=\$($script_path_command)

base=\$(dirname "\$SCRIPT_PATH")/$base_rel_path # Project base
source "\$base"/config/utils.sh
source "\$base"/config/config.sh
set -euo pipefail
$( if $sbatch; then echo "IS_SBATCH_SCRIPT=true"; fi)

$arg_parsing_block
# ====
# MAIN
# ====
EOT

chmod +x "$new_file"


