# Документация по Ansible проекту для развертывания веб-кластера на Proxmox


## Обзор проекта

Данный проект автоматизирует развертывание высокодоступного веб-кластера на платформе Proxmox VE с использованием LXC контейнеров и Ansible. Архитектура включает:

- **Балансировщик нагрузки** (HAProxy) - распределяет трафик между веб-серверами
- **Веб-серверы** (2 экземпляра) - Nginx + PHP-FPM с приложением
- **Сервер базы данных** - MySQL для хранения данных приложения


### Инструкция по добавлению дополнительных веб-серверов
Шаг 1: Добавление новых контейнеров в скрипт создания
Отредактируйте файл create_containers.sh - добавьте новые контейнеры в массив CONTAINERS:

# В секции "Конфигурация контейнеров" добавьте:
```
declare -A CONTAINERS=(
    ["100"]="ct-lb,192.168.104.90,2,1,512,256"
    ["101"]="ct-web1,192.168.104.91,5,1,1024,512" 
    ["102"]="ct-web2,192.168.104.92,5,1,1024,512"
    ["103"]="ct-web3,192.168.104.94,5,1,1024,512"  # НОВЫЙ
    ["104"]="ct-web4,192.168.104.95,5,1,1024,512"  # НОВЫЙ
    ["105"]="ct-db,192.168.104.93,10,2,2048,1024"  # ID изменен на 105
)
```
Шаг 2: Обновление инвентаря Ansible
Отредактируйте файл inventory.ini - добавьте новые веб-серверы:
```
[proxmox]
192.168.104.177 ansible_user=root ansible_password=P@$$w0rd

[load_balancer]
ct-lb ansible_host=192.168.104.90 ansible_user=root ansible_password=P@$$w0rd

[web_servers]
ct-web1 ansible_host=192.168.104.91 ansible_user=root ansible_password=P@$$w0rd
ct-web2 ansible_host=192.168.104.92 ansible_user=root ansible_password=P@$$w0rd
ct-web3 ansible_host=192.168.104.94 ansible_user=root ansible_password=P@$$w0rd  # НОВЫЙ
ct-web4 ansible_host=192.168.104.95 ansible_user=root ansible_password=P@$$w0rd  # НОВЫЙ

[database]
ct-db ansible_host=192.168.104.93 ansible_user=root ansible_password=P@$$w0rd ansible_python_interpreter=/usr/bin/python3

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

## Структура проекта

```
.
├── ansible.cfg                    # Конфигурация Ansible
├── inventory.ini                  # Инвентарь хостов
├── group_vars/
│   └── all.yml                   # Общие переменные
├── roles/
│   ├── common/                   # Общие настройки для всех серверов
│   ├── database/                 # Роль для настройки MySQL
│   ├── web/                      # Роль для настройки веб-серверов
│   └── haproxy/                  # Роль для настройки балансировщика
├── run_create_containers.yml     # Плейбук создания контейнеров
├── run_playbook.yml              # Основной плейбук развертывания
├── create_containers.sh          # Скрипт создания LXC контейнеров
├── full_delete.yml               # Плейбук удаления контейнеров
├── clean_known_hosts.yml         # Очистка SSH known_hosts
└── fix_web.yml                   # Исправление конфигурации PHP-FPM
```
```
.
├── ansible.cfg
├── clean_known_hosts.yml
├── create_containers.sh
├── database
│   └── tasks
│       └── main.yml
├── fix_web.yml
├── full_delete.yml
├── group_vars
│   └── all.yml
├── inventory.ini
├── pre_install.yml
├── README.md
├── roles
│   ├── common
│   │   ├── handlers
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   ├── database
│   │   ├── handlers
│   │   │   └── main.yml
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   │       ├── init_db.sql.j2
│   │       └── myapp_db.sql.j2
│   ├── haproxy
│   │   ├── handlers
│   │   │   └── main.yml
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   │       └── haproxy.cfg.j2
│   └── web
│       ├── handlers
│       │   └── main.yml
│       ├── tasks
│       │   └── main.yml
│       └── templates
│           ├── index.html.j2
│           └── nginx.conf.j2
├── run_create_containers.yml
└── run_playbook.yml
```
## Предварительные требования

1. **Proxmox VE сервер** с настроенной сетью и LXC поддержкой
2. **Ansible** установленный на управляющей машине
3. **SSH доступ** к Proxmox серверу
4. **Доступ к интернету** для загрузки образов и пакетов

## Быстрый старт

### Шаг 1: Настройка инвентаря

Проверьте файл `inventory.ini` и обновите IP адреса при необходимости:

```ini
[proxmox]
192.168.104.177 ansible_user=root ansible_password=P@$$w0rd

[load_balancer]
ct-lb ansible_host=192.168.104.90 ansible_user=root ansible_password=P@$$w0rd

[web_servers]
ct-web1 ansible_host=192.168.104.91 ansible_user=root ansible_password=P@$$w0rd
ct-web2 ansible_host=192.168.104.92 ansible_user=root ansible_password=P@$$w0rd

