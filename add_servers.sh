#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Файлы конфигурации
INVENTORY_FILE="inventory.ini"
CREATION_SCRIPT="create_containers.sh"
CLEAN_HOSTS_FILE="clean_known_hosts.yml"
FULL_DELETE_FILE="full_delete.yml"
GROUP_VARS_FILE="group_vars/all.yml"

# Функция для красивого вывода
print_header() {
    echo -e "${CYAN}"
    echo "=========================================="
    echo "   АВТОМАТИЧЕСКОЕ ДОБАВЛЕНИЕ СЕРВЕРОВ"
    echo "=========================================="
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Функция проверки существования файлов
check_files() {
    local missing_files=()
    
    for file in "$INVENTORY_FILE" "$CREATION_SCRIPT" "$CLEAN_HOSTS_FILE" "$FULL_DELETE_FILE" "$GROUP_VARS_FILE"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_error "Отсутствуют необходимые файлы:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        return 1
    fi
    
    print_success "Все необходимые файлы найдены"
    return 0
}

# Функция показа текущей конфигурации
show_current_config() {
    echo -e "${PURPLE}"
    echo "=== ТЕКУЩАЯ КОНФИГУРАЦИЯ ==="
    echo -e "${NC}"
    
    # Показываем текущие веб-серверы
    echo -e "${YELLOW}Текущие веб-серверы:${NC}"
    if [[ -f "$INVENTORY_FILE" ]]; then
        grep -A 10 "\[web_servers\]" "$INVENTORY_FILE" | grep -v "\[web_servers\]" | grep -v "^\-\-" | while read line; do
            if [[ ! -z "$line" ]]; then
                echo "  📍 $line"
            fi
        done
    fi
    
    # Показываем текущие контейнеры из скрипта создания
    echo -e "${YELLOW}Контейнеры в скрипте создания:${NC}"
    if [[ -f "$CREATION_SCRIPT" ]]; then
        grep -E '\["[0-9]+"\]=' "$CREATION_SCRIPT" | while read line; do
            if [[ $line == *"ct-web"* ]]; then
                echo "  🐳 $line"
            fi
        done
    fi
    
    echo
}

# Функция генерации следующего доступного IP
get_next_ip() {
    local base_ip="192.168.104"
    
    # Ищем все IP адреса в inventory.ini
    local last_ip_inventory=$(grep -oP '192\.168\.104\.\K[0-9]+' "$INVENTORY_FILE" 2>/dev/null | sort -n | tail -1)
    
    # Ищем все IP адреса в create_containers.sh
    local last_ip_script=$(grep -oP '192\.168\.104\.\K[0-9]+' "$CREATION_SCRIPT" 2>/dev/null | sort -n | tail -1)
    
    # Берем максимальный IP из обоих файлов
    local last_ip=$(( last_ip_inventory > last_ip_script ? last_ip_inventory : last_ip_script ))
    
    if [[ -z "$last_ip" ]] || [[ "$last_ip" -lt 92 ]]; then
        last_ip=92
    fi
    
    local next_ip=$((last_ip + 1))
    echo "${base_ip}.${next_ip}"
}

# Функция генерации следующего доступного ID контейнера
get_next_id() {
    local last_id=$(grep -oP '\["\K[0-9]+(?="\]=' "$CREATION_SCRIPT" 2>/dev/null | sort -n | tail -1)
    
    if [[ -z "$last_id" ]]; then
        last_id=102
    fi
    
    local next_id=$((last_id + 1))
    echo "$next_id"
}

# Функция получения количества текущих веб-серверов
get_web_server_count() {
    if [[ -f "$INVENTORY_FILE" ]]; then
        grep -A 20 "\[web_servers\]" "$INVENTORY_FILE" | grep -c "ct-web"
    else
        echo "0"
    fi
}

# Функция добавления веб-сервера
add_web_server() {
    local server_name=$1
    local ip_address=$2
    local container_id=$3
    
    print_info "Добавляем сервер: $server_name ($ip_address) ID: $container_id"
    
    # 1. Добавляем в инвентарь
    if ! grep -q "$server_name" "$INVENTORY_FILE"; then
        # Находим секцию [web_servers] и добавляем после нее
        if grep -q "\[web_servers\]" "$INVENTORY_FILE"; then
            # Используем sed для добавления строки после секции [web_servers]
            sed -i "/\[web_servers\]/a $server_name ansible_host=$ip_address ansible_user=root ansible_password=P@\\$\\$w0rd" "$INVENTORY_FILE"
            print_success "Добавлен в инвентарь"
        else
            print_error "Секция [web_servers] не найдена в $INVENTORY_FILE"
            return 1
        fi
    else
        print_warning "Сервер уже есть в инвентаре"
    fi
    
    # 2. Добавляем в скрипт создания контейнеров
    local container_line="    [\"$container_id\"]=\"$server_name,$ip_address,5,1,1024,512\""
    if ! grep -q "\[\"$container_id\"\]" "$CREATION_SCRIPT"; then
        # Находим место перед ct-db и добавляем перед ним
        if grep -q "\"ct-db" "$CREATION_SCRIPT"; then
            sed -i "/\"ct-db/ i $container_line" "$CREATION_SCRIPT"
            print_success "Добавлен в скрипт создания контейнеров"
        else
            # Если ct-db не найден, добавляем в конец массива CONTAINERS
            sed -i "/declare -A CONTAINERS=/,/)/ { /)/ i $container_line }" "$CREATION_SCRIPT"
            print_success "Добавлен в скрипт создания контейнеров (в конец массива)"
        fi
    else
        print_warning "Контейнер с ID $container_id уже есть в скрипте создания"
    fi
    
    # 3. Добавляем IP в clean_known_hosts.yml
    if [[ -f "$CLEAN_HOSTS_FILE" ]]; then
        if ! grep -q "$ip_address" "$CLEAN_HOSTS_FILE"; then
            sed -i "/container_ips:/a \      - $ip_address" "$CLEAN_HOSTS_FILE"
            print_success "Добавлен в список очистки known_hosts"
        fi
    else
        print_warning "Файл $CLEAN_HOSTS_FILE не найден, пропускаем"
    fi
    
    # 4. Добавляем ID в full_delete.yml
    if [[ -f "$FULL_DELETE_FILE" ]]; then
        if ! grep -q "      - $container_id" "$FULL_DELETE_FILE"; then
            sed -i "/containers:/a \      - $container_id" "$FULL_DELETE_FILE"
            print_success "Добавлен в список удаления контейнеров"
        fi
    else
        print_warning "Файл $FULL_DELETE_FILE не найден, пропускаем"
    fi
    
    return 0
}

# Функция автоматического добавления сервера
auto_add_server() {
    echo -e "${CYAN}"
    echo "=== АВТОМАТИЧЕСКОЕ ДОБАВЛЕНИЕ СЕРВЕРА ==="
    echo -e "${NC}"
    
    local next_id=$(get_next_id)
    local next_ip=$(get_next_ip)
    local server_count=$(get_web_server_count)
    local next_server_num=$((server_count + 1))
    local server_name="ct-web${next_server_num}"
    
    echo -e "${YELLOW}Предлагаемая конфигурация:${NC}"
    echo "  🆔 ID контейнера: $next_id"
    echo "  🌐 Имя сервера: $server_name"
    echo "  📡 IP адрес: $next_ip"
    echo "  💾 Ресурсы: 5 CPU, 1024MB RAM, 512MB Swap"
    
    echo
    read -p "Вы хотите добавить этот сервер? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if add_web_server "$server_name" "$next_ip" "$next_id"; then
            print_success "Сервер $server_name успешно добавлен в конфигурацию!"
        else
            print_error "Ошибка при добавлении сервера"
        fi
    else
        print_warning "Добавление отменено"
    fi
}

# Функция ручного добавления сервера
manual_add_server() {
    echo -e "${CYAN}"
    echo "=== РУЧНОЕ ДОБАВЛЕНИЕ СЕРВЕРА ==="
    echo -e "${NC}"
    
    local next_id=$(get_next_id)
    local next_ip=$(get_next_ip)
    
    read -p "Введите ID контейнера [по умолчанию: $next_id]: " container_id
    container_id=${container_id:-$next_id}
    
    read -p "Введите имя сервера [например: ct-web3]: " server_name
    if [[ -z "$server_name" ]]; then
        print_error "Имя сервера обязательно!"
        return 1
    fi
    
    read -p "Введите IP адрес [по умолчанию: $next_ip]: " ip_address
    ip_address=${ip_address:-$next_ip}
    
    # Валидация ввода
    if ! [[ "$container_id" =~ ^[0-9]+$ ]]; then
        print_error "ID контейнера должен быть числом!"
        return 1
    fi
    
    if ! [[ "$ip_address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Некорректный IP адрес!"
        return 1
    fi
    
    echo
    echo -e "${YELLOW}Подтвердите добавление:${NC}"
    echo "  🆔 ID контейнера: $container_id"
    echo "  🌐 Имя сервера: $server_name"
    echo "  📡 IP адрес: $ip_address"
    echo "  💾 Ресурсы: 5 CPU, 1024MB RAM, 512MB Swap"
    
    echo
    read -p "Добавить этот сервер? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if add_web_server "$server_name" "$ip_address" "$container_id"; then
            print_success "Сервер $server_name успешно добавлен в конфигурацию!"
        else
            print_error "Ошибка при добавлении сервера"
        fi
    else
        print_warning "Добавление отменено"
    fi
}

# Функция массового добавления серверов
bulk_add_servers() {
    echo -e "${CYAN}"
    echo "=== МАССОВОЕ ДОБАВЛЕНИЕ СЕРВЕРОВ ==="
    echo -e "${NC}"
    
    read -p "Сколько серверов добавить? " count
    
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]]; then
        print_error "Некорректное количество!"
        return 1
    fi
    
    echo
    print_warning "Будет добавлено $count серверов:"
    
    local current_id=$(get_next_id)
    local current_ip=$(get_next_ip)
    
    for ((i=1; i<=count; i++)); do
        local server_num=$(( $(get_web_server_count) + 1 ))
        local server_name="ct-web${server_num}"
        
        echo "  $i. $server_name - ID: $current_id - IP: $current_ip"
        
        if add_web_server "$server_name" "$current_ip" "$current_id"; then
            print_success "  ✓ Добавлен"
        else
            print_error "  ✗ Ошибка"
        fi
        
        current_id=$((current_id + 1))
        
        # Увеличиваем IP адрес
        local ip_part=$(echo "$current_ip" | cut -d. -f4)
        local base_ip=$(echo "$current_ip" | cut -d. -f1-3)
        ip_part=$((ip_part + 1))
        current_ip="${base_ip}.${ip_part}"
        
        sleep 1
    done
    
    print_success "Успешно добавлено $count серверов!"
}

# Функция применения изменений
apply_changes() {
    echo -e "${CYAN}"
    echo "=== ПРИМЕНЕНИЕ ИЗМЕНЕНИЙ ==="
    echo -e "${NC}"
    
    echo "Выберите действие:"
    echo "  1) Только обновить конфигурацию"
    echo "  2) Создать и настроить новые контейнеры"
    echo "  3) Полное переразвертывание"
    echo "  0) Назад"
    
    read -p "Выберите вариант [0-3]: " choice
    
    case $choice in
        1)
            print_success "Конфигурация обновлена"
            ;;
        2)
            echo
            print_info "Запуск создания новых контейнеров..."
            ansible-playbook run_create_containers.yml
            echo
            print_info "Очистка known_hosts..."
            ansible-playbook clean_known_hosts.yml
            echo
            print_info "Запуск настройки..."
            ansible-playbook run_playbook.yml
            ;;
        3)
            echo
            print_warning "ВНИМАНИЕ: Будет выполнено полное переразвертывание!"
            read -p "Вы уверены? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                echo
                print_info "Удаление старых контейнеров..."
                ansible-playbook full_delete.yml
                echo
                print_info "Создание новых контейнеров..."
                ansible-playbook run_create_containers.yml
                echo
                print_info "Очистка known_hosts..."
                ansible-playbook clean_known_hosts.yml
                echo
                print_info "Настройка кластера..."
                ansible-playbook run_playbook.yml
            else
                print_warning "Переразвертывание отменено"
            fi
            ;;
        0)
            return
            ;;
        *)
            print_error "Некорректный выбор"
            ;;
    esac
}

