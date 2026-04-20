#!/bin/bash

#===============================================================================
#
#  VERCEL PROJECT CLEANUP SCRIPT
#
#  A robust script to clean up Vercel projects with filtering options.
#
#  FEATURES:
#    - Delete all projects except specified ones
#    - Filter by visibility (public/private GitHub repos)
#    - Dry-run mode for safe preview
#    - Debug mode for troubleshooting
#    - Automatic token detection
#    - API-based with CLI fallback
#
#  USAGE:
#    ./cleanup-vercel.sh [OPTIONS]
#
#  OPTIONS:
#    --dry-run     Preview without deleting
#    --public      Only target public GitHub repos
#    --private     Only target private GitHub repos
#    --debug       Enable verbose debug output
#    --use-cli     Force CLI mode (skip API)
#    --help        Show help message
#
#  EXAMPLES:
#    ./cleanup-vercel.sh --dry-run              # Preview all
#    ./cleanup-vercel.sh --public --dry-run     # Preview public only
#    ./cleanup-vercel.sh --private              # Delete private repos
#    ./cleanup-vercel.sh --debug --dry-run      # Debug mode
#
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------

readonly DEFAULT_KEEP="financialretardedtimes"
readonly VERSION="2.0.0"

#-------------------------------------------------------------------------------
# GLOBAL STATE
#-------------------------------------------------------------------------------

DRY_RUN=false
DEBUG=false
FILTER_MODE="all"  # all, public, private
USE_CLI=false
VERCEL_TOKEN=""
VERCEL_SCOPE=""

# Arrays for project data
declare -a PROJECT_NAMES=()
declare -a PROJECT_VISIBILITY=()

#-------------------------------------------------------------------------------
# COLORS
#-------------------------------------------------------------------------------

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'

#-------------------------------------------------------------------------------
# LOGGING FUNCTIONS
#-------------------------------------------------------------------------------

log_info()    { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
log_error()   { echo -e "${RED}✗${NC} $*" >&2; }

log_debug() {
    if [[ "$DEBUG" == true ]]; then
        echo -e "${GRAY}[DEBUG] $*${NC}" >&2
    fi
}

log_step() {
    echo ""
    echo -e "${BLUE}━━━ $* ━━━${NC}"
}

#-------------------------------------------------------------------------------
# ERROR HANDLING
#-------------------------------------------------------------------------------

die() {
    log_error "$1"
    exit "${2:-1}"
}

# Trap for cleanup on exit
cleanup() {
    local exit_code=$?
    log_debug "Script exiting with code: $exit_code"
    exit $exit_code
}
trap cleanup EXIT

#-------------------------------------------------------------------------------
# HELP & VERSION
#-------------------------------------------------------------------------------

show_help() {
    cat << 'EOF'
Vercel Project Cleanup Script

USAGE:
    ./cleanup-vercel.sh [OPTIONS]

OPTIONS:
    --dry-run     Preview what would be deleted (no actual deletion)
    --public      Only show/delete projects linked to PUBLIC GitHub repos
    --private     Only show/delete projects linked to PRIVATE GitHub repos
    --debug       Enable verbose debug output for troubleshooting
    --use-cli     Force using Vercel CLI instead of API
    --help        Show this help message
    --version     Show version

EXAMPLES:
    ./cleanup-vercel.sh                      # Delete all (except default keep)
    ./cleanup-vercel.sh --dry-run            # Preview mode
    ./cleanup-vercel.sh --public --dry-run   # Preview public repos only
    ./cleanup-vercel.sh --private            # Delete private repos only
    ./cleanup-vercel.sh --debug --dry-run    # Debug with preview

DEFAULT KEPT PROJECT:
    financialretardedtimes (can be changed in script config)
EOF
    exit 0
}

show_version() {
    echo "cleanup-vercel.sh version $VERSION"
    exit 0
}

#-------------------------------------------------------------------------------
# ARGUMENT PARSING
#-------------------------------------------------------------------------------

parse_args() {
    log_debug "Parsing arguments: $*"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                log_debug "Dry run mode enabled"
                shift
                ;;
            --public)
                FILTER_MODE="public"
                log_debug "Filter mode: public"
                shift
                ;;
            --private)
                FILTER_MODE="private"
                log_debug "Filter mode: private"
                shift
                ;;
            --debug)
                DEBUG=true
                echo -e "${GRAY}[DEBUG] Debug mode enabled${NC}"
                shift
                ;;
            --use-cli)
                USE_CLI=true
                log_debug "Forcing CLI mode"
                shift
                ;;
            --help|-h)
                show_help
                ;;
            --version|-v)
                show_version
                ;;
            *)
                die "Unknown option: $1. Use --help for usage."
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# VERCEL CLI CHECKS
#-------------------------------------------------------------------------------

