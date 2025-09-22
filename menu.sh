#!/data/data/com.termux/files/usr/bin/bash

# Configuración
GITHUB_TOKEN="TU_TOKEN_GIT"
API_URL="https://api.github.com"
USERNAME=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/user" | grep '"login":' | cut -d'"' -f4)
EMAIL=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/user" | grep '"email":' | cut -d'"' -f4)

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Función para mostrar el menú principal
show_menu() {
    clear
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE}       GESTOR AVANZADO DE REPOSITORIOS       ${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo -e "Usuario: ${GREEN}$USERNAME${NC}"
    echo -e "Email: ${GREEN}$EMAIL${NC}"
    echo -e ""
    echo -e "${CYAN}1. Listar repositorios${NC}"
    echo -e "${CYAN}2. Crear nuevo repositorio${NC}"
    echo -e "${CYAN}3. Clonar repositorio${NC}"
    echo -e "${CYAN}4. Actualizar información de repositorio${NC}"
    echo -e "${YELLOW}5. Eliminar un repositorio específico${NC}"
    echo -e "${YELLOW}6. Realizar commit y push${NC}"
    echo -e "${YELLOW}7. Crear un issue${NC}"
    echo -e "${YELLOW}8. Listar issues${NC}"
    echo -e "${PURPLE}9. Crear un release${NC}"
    echo -e "${PURPLE}10. Forkear un repositorio${NC}"
    echo -e "${PURPLE}11. Ver estadísticas${NC}"
    echo -e "${RED}12. ELIMINAR TODOS LOS REPOSITORIOS${NC}"
    echo -e "${BLUE}13. Salir${NC}"
    echo -e ""
    echo -e "${RED}ADVERTENCIA: La opción 12 es irreversible${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo -n "Selecciona una opción [1-13]: "
}

# Función para listar repositorios
list_repos() {
    echo -e "${BLUE}Listando repositorios...${NC}"
    echo -e ""
    
    page=1
    repo_count=0
    while true; do
        response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$API_URL/user/repos?page=$page&per_page=100&sort=updated")
        if echo "$response" | grep -q "Not Found"; then
            break
        fi
        
        current_count=$(echo "$response" | grep -o '"full_name":' | wc -l)
        if [ "$current_count" -eq 0 ]; then
            break
        fi
        
        # Mostrar información detallada de cada repo
        echo "$response" | jq -r '.[] | "\(.full_name) | \(.description // "Sin descripción") | \(.language // "N/A") | \(.stargazers_count)⭐ | \(.fork | if . then "Forked" else "Original" end)"' 2>/dev/null || \
        echo "$response" | grep -E '"full_name":|"description":|"language":|"stargazers_count":|"fork":' | \
        awk -F '"' '{
            if ($2 == "full_name") {name = $4}
            if ($2 == "description") {desc = $4}
            if ($2 == "language") {lang = $4}
            if ($2 == "stargazers_count") {stars = $3}
            if ($2 == "fork") {is_fork = $3}
            if (name && desc && lang && stars && is_fork) {
                printf "%-30s | %-40s | %-10s | %2s⭐ | %s\n", name, (length(desc) > 40 ? substr(desc,1,37)"..." : desc), (lang == "" ? "N/A" : lang), stars, (is_fork ~ /true/ ? "Forked" : "Original");
                name=""; desc=""; lang=""; stars=""; is_fork=""
            }
        }' | sed 's/,[^,]*$//'
        
        repo_count=$((repo_count + current_count))
        page=$((page + 1))
    done
    
    echo -e ""
    echo -e "${GREEN}Total de repositorios: $repo_count${NC}"
    echo -e ""
    read -p "Presiona Enter para continuar..."
}