# Главное меню
main_menu() {
    while true; do
        print_header
        show_current_config
        
        echo -e "${GREEN}ГЛАВНОЕ МЕНЮ:${NC}"
        echo "  1) 🔍 Показать текущую конфигурацию"
        echo "  2) 🤖 Автоматически добавить сервер"
        echo "  3) ✍️  Ручное добавление сервера"
        echo "  4) 📦 Массовое добавление серверов"
        echo "  5) 🚀 Применить изменения"
        echo "  6) 🧹 Проверить целостность файлов"
        echo "  0) ❌ Выход"
        echo
        
        read -p "Выберите действие [0-6]: " choice
        
        case $choice in
            1)
                show_current_config
                ;;
            2)
                auto_add_server
                ;;
            3)
                manual_add_server
                ;;
            4)
                bulk_add_servers
                ;;
            5)
                apply_changes
                ;;
            6)
                check_files
                ;;
            0)
                echo -e "${GREEN}До свидания!${NC}"
                exit 0
                ;;
            *)
                print_error "Некорректный выбор!"
                ;;
        esac
        
        echo
        read -p "Нажмите Enter для продолжения..."
        clear
    done
}

# Запуск скрипта
clear
if check_files; then
    main_menu
else
    print_error "Не удалось запустить скрипт. Проверьте наличие необходимых файлов."
    exit 1
fi