check_vercel_cli() {
    log_debug "Checking Vercel CLI installation..."
    
    if ! command -v vercel &> /dev/null; then
        die "Vercel CLI not found. Install with: npm install -g vercel"
    fi
    
    log_debug "Vercel CLI found: $(which vercel)"
}

check_vercel_login() {
    log_debug "Checking Vercel login status..."
    
    local whoami_output
    if ! whoami_output=$(vercel whoami 2>&1); then
        log_warn "Not logged in to Vercel"
        log_info "Starting Vercel login..."
        
        if ! vercel login; then
            die "Vercel login failed"
        fi
        
        whoami_output=$(vercel whoami 2>&1)
    fi
    
    local username
    username=$(echo "$whoami_output" | tail -1)
    log_success "Logged in as: $username"
    log_debug "Vercel user: $username"
}

#-------------------------------------------------------------------------------
# TOKEN MANAGEMENT
#-------------------------------------------------------------------------------

find_auth_token() {
    log_debug "Searching for Vercel auth token..."
    
    # Possible locations for Vercel auth config
    local auth_paths=(
        "$HOME/Library/Application Support/com.vercel.cli/auth.json"
        "$HOME/.config/vercel/auth.json"
        "$HOME/.vercel/auth.json"
        "$HOME/.local/share/com.vercel.cli/auth.json"
    )
    
    for auth_path in "${auth_paths[@]}"; do
        log_debug "Checking: $auth_path"
        
        if [[ -f "$auth_path" ]]; then
            log_debug "Found auth file: $auth_path"
            
            # Extract token using Python for reliable JSON parsing
            local token
            token=$(python3 -c "
import json
import sys
try:
    with open('$auth_path', 'r') as f:
        data = json.load(f)
        print(data.get('token', ''))
except Exception as e:
    print('', file=sys.stderr)
" 2>/dev/null)
            
            if [[ -n "$token" ]]; then
                VERCEL_TOKEN="$token"
                log_debug "Token found (length: ${#token})"
                return 0
            fi
        fi
    done
    
    log_debug "No auth token found in any location"
    return 1
}

#-------------------------------------------------------------------------------
# SCOPE/TEAM DETECTION
#-------------------------------------------------------------------------------

detect_scope() {
    log_debug "Detecting Vercel scope/team..."
    
    local teams_output
    teams_output=$(vercel teams ls 2>&1)
    
    log_debug "Teams output: $teams_output"
    
    # Parse team ID from output (skip headers and empty lines)
    VERCEL_SCOPE=$(echo "$teams_output" | \
        grep -v -E '^(Vercel CLI|Fetching|id\s+|$|\s*$)' | \
        head -1 | \
        awk '{print $1}')
    
    if [[ -z "$VERCEL_SCOPE" ]]; then
        log_warn "Could not detect team/scope, using personal account"
        return 1
    fi
    
    log_success "Using scope: $VERCEL_SCOPE"
    log_debug "Detected scope: $VERCEL_SCOPE"
    return 0
}

#-------------------------------------------------------------------------------
# PROJECT FETCHING - API MODE
#-------------------------------------------------------------------------------

fetch_projects_api() {
    log_debug "Fetching projects via API..."
    
    if [[ -z "$VERCEL_TOKEN" ]]; then
        log_debug "No token available for API"
        return 1
    fi
    
    if [[ -z "$VERCEL_SCOPE" ]]; then
        log_debug "No scope available for API"
        return 1
    fi
    
    local page_count=0
    local next_cursor=""
    local api_base="https://api.vercel.com/v9/projects"
    
    # Clear arrays
    PROJECT_NAMES=()
    PROJECT_VISIBILITY=()
    
    while true; do
        ((page_count++))
        log_debug "Fetching API page $page_count..."
        
        # Build URL
        local api_url="${api_base}?limit=100&teamId=${VERCEL_SCOPE}"
        if [[ -n "$next_cursor" ]]; then
            api_url="${api_url}&until=${next_cursor}"
        fi
        
        log_debug "API URL: $api_url"
        
        # Fetch from API
        local response
        local http_code
        
        response=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Bearer $VERCEL_TOKEN" \
            "$api_url" 2>&1)
        
        http_code=$(echo "$response" | tail -1)
        response=$(echo "$response" | sed '$d')
        
        log_debug "HTTP status: $http_code"
        
        if [[ "$http_code" != "200" ]]; then
            log_debug "API request failed with status $http_code"
            log_debug "Response: $response"
            return 1
        fi
        
        # Parse JSON response with Python
        local parsed
        parsed=$(echo "$response" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    
    if 'error' in data:
        print(f\"ERROR|{data['error'].get('message', 'Unknown error')}\")
        sys.exit(1)
    
    projects = data.get('projects', [])
    
    for p in projects:
        name = p.get('name', '')
        visibility = 'unknown'
        
        # Get visibility from latest deployment metadata
        latest_deps = p.get('latestDeployments', [])
        if latest_deps:
            meta = latest_deps[0].get('meta', {})
            visibility = meta.get('githubRepoVisibility', 'unknown')
        
        print(f'{name}|{visibility}')
    
    # Output next cursor if available
    pagination = data.get('pagination', {})
    next_val = pagination.get('next', '')
    if next_val:
        print(f'__NEXT__|{next_val}')

except json.JSONDecodeError as e:
    print(f'ERROR|JSON parse error: {e}')
    sys.exit(1)
except Exception as e:
    print(f'ERROR|{e}')
    sys.exit(1)
" 2>&1)
        
        if [[ $? -ne 0 ]]; then
            log_debug "Python parsing failed: $parsed"
            return 1
        fi
        
        # Check for errors in parsed output
        if echo "$parsed" | grep -q "^ERROR|"; then
            local error_msg
            error_msg=$(echo "$parsed" | grep "^ERROR|" | cut -d'|' -f2)
            log_debug "API error: $error_msg"
            return 1
        fi
        
        # Process parsed output
        next_cursor=""
        while IFS='|' read -r name visibility; do
            if [[ "$name" == "__NEXT__" ]]; then
                next_cursor="$visibility"
                log_debug "Next cursor: $next_cursor"
            elif [[ -n "$name" ]]; then
                PROJECT_NAMES+=("$name")
                PROJECT_VISIBILITY+=("$visibility")
                log_debug "Project: $name ($visibility)"
            fi
        done <<< "$parsed"
        
        # Check if more pages
        if [[ -z "$next_cursor" ]]; then
            log_debug "No more pages"
            break
        fi
        
        log_info "Page $page_count fetched, loading more..."
    done
    
    log_debug "API fetch complete. Total projects: ${#PROJECT_NAMES[@]}"
    return 0
}

#-------------------------------------------------------------------------------
# PROJECT FETCHING - CLI MODE
#-------------------------------------------------------------------------------

fetch_projects_cli() {
    log_debug "Fetching projects via CLI..."
    
    local page_count=0
    local next_token=""
    local scope_arg=""
    
    if [[ -n "$VERCEL_SCOPE" ]]; then
        scope_arg="--scope $VERCEL_SCOPE"
    fi
    
    # Clear arrays
    PROJECT_NAMES=()
    PROJECT_VISIBILITY=()
    
    while true; do
        ((page_count++))
        log_debug "Fetching CLI page $page_count..."
        
        # Build command
        local cmd="vercel project ls $scope_arg"
        if [[ -n "$next_token" ]]; then
            cmd="$cmd --next $next_token"
        fi
        
        log_debug "Command: $cmd"
        
        # Execute
        local output
        if ! output=$(eval "$cmd" 2>&1); then
            log_debug "CLI command failed: $output"
            return 1
        fi
        
        log_debug "CLI output received (${#output} chars)"
        
        # Parse project names from output
        # Format: "  project-name   https://... or --"
        local names
        names=$(echo "$output" | grep -E '^\s+\S+\s+(https?://|--)' | awk '{print $1}' || true)
        
        while IFS= read -r name; do
            if [[ -n "$name" ]]; then
                PROJECT_NAMES+=("$name")
                PROJECT_VISIBILITY+=("unknown")  # CLI doesn't provide visibility
                log_debug "Project: $name (unknown)"
            fi
        done <<< "$names"
        
        # Check for next page token
        next_token=$(echo "$output" | grep -oE 'vercel project ls --next [0-9]+' | awk '{print $NF}' || true)
        
        if [[ -z "$next_token" ]]; then
            log_debug "No more pages"
            break
        fi
        
        log_info "Page $page_count fetched, loading more..."
    done
    
    log_debug "CLI fetch complete. Total projects: ${#PROJECT_NAMES[@]}"
    return 0
}

#-------------------------------------------------------------------------------
# PROJECT FETCHING - MAIN
#-------------------------------------------------------------------------------

fetch_projects() {
    log_step "Fetching Projects"
    
    local method_used=""
    
    if [[ "$USE_CLI" == true ]]; then
        log_info "Using CLI mode (forced)"
        if fetch_projects_cli; then
            method_used="CLI"
        else
            die "CLI fetch failed"
        fi
    else
        log_info "Attempting API mode..."
        if fetch_projects_api; then
            method_used="API"
        else
            log_warn "API fetch failed, falling back to CLI..."
            if fetch_projects_cli; then
                method_used="CLI (fallback)"
            else
                die "Both API and CLI fetch failed"
            fi
        fi
    fi
    
    log_success "Fetched ${#PROJECT_NAMES[@]} projects via $method_used"
    
    # Warn if using CLI with visibility filter
    if [[ "$method_used" == "CLI"* && "$FILTER_MODE" != "all" ]]; then
        log_warn "Visibility filter requires API. CLI doesn't provide visibility info."
        log_warn "All projects will be shown as 'unknown' visibility."
    fi
}

#-------------------------------------------------------------------------------
# PROJECT FILTERING
#-------------------------------------------------------------------------------

get_visibility() {
    local name="$1"
    
    for i in "${!PROJECT_NAMES[@]}"; do
        if [[ "${PROJECT_NAMES[$i]}" == "$name" ]]; then
            echo "${PROJECT_VISIBILITY[$i]}"
            return
        fi
    done
    
    echo "unknown"
}

filter_projects() {
    log_debug "Filtering projects by: $FILTER_MODE"
    
    local filtered_names=()
    
    for i in "${!PROJECT_NAMES[@]}"; do
        local name="${PROJECT_NAMES[$i]}"
        local visibility="${PROJECT_VISIBILITY[$i]}"
        
        case "$FILTER_MODE" in
            all)
                filtered_names+=("$name")
                ;;
            public)
                if [[ "$visibility" == "public" ]]; then
                    filtered_names+=("$name")
                fi
                ;;
            private)
                if [[ "$visibility" == "private" ]]; then
                    filtered_names+=("$name")
                fi
                ;;
        esac
    done
    
    # Sort and dedupe
    local sorted_names
    sorted_names=$(printf '%s\n' "${filtered_names[@]}" | sort -u)
    
    echo "$sorted_names"
}