# Función para crear un nuevo repositorio
create_repo() {
    echo -e "${BLUE}Creando nuevo repositorio...${NC}"
    echo -n "Nombre del repositorio: "
    read repo_name
    
    if [ -z "$repo_name" ]; then
        echo -e "${RED}El nombre no puede estar vacío${NC}"
        return
    fi
    
    echo -n "Descripción (opcional): "
    read repo_description
    
    echo -n "¿Es privado? [s/N]: "
    read is_private
    private=false
    if [ "$is_private" = "s" ] || [ "$is_private" = "S" ]; then
        private=true
    fi
    
    echo -n "¿Añadir README? [s/N]: "
    read add_readme
    auto_init=false
    if [ "$add_readme" = "s" ] || [ "$add_readme" = "S" ]; then
        auto_init=true
    fi
    
    # Crear el JSON para la solicitud
    json_data=$(jq -n \
                  --arg name "$repo_name" \
                  --arg desc "$repo_description" \
                  --argjson private "$private" \
                  --argjson auto_init "$auto_init" \
                  '{name: $name, description: $desc, private: $private, auto_init: $auto_init}')
    
    response=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
                   -d "$json_data" "$API_URL/user/repos")
    
    if echo "$response" | grep -q '"html_url"'; then
        clone_url=$(echo "$response" | grep '"clone_url"' | cut -d'"' -f4)
        echo -e "${GREEN}Repositorio creado exitosamente!${NC}"
        echo -e "${CYAN}URL: $clone_url${NC}"
        
        echo -n "¿Quieres clonarlo ahora? [s/N]: "
        read clone_now
        if [ "$clone_now" = "s" ] || [ "$clone_now" = "S" ]; then
            git clone "$clone_url"
            echo -e "${GREEN}Repositorio clonado en el directorio actual${NC}"
        fi
    else
        echo -e "${RED}Error al crear el repositorio: $response${NC}"
    fi
    
    read -p "Presiona Enter para continuar..."
}

# Función para clonar un repositorio
clone_repo() {
    echo -e "${BLUE}Clonar repositorio...${NC}"
    echo -n "Nombre del repositorio (formato: usuario/repo o URL HTTPS): "
    read repo_input
    
    if [ -z "$repo_input" ]; then
        echo -e "${RED}No se introdujo ningún nombre${NC}"
        return
    fi
    
    # Si es una URL completa
    if echo "$repo_input" | grep -q "https://"; then
        clone_url="$repo_input"
    else
        # Verificar si el repositorio existe
        response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$API_URL/repos/$repo_input")
        if echo "$response" | grep -q '"not found"'; then
            echo -e "${RED}El repositorio no existe o no tienes acceso${NC}"
            return
        fi
        clone_url=$(echo "$response" | grep '"clone_url"' | cut -d'"' -f4)
    fi
    
    # Clonar el repositorio
    git clone "$clone_url"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Repositorio clonado exitosamente!${NC}"
    else
        echo -e "${RED}Error al clonar el repositorio${NC}"
    fi
    
    read -p "Presiona Enter para continuar..."
}

# Función para actualizar información de repositorio
update_repo() {
    echo -e "${BLUE}Actualizar información de repositorio...${NC}"
    echo -n "Nombre actual del repositorio (formato: usuario/repo): "
    read repo_name
    
    if [ -z "$repo_name" ]; then
        echo -e "${RED}No se introdujo ningún nombre${NC}"
        return
    fi
    
    # Verificar si el repositorio existe
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$API_URL/repos/$repo_name")
    if echo "$response" | grep -q '"not found"'; then
        echo -e "${RED}El repositorio no existe o no tienes acceso${NC}"
        return
    fi
    
    echo -n "Nuevo nombre (dejar vacío para no cambiar): "
    read new_name
    echo -n "Nueva descripción (dejar vacío para no cambiar): "
    read new_description
    echo -n "¿Es privado? [s/N/actual]: "
    read new_private
    
    # Preparar datos para actualización
    json_data="{"
    if [ -n "$new_name" ]; then
        json_data="$json_data\"name\":\"$new_name\","
    fi
    if [ -n "$new_description" ]; then
        json_data="$json_data\"description\":\"$new_description\","
    fi
    if [ "$new_private" = "s" ] || [ "$new_private" = "S" ]; then
        json_data="$json_data\"private\":true,"
    elif [ "$new_private" = "n" ] || [ "$new_private" = "N" ]; then
        json_data="$json_data\"private\":false,"
    fi
    json_data="${json_data%,}}"
    
    if [ "$json_data" = "{}" ]; then
        echo -e "${YELLOW}No se especificaron cambios${NC}"
        return
    fi
    
    response=$(curl -s -X PATCH -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
                   -d "$json_data" "$API_URL/repos/$repo_name")
    
    if echo "$response" | grep -q '"name"'; then
        echo -e "${GREEN}Repositorio actualizado exitosamente!${NC}"
        new_full_name=$(echo "$response" | grep '"full_name"' | cut -d'"' -f4)
        echo -e "${CYAN}Nombre actualizado: $new_full_name${NC}"
    else
        echo -e "${RED}Error al actualizar el repositorio: $response${NC}"
    fi
    
    read -p "Presiona Enter para continuar..."
}

