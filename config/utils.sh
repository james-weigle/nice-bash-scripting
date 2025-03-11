#!/usr/bin/false
# General functions and environment variables.

# === ENVIRONMENT VARIABLES ===

# Distinguish interactive from non-interactive usage
if [ -t 1 ] && [ "$(tput colors 2>/dev/null)" -gt 2 ]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

# Set this to true if your script is being run as an SBATCH script
IS_SBATCH_SCRIPT=false

# level of verbosity (set this after sourcing this utility script)
# 0 --- suppress warnings and messages
# 1 --- suppress messages
# 2 --- suppress nothing
# 3 --- also print call stack with errors [default]
VERBOSITY=3

DEFAULT_IFS=$' \t\n'
# Reset IFS to this
function reset_ifs() { IFS="$DEFAULT_IFS" ; }

decorate() {
  # Decorate the given text iff the terminal is interactive.
  #
  #   Arguments:
  #     1. `options`: the arguments you would pass to `tput`,
  #           in one string, separated by spaces.
  #     2. everything else: the text to decorate.

  # We don't want the exit code to get overwritten when we're decorating text
  # inside an error message, so we store it and return it:
  local exit_code=$?

  # process the options as passed as one string
  local options="$1"
  local IFS=' ' # make sure this doesn't get overwritten either
  # read the options into an array
  declare -a split_options=()
  read -ra split_options <<< "$options"

  if $INTERACTIVE; then
    echo "$(tput "${split_options[@]}")${*:2}$(tput sgr0)"
  else
    echo "${*:2}"
  fi

  # return the exit code like nothing happened
  return "$exit_code"
}


# Color the given text with the given code
function color() { decorate "setaf $1" "${*:2}" ; }

# Text styles: bold and underline
function bd() { decorate bold "$*" ; } # bold
function ul() { decorate smul "$*" ; } # underlined

# Color commands
function r() { color 1 "$*" ; } # red
function g() { color 2 "$*" ; } # green
function y() { color 3 "$*" ; } # yellow
function b() { color 4 "$*" ; } # blue
function v() { color 5 "$*" ; } # violet

# Print a multiline string as bash comments
comment() {
  local str="$1"
  echo -e "$str" | fold -s -w 78 | sed "s/^/# /g" 
}

# Print a multiline string as a bullet point in a list
bullet() {
  local str="$1"
  echo -e "$str" | fold -s -w 74 |
    awk 'NR==1 { print " - " $0 } NR>1 { print "   " $0 }' 
}


# === ERROR REPORTING ===

# Print a timestamp
function timestamp() { echo "[$(date +'%Y-%m-%d-@-%H:%M:%S%z')]" ; }