#-------------------------------------------------------------------------------
# DISPLAY FUNCTIONS
#-------------------------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Vercel Project Cleanup Script v$VERSION    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}🔍 DRY RUN MODE - No projects will be deleted${NC}"
    fi
    
    if [[ "$FILTER_MODE" == "public" ]]; then
        echo -e "${YELLOW}📂 Filter: PUBLIC GitHub repos only${NC}"
    elif [[ "$FILTER_MODE" == "private" ]]; then
        echo -e "${YELLOW}🔒 Filter: PRIVATE GitHub repos only${NC}"
    fi
    
    echo ""
}

display_projects() {
    local projects="$1"
    local total_count="${#PROJECT_NAMES[@]}"
    local filtered_count
    filtered_count=$(echo "$projects" | grep -c '^' || echo 0)
    
    log_step "Projects ($filtered_count of $total_count)"
    
    if [[ -z "$projects" ]]; then
        log_warn "No projects match the filter criteria"
        return 1
    fi
    
    echo ""
    echo "  Legend: 🌐 public  🔒 private  ❓ unknown"
    echo "  ─────────────────────────────────────────"
    
    local i=1
    while IFS= read -r name; do
        if [[ -z "$name" ]]; then continue; fi
        
        local vis
        vis=$(get_visibility "$name")
        
        local icon
        case "$vis" in
            public)  icon="🌐" ;;
            private) icon="🔒" ;;
            *)       icon="❓" ;;
        esac
        
        if [[ "$name" == "$DEFAULT_KEEP" ]]; then
            printf "  %3d. %s ${GREEN}%s${NC} ${GREEN}← KEEP${NC}\n" "$i" "$icon" "$name"
        else
            printf "  %3d. %s %s\n" "$i" "$icon" "$name"
        fi
        
        ((i++))
    done <<< "$projects"
    
    echo "  ─────────────────────────────────────────"
    echo ""
    
    return 0
}