# Función para eliminar un repositorio específico
delete_specific_repo() {
    echo -n "Introduce el nombre del repositorio a eliminar (formato: usuario/repo): "
    read repo_name
    
    if [ -z "$repo_name" ]; then
        echo -e "${RED}No se introdujo ningún nombre${NC}"
        return
    fi
    
    echo -e "${YELLOW}¿Estás seguro de que quieres eliminar '$repo_name'? [s/N]: ${NC}"
    read confirmation
    
    if [ "$confirmation" != "s" ] && [ "$confirmation" != "S" ]; then
        echo -e "${BLUE}Operación cancelada${NC}"
        return
    fi
    
    response=$(curl -s -X DELETE -H "Authorization: token $GITHUB_TOKEN" "$API_URL/repos/$repo_name")
    
    if [ -z "$response" ]; then
        echo -e "${GREEN}Repositorio '$repo_name' eliminado correctamente${NC}"
    else
        echo -e "${RED}Error al eliminar el repositorio: $response${NC}"
    fi
    
    read -p "Presiona Enter para continuar..."
}

# Función para realizar commit y push
commit_and_push() {
    echo -e "${BLUE}Realizar commit y push...${NC}"
    
    # Verificar si estamos en un repositorio git
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo -e "${RED}No estás dentro de un repositorio Git${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi
    
    # Mostrar cambios actuales
    echo -e "${CYAN}Estado actual:${NC}"
    git status --short
    
    echo -n "¿Quieres añadir todos los cambios? [s/N]: "
    read add_all
    if [ "$add_all" = "s" ] || [ "$add_all" = "S" ]; then
        git add .
        echo -e "${GREEN}Todos los cambios añadidos${NC}"
    else
        echo -n "Introduce los archivos específicos para añadir (separados por espacios): "
        read files_to_add
        if [ -n "$files_to_add" ]; then
            git add $files_to_add
            echo -e "${GREEN}Archivos añadidos${NC}"
        fi
    fi
    
    echo -n "Mensaje del commit: "
    read commit_message
    if [ -z "$commit_message" ]; then
        commit_message="Actualización $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    
    git commit -m "$commit_message"
    
    echo -n "¿Quieres hacer push? [S/n]: "
    read do_push
    if [ "$do_push" != "n" ] && [ "$do_push" != "N" ]; then
        current_branch=$(git branch --show-current)
        git push origin "$current_branch"
        echo -e "${GREEN}Push completado${NC}"
    fi
    
    read -p "Presiona Enter para continuar..."
}

# Función para crear un issue
create_issue() {
    echo -e "${BLUE}Crear un issue...${NC}"
    echo -n "Repositorio (formato: usuario/repo): "
    read repo_name
    
    if [ -z "$repo_name" ]; then
        echo -e "${RED}No se introdujo ningún nombre${NC}"
        return
    fi
    
    echo -n "Título del issue: "
    read issue_title
    echo -n "Descripción del issue (multilínea, termina con Ctrl+D): "
    read -d '' issue_body
    
    json_data=$(jq -n \
                  --arg title "$issue_title" \
                  --arg body "$issue_body" \
                  '{title: $title, body: $body}')
    
    response=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
                   -d "$json_data" "$API_URL/repos/$repo_name/issues")
    
    if echo "$response" | grep -q '"html_url"'; then
        issue_url=$(echo "$response" | grep '"html_url"' | cut -d'"' -f4)
        echo -e "${GREEN}Issue creado exitosamente!${NC}"
        echo -e "${CYAN}URL: $issue_url${NC}"
    else
        echo -e "${RED}Error al crear el issue: $response${NC}"
    fi
    
    read -p "Presiona Enter para continuar..."
}