# Report an error.
function err() { reset_ifs;
  local oldenv="$-"
  set +u
  # in a slurm job, use 2 rather than 1
  i=0
  if [[ "$IS_SBATCH_SCRIPT" ]]; then
    i=1
  fi

  call_stack=( "${FUNCNAME[@]}" )
  source_stack=( "${BASH_SOURCE[@]}" )
  lineno_stack=( "${BASH_LINENO[@]}" )
  printf "$(r $(timestamp)) " >&2
  if (( VERBOSITY > 2)); then
    printf "\n" >&2
    for ((j=(${#call_stack});j>0;j--)); do
      if [[ -n ${call_stack[$j]} ]]; then
        line="$(bd ${source_stack[$j]##*/}):$(b ${call_stack[$j]}):$(y ${lineno_stack[$j]})"
        echo "  $(r ⮡) $line" >&2
      fi
    done
  fi
  printf "$(r $(bd "Error:")) $*\n" >&2
  set $oldenv

}


# Print a message.
function msg() { reset_ifs; if (( VERBOSITY > 1 )); then echo "$(color 28 "$(timestamp)") $*" >&2 ; fi ; }


# print a warning
function warn() { reset_ifs; if (( VERBOSITY > 0 )); then echo "$(y "$(timestamp)" "$(bd Warning:)") $*" >&2 ; fi ; }


# print an error that the current function is not implemented
function notimplemented() { err "${FUNCNAME[1]} is not yet implemented!" ; }


# === LOCALLY CHANGING VARIABLES ===

declare -a _using_stack

using() {
  # Temporarily save the given variable to a stack; it can be retrieved with `gnisu`.

  local old_env="$-"
  set +u
  local varname="$1"
  local value="$2"

  if [[ "${!varname}" =~ $'\001' ]]; then
    err "No \\001 allowed in value when assigning variable $varname."
    return 1
  fi

  # Push <var>:<value> onto the stack
  _using_stack[${#_using_stack[*]}]="$varname"$'\001'"${!varname@Q}"
  # Reassign varname
  eval "$varname=$value"
  set "$old_env"
}

showusingstack() {
  # Print the contents of the using stack
  msg "Custom variable stack: ${_using_stack[*]//$'\001'/:}"
}

gnisu() {
  # Pop an item off the variable stack and assign that variable accordingly.

  local size="${#_using_stack[@]}"
  if (( size < 1 )); then return; fi
  local kvpair=${_using_stack[${#_using_stack[@]}-1]}
  unset _using_stack[${#_using_stack[@]}-1]
  varname="${kvpair%$'\001'*}"
  value="${kvpair#*$'\001'}"
  eval "$varname=$value"
}



# === MISCELLANEOUS ===


squeeze() {
  # Fit the string within k>=5 columns.
  local k="$1"
  local s="$2"

  if (( k < 5 )); then
    err "Unsupported length $k"; return 1
  fi

  # Leave it unchanged if the string is shorter
  if (( "${#s}" <= k )); then
    echo "$s"; return
  fi

  # Otherwise, let len := (k-3)/2
  local len=$(( ( "$k" - 3) / 2 )) 
  echo "${s::$len}...${s:$((${#s}-len))}"
  
}

squeezepath() {
  # Fit the path within COLUMNS.
  local path="$1"
  local base="$(basename "$path")"
  local old_env="$-"
  
  set +u
  local COLUMNS="$COLUMNS"
  : ${COLUMNS:=80} # if not defined
  if (( "${#base}" > COLUMNS )); then
    # Truncate both the parent and the basename.
    echo "$(squeeze 7 $(dirname "$path"))"/"$(squeeze $(( COLUMNS - 8 )) "$base")"
    return
  fi 

  # Otherwise, keep full basename and truncate path
  echo "$(squeeze $((COLUMNS-1-${#base})) $(dirname "$path"))"/"$base"
  # Reset environment
  set $old_env

}

length() {
  # Length of a string minus non-printing characters
  local str=$( sed $'s,\x1B\[[0-9;]*[a-zA-Z],,g;s,\017,,g' <<< "$*" )
  echo "${#str}"
}

box() {
  # Surround a string with a box
  local old_env="$-"
  set +u 
  local COLUMNS=$COLUMNS
  : ${COLUMNS:=80}
  contents="$(fold -s -w "$(( COLUMNS - 4 ))" <<< "$*")"
  length=$(awk -F '' 'NF>a{a=NF}END{print a}' <<< "$contents") # length of longest line
  awk -v l=$length 'BEGIN{ printf "┌";for(;i++<l+2;){printf "─"}print "┐"}{printf "│ %*-s │\n", l, $0 }END{  printf "└";for(i=0;i++<l+2;){printf "─"}print "┘" }' <<< "$contents"

  set $old_env
}

showfilecontents() { 
  # Print the given file in a fetching way
  filename="$1"
  if [[ ! -f "$filename" ]]; then
    err "File not found: $filename"
    return 1 
  fi
  : ${COLUMNS:=80} # 80 if not defined
  box "$(squeezepath "$filename")"

  # Prepend a 🮌 to each line in the file
  sed "s/^/🮌 /g" "$filename"
  echo # Skip a line

}


# === PARSING ARGUMENTS === 


docstring() {
  # Print the comment header of the file
  # without the leading #'s.
  local our_file="$1"
  local heading="$(basename "$our_file")"
  using COLUMNS 80
    box "$heading" >&2
  gnisu
  awk '/^[[:space:]]*$/{a=1};NR>1&&a==0{gsub(/^[[:space:]]*#/,"",$0);print $0}' "$our_file" >&2
  echo "" >&2
}

parse_args() {
  # This gargantuan function parses a given string as arguments and makes them
  # available as variables. Note that hyphens get translated into underscores.
  #
  # The first argument is the string and everything else is parsed as the
  # arguments.
  #
  # Supports required positional arguments, optional keyword arguments, and
  # optional flags. (But not required keyword arguments!)
  # 
  # Example usage:
  #   local var_1 var_2
  #   parse_args "var-1 [--var-2=<path>]" "$@"
  #
  # Note that keyword arguments without the equals sign are not supported!

  local env_options="$-"
  set +u # allow unbound
  set -f # do not allow file globbing right now
  
  local _fname 
  if [[ ${FUNCNAME[1]} == "main" ]]; then
    _fname="$0"
  else
    _fname="${FUNCNAME[1]} (function under $0)"
  fi

  if [[ "$_fname" == "main" ]]; then
    _fname=$0
  fi

  local arg_strings=( $1 )
  shift
  local real_args=( "${@}" )
  declare -a args=()
  declare -A options=()

  # For each arg in arg_strings: if it's of the form
  # [--something=something] or [--something]
  # add 'something' to the dictionary
  set -- "${arg_strings[@]}"
  local argc=0

  # Make these three local variables
  local arg
  local key
  local value

  # Iterate over arguments.
  while (( $# > 0 )); do
    arg="$1"

    # Replace [X] with X
    arg="${arg#[}"; arg="${arg%]}"

    # Check if we're looking at a keyword option
    if [[ "$arg" =~ ^--[a-zA-Z_-][a-zA-Z_-]*=[^=][^=]*$ ]]; then

      arg="${arg#--}" # remove prefix
      key="${arg%%=*}" # remove suffix
      key="${key//-/_}" # Replace all - with _
      # We discard the suffix

      # Don't change it if key was defined as an environment variable
      if [[ -z "${!key}" ]]; then
        options["$key"]="EMPTY"
      else
        options["$key"]="${!key}"
      fi

    # Or a flag
    elif [[ "$arg" =~ ^--[^=[:space:]][^=[:space:]]*$ ]]; then
      # Set it to false
      arg="${arg#--}"
      arg="${arg//-/_}"
      options["$arg"]="false"

    # Otherwise, assume it's a positional argument
    else
      args[(( argc++ ))]="$arg"
    fi

    # Remove this one from the arg list
    shift

  done

  # Now move on to processing args
  set -- "${real_args[@]}"
  rargc=0
  while (( $# > 0 )); do
    arg="$1"

    # If arg is help, docstring
    if [[ "$arg" == "-h" ]] || [[ "$arg" == "--help" ]]; then
      docstring "$0"
      exit 1
    fi

    case "$arg" in
      # Keyword argument
      --*=*)
        arg="${arg#--}"
        key="${arg%%=*}"
        value="${arg##*=}"
        # Replace - with _
        key="${key//-/_}"
        if [[ -z "${options["$key"]}" ]]; then
          err "Unrecognized option: $key"
          return 1
        fi

        options["$key"]="$value"

        ;;
      # Flag
      --*) arg="${arg#--}"
           arg="${arg//-/_}"
           if [[ -z "${options["$arg"]}" ]]; then
             err "Unrecognized flag: $arg"
             return 1
           fi
           options["$arg"]=true
           ;;

      # Positional argument 
      *) if (( "$rargc" < "$argc" )); then
          name=${args[$rargc]};
          eval "$name=${arg@Q}"
          rargc=$(( $rargc + 1 ))
         else
          echo "$(r Usage): $_fname ${arg_strings[*]}" >&2
          echo "--> Error token: $arg" >&2
          return 1
         fi ;;
    esac
    shift
  done

  # If we still have required arguments, complain
  for arg in "${args[@]}"; do
    if [[ -z "${!arg}" ]]; then
      echo "$(r Usage): $_fname ${arg_strings[*]}" >&2
      echo "--> Unset variable: $arg"
      return 1
    fi
  done

  # Export options to environment variables
  for option_key in "${!options[@]}"; do
    value="${options["$option_key"]}"
    eval "$option_key=${value@Q}"
  done

  # Set environment options back
  set "$env_options"
}