#-------------------------------------------------------------------------------
# USER INPUT
#-------------------------------------------------------------------------------

prompt_keep_projects() {
    echo -e "${YELLOW}Which projects do you want to KEEP?${NC}"
    echo ""
    echo "  Enter names separated by commas, or press Enter for default."
    echo -e "  Default: ${GREEN}$DEFAULT_KEEP${NC}"
    echo ""
    
    local input
    read -r -p "  Projects to keep: " input
    
    # Use default if empty
    if [[ -z "$input" ]]; then
        input="$DEFAULT_KEEP"
    fi
    
    # Parse comma-separated list
    local keep_list=()
    IFS=',' read -ra items <<< "$input"
    
    for item in "${items[@]}"; do
        # Trim whitespace
        item=$(echo "$item" | xargs)
        if [[ -n "$item" ]]; then
            keep_list+=("$item")
        fi
    done
    
    echo ""
    echo -e "${GREEN}Keeping ${#keep_list[@]} project(s):${NC}"
    for p in "${keep_list[@]}"; do
        echo "  ✓ $p"
    done
    echo ""
    
    printf '%s\n' "${keep_list[@]}"
}

#-------------------------------------------------------------------------------
# DELETION LOGIC
#-------------------------------------------------------------------------------

build_delete_list() {
    local all_projects="$1"
    shift
    local -a keep_projects=("$@")
    
    local delete_list=()
    
    while IFS= read -r project; do
        if [[ -z "$project" ]]; then continue; fi
        
        local should_keep=false
        for keep in "${keep_projects[@]}"; do
            if [[ "$project" == "$keep" ]]; then
                should_keep=true
                break
            fi
        done
        
        if [[ "$should_keep" == false ]]; then
            delete_list+=("$project")
        fi
    done <<< "$all_projects"
    
    printf '%s\n' "${delete_list[@]}"
}