# Función para listar issues
list_issues() {
    echo -e "${BLUE}Listar issues...${NC}"
    echo -n "Repositorio (formato: usuario/repo): "
    read repo_name
    
    if [ -z "$repo_name" ]; then
        echo -e "${RED}No se introdujo ningún nombre${NC}"
        return
    fi
    
    echo -n "Estado (open, closed, all) [open]: "
    read issue_state
    if [ -z "$issue_state" ]; then
        issue_state="open"
    fi
    
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$API_URL/repos/$repo_name/issues?state=$issue_state")
    
    if echo "$response" | grep -q '"not found"'; then
        echo -e "${RED}El repositorio no existe o no tienes acceso${NC}"
        return
    fi
    
    echo -e "${CYAN}Issues en $repo_name:${NC}"
    echo "$response" | jq -r '.[] | "#\(.number): \(.title) [\(.state)] - \(.user.login)"' 2>/dev/null || \
    echo "$response" | grep -E '"number":|"title":|"state":|"login":' | \
    awk -F '"' '{
        if ($2 == "number") {number = $4}
        if ($2 == "title") {title = $4}
        if ($2 == "state") {state = $4}
        if ($2 == "login") {login = $4}
        if (number && title && state && login) {
            printf "#%s: %s [%s] - %s\n", number, (length(title) > 50 ? substr(title,1,47)"..." : title), state, login;
            number=""; title=""; state=""; login=""
        }
    }'
    
    read -p "Presiona Enter para continuar..."
}

# Función para crear un release
create_release() {
    echo -e "${BLUE}Crear un release...${NC}"
    echo -n "Repositorio (formato: usuario/repo): "
    read repo_name
    
    if [ -z "$repo_name" ]; then
        echo -e "${RED}No se introdujo ningún nombre${NC}"
        return
    fi
    
    echo -n "Tag name (ej: v1.0.0): "
    read tag_name
    echo -n "Nombre del release: "
    read release_name
    echo -n "Descripción: "
    read release_body
    echo -n "¿Es pre-release? [s/N]: "
    read is_prerelease
    
    prerelease=false
    if [ "$is_prerelease" = "s" ] || [ "$is_prerelease" = "S" ]; then
        prerelease=true
    fi
    
    json_data=$(jq -n \
                  --arg tag_name "$tag_name" \
                  --arg name "$release_name" \
                  --arg body "$release_body" \
                  --argjson prerelease "$prerelease" \
                  '{tag_name: $tag_name, name: $name, body: $body, prerelease: $prerelease}')
    
    response=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
                   -d "$json_data" "$API_URL/repos/$repo_name/releases")
    
    if echo "$response" | grep -q '"html_url"'; then
        release_url=$(echo "$response" | grep '"html_url"' | cut -d'"' -f4)
        echo -e "${GREEN}Release creado exitosamente!${NC}"
        echo -e "${CYAN}URL: $release_url${NC}"
    else
        echo -e "${RED}Error al crear el release: $response${NC}"
    fi
    
    read -p "Presiona Enter para continuar..."
}

# Función para forkear un repositorio
fork_repo() {
    echo -e "${BLUE}Forkear un repositorio...${NC}"
    echo -n "Repositorio a forkear (formato: usuario/repo): "
    read repo_name
    
    if [ -z "$repo_name" ]; then
        echo -e "${RED}No se introdujo ningún nombre${NC}"
        return
    fi
    
    response=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" "$API_URL/repos/$repo_name/forks")
    
    if echo "$response" | grep -q '"full_name"'; then
        forked_name=$(echo "$response" | grep '"full_name"' | cut -d'"' -f4)
        clone_url=$(echo "$response" | grep '"clone_url"' | cut -d'"' -f4)
        echo -e "${GREEN}Repositorio forkeado exitosamente!${NC}"
        echo -e "${CYAN}Nombre: $forked_name${NC}"
        echo -e "${CYAN}URL para clonar: $clone_url${NC}"
        
        echo -n "¿Quieres clonarlo ahora? [s/N]: "
        read clone_now
        if [ "$clone_now" = "s" ] || [ "$clone_now" = "S" ]; then
            git clone "$clone_url"
            echo -e "${GREEN}Repositorio clonado${NC}"
        fi
    else
        echo -e "${RED}Error al forkear el repositorio: $response${NC}"
    fi
    
    read -p "Presiona Enter para continuar..."
}