[database]
ct-db ansible_host=192.168.104.93 ansible_user=root ansible_password=P@$$w0rd
```

### Шаг 2: Создание контейнеров

```bash
ansible-playbook run_create_containers.yml
```

**Что делает этот плейбук:**
- Скачивает образ Ubuntu 22.04 LXC (если отсутствует)
- Создает 4 LXC контейнера:
  - `ct-lb` (100) - балансировщик нагрузки, 2 CPU, 512MB RAM
  - `ct-web1` (101) - веб-сервер 1, 5 CPU, 1024MB RAM
  - `ct-web2` (102) - веб-сервер 2, 5 CPU, 1024MB RAM
  - `ct-db` (103) - база данных, 10 CPU, 2048MB RAM
- Настраивает SSH доступ для всех контейнеров
- Запускает контейнеры и проверяет их статус

### Шаг 3: Развертывание приложения

```bash
ansible-playbook run_playbook.yml
```

**Что делает этот плейбук:**

#### 1. Общие настройки (для всех серверов)
- Обновление пакетов
- Установка Python3 и базовых утилит
- Настройка фаервола (открыты порты: 22, 80, 8080, 1936, 3306)
- Установка временной зоны Europe/Moscow

#### 2. Настройка базы данных
- Установка MySQL Server
- Создание базы данных `myapp_db`
- Создание пользователя `myapp_user`
- Импорт схемы базы данных
- Настройка доступа по сети

#### 3. Настройка веб-серверов
- Установка Nginx + PHP-FPM 8.1
- Развертывание PHP приложения
- Настройка виртуальных хостов
- Создание health-check эндпоинта

#### 4. Настройка балансировщика
- Установка HAProxy
- Конфигурация балансировки между веб-серверами
- Настройка статистики HAProxy

#### 5. Проверка развертывания
- Тестирование доступности балансировщика
- Вывод информации о развернутых сервисах

## Доступ к сервисам

После успешного развертывания доступны следующие endpoints:

- **Веб-приложение**: http://192.168.104.90:80
- **Статистика HAProxy**: http://192.168.104.90:1936
  - Логин: `admin`
  - Пароль: `admin123`
- **Прямой доступ к веб-серверам**:
  - http://192.168.104.91:8080
  - http://192.168.104.92:8080

## Функциональность приложения

Веб-приложение отображает:
- Информацию о сервере (hostname, IP адрес)
- Статус подключения к базе данных
- Счетчик посещений (общий для всех серверов)
- Время выполнения запроса

База данных хранит:
- Историю посещений с указанием сервера
- Общий счетчик посещений кластера

## Дополнительные плейбуки

### Очистка SSH known_hosts

```bash
ansible-playbook clean_known_hosts.yml
```
Удаляет старые SSH ключи контейнеров и добавляет новые.

### Полное удаление контейнеров

```bash
ansible-playbook full_delete.yml
```
Полностью удаляет все созданные контейнеры и их конфигурации.

### Исправление конфигурации PHP-FPM

```bash
ansible-playbook fix_web.yml
```
Исправляет проблемы с PHP-FPM сокетами на веб-серверах.

## Переменные конфигурации

Основные переменные в `group_vars/all.yml`:

```yaml
db_name: myapp_db           # Имя базы данных
db_user: myapp_user         # Пользователь БД
db_password: secure_password # Пароль БД

app_port: 8080              # Порт веб-приложения
lb_port: 80                 # Порт балансировщика

haproxy_stats_port: 1936    # Порт статистики HAProxy
haproxy_stats_user: admin   # Пользователь статистики
haproxy_stats_password: admin123 # Пароль статистики
```

## Мониторинг и отладка

### Проверка состояния контейнеров
```bash
pct list
```

### Проверка логов
```bash
# Логи HAProxy
journalctl -u haproxy

# Логи Nginx
journalctl -u nginx

# Логи MySQL
journalctl -u mysql
```

### Тестирование балансировки
```bash
# Многократный доступ к приложению для проверки балансировки
for i in {1..10}; do curl -s http://192.168.104.90 | grep "Server Information"; done
```

## Устранение неполадок

1. **Проблемы с SSH подключением** - используйте `clean_known_hosts.yml`
2. **Проблемы с PHP-FPM** - используйте `fix_web.yml`
3. **Проблемы с базой данных** - проверьте подключение и права пользователя
4. **Проблемы с балансировкой** - проверьте health-check эндпоинты

## Безопасность

Рекомендуется после тестирования:
1. Изменить пароли по умолчанию
2. Настроить SSL/TLS для веб-сервисов
3. Ограничить доступ к статистике HAProxy
4. Настроить брандмауэр для ограничения доступа

## Заключение

Данный проект предоставляет полную автоматизацию развертывания высокодоступного веб-кластера с балансировкой нагрузки и репликацией данных. Система масштабируема - можно легко добавить дополнительные веб-серверы в пул балансировщика.