confirm_deletion() {
    local count="$1"
    
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  WARNING: This will PERMANENTLY delete        ║${NC}"
    echo -e "${RED}║      $count project(s) and ALL their deployments!    ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -r -p "  Type 'yes' to confirm: " confirm
    
    [[ "$confirm" == "yes" ]]
}

delete_projects() {
    local -a projects=("$@")
    local total=${#projects[@]}
    local deleted=0
    local failed=0
    
    log_step "Deleting Projects"
    
    local scope_arg=""
    if [[ -n "$VERCEL_SCOPE" ]]; then
        scope_arg="--scope $VERCEL_SCOPE"
    fi
    
    for project in "${projects[@]}"; do
        if [[ -z "$project" ]]; then continue; fi
        
        printf "  Deleting %-40s " "$project..."
        
        if echo "y" | vercel project rm "$project" $scope_arg &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
            ((deleted++))
        else
            echo -e "${RED}✗${NC}"
            ((failed++))
            log_debug "Failed to delete: $project"
        fi
    done
    
    echo ""
    echo -e "  ${GREEN}Deleted: $deleted${NC}"
    if [[ $failed -gt 0 ]]; then
        echo -e "  ${RED}Failed:  $failed${NC}"
    fi
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------

main() {
    parse_args "$@"
    
    print_header
    
    # Step 1: Check prerequisites
    log_step "Prerequisites"
    check_vercel_cli
    check_vercel_login
    
    # Step 2: Get token and scope
    log_step "Configuration"
    
    if find_auth_token; then
        log_success "Auth token found"
    else
        log_warn "No auth token found (API mode unavailable)"
    fi
    
    if ! detect_scope; then
        log_warn "Could not detect scope"
    fi
    
    # Step 3: Fetch projects
    fetch_projects
    
    if [[ ${#PROJECT_NAMES[@]} -eq 0 ]]; then
        log_success "No projects found. Nothing to do!"
        exit 0
    fi
    
    # Step 4: Filter and display projects
    local filtered_projects
    filtered_projects=$(filter_projects)
    
    if ! display_projects "$filtered_projects"; then
        exit 0
    fi
    
    # Step 5: Get user input for which projects to keep
    local keep_projects_str
    keep_projects_str=$(prompt_keep_projects)
    
    local -a keep_projects=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            keep_projects+=("$line")
        fi
    done <<< "$keep_projects_str"
    
    # Step 6: Build delete list
    local delete_list
    delete_list=$(build_delete_list "$filtered_projects" "${keep_projects[@]}")
    
    local delete_count
    delete_count=$(echo "$delete_list" | grep -c '^' || echo 0)
    
    if [[ $delete_count -eq 0 ]]; then
        log_success "No projects to delete. All done!"
        exit 0
    fi
    
    # Step 7: Show delete preview
    log_step "Projects to Delete ($delete_count)"
    while IFS= read -r p; do
        if [[ -n "$p" ]]; then
            echo -e "  ${RED}✗${NC} $p"
        fi
    done <<< "$delete_list"
    echo ""
    
    # Step 8: Dry run or actual deletion
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}━━━ DRY RUN SUMMARY ━━━${NC}"
        echo ""
        echo -e "  Would keep:   ${GREEN}${#keep_projects[@]}${NC} project(s)"
        echo -e "  Would delete: ${RED}$delete_count${NC} project(s)"
        echo ""
        echo -e "${CYAN}Run without --dry-run to delete.${NC}"
        exit 0
    fi
    
    # Confirm and delete
    if ! confirm_deletion "$delete_count"; then
        log_warn "Aborted by user. No projects deleted."
        exit 0
    fi
    
    # Convert delete_list string to array
    local -a delete_array=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            delete_array+=("$line")
        fi
    done <<< "$delete_list"
    
    delete_projects "${delete_array[@]}"
    
    # Final summary
    log_step "Complete"
    log_info "Remaining projects:"
    vercel project ls ${VERCEL_SCOPE:+--scope $VERCEL_SCOPE} 2>&1 | \
        grep -E '^\s+\S+\s+(https?://|--)' | \
        awk '{print "  ✓ " $1}' || echo "  (none)"
    
    echo ""
    log_success "Cleanup finished! 🎉"
}

# Run main function
main "$@"