# Función para ver estadísticas
show_stats() {
    echo -e "${BLUE}Estadísticas del usuario...${NC}"
    
    # Obtener información del usuario
    user_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$API_URL/users/$USERNAME")
    public_repos=$(echo "$user_info" | grep '"public_repos":' | cut -d':' -f2 | tr -d ' ,')
    followers=$(echo "$user_info" | grep '"followers":' | cut -d':' -f2 | tr -d ' ,')
    following=$(echo "$user_info" | grep '"following":' | cut -d':' -f2 | tr -d ' ,')
    
    echo -e "${CYAN}Repositorios públicos: ${GREEN}$public_repos${NC}"
    echo -e "${CYAN}Seguidores: ${GREEN}$followers${NC}"
    echo -e "${CYAN}Siguiendo: ${GREEN}$following${NC}"
    
    # Contar repositorios totales (públicos y privados)
    total_repos=0
    page=1
    while true; do
        response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$API_URL/user/repos?page=$page&per_page=100")
        count=$(echo "$response" | grep -o '"full_name":' | wc -l)
        if [ "$count" -eq 0 ]; then
            break
        fi
        total_repos=$((total_repos + count))
        page=$((page + 1))
    done
    
    echo -e "${CYAN}Total de repositorios (públicos + privados): ${GREEN}$total_repos${NC}"
    
    read -p "Presiona Enter para continuar..."
}

# Función para eliminar TODOS los repositorios
delete_all_repos() {
    echo -e "${RED}===================================================${NC}"
    echo -e "${RED}         ADVERTENCIA: OPERACIÓN PELIGROSA         ${NC}"
    echo -e "${RED}===================================================${NC}"
    echo -e ""
    echo -e "Estás a punto de eliminar ${RED}TODOS${NC} tus repositorios de GitHub."
    echo -e "Esta acción es ${RED}IRREVERSIBLE${NC} y puede causar pérdida de datos."
    echo -e ""
    echo -n "Para confirmar, escribe 'ELIMINAR TODOS': "
    read confirmation
    
    if [ "$confirmation" != "ELIMINAR TODOS" ]; then
        echo -e "${BLUE}Operación cancelada${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi
    
    echo -e "${YELLOW}Eliminando todos los repositorios...${NC}"
    
    page=1
    deleted_count=0
    while true; do
        response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$API_URL/user/repos?page=$page&per_page=100")
        if echo "$response" | grep -q "Not Found"; then
            break
        fi
        
        repos=$(echo "$response" | grep '"full_name":' | cut -d'"' -f4)
        if [ -z "$repos" ]; then
            break
        fi
        
        for repo in $repos; do
            # No eliminar repositorios por defecto de GitHub
            if [ "$repo" != "$USERNAME/.github" ]; then
                echo -e "${YELLOW}Eliminando: $repo${NC}"
                curl -s -X DELETE -H "Authorization: token $GITHUB_TOKEN" "$API_URL/repos/$repo" > /dev/null
                deleted_count=$((deleted_count + 1))
            fi
        done
        
        page=$((page + 1))
    done
    
    echo -e "${GREEN}Proceso completado. Se eliminaron $deleted_count repositorios.${NC}"
    read -p "Presiona Enter para continuar..."
}

# Verificar token y conexión
check_auth() {
    echo -e "${BLUE}Verificando token...${NC}"
    response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "$API_URL/user")
    
    if [ "$response" -ne 200 ]; then
        echo -e "${RED}Error: Token inválido o sin permisos${NC}"
        echo -e "Por favor, verifica tu token de GitHub"
        exit 1
    fi
    
    echo -e "${GREEN}Token verificado correctamente${NC}"
    sleep 1
}

# Instalar dependencias si es necesario
install_dependencies() {
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Instalando jq...${NC}"
        pkg update && pkg install -y jq
    fi
    
    if ! command -v git &> /dev/null; then
        echo -e "${YELLOW}Instalando git...${NC}"
        pkg update && pkg install -y git
    fi
}

# Programa principal
main() {
    install_dependencies
    check_auth
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1) list_repos ;;
            2) create_repo ;;
            3) clone_repo ;;
            4) update_repo ;;
            5) delete_specific_repo ;;
            6) commit_and_push ;;
            7) create_issue ;;
            8) list_issues ;;
            9) create_release ;;
            10) fork_repo ;;
            11) show_stats ;;
            12) delete_all_repos ;;
            13) echo -e "${BLUE}Saliendo...${NC}"; exit 0 ;;
            *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}

# Ejecutar programa principal
main